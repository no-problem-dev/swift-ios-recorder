import Foundation
import iOSRecorder

/// Keeps records as plain files, one folder per record, so they can be opened in Finder without
/// this package.
///
/// ```
/// <root>/<recordID>/meta.json
/// <root>/<recordID>/0-screenshot.jpg
/// <root>/<recordID>/1-state.json
/// ```
///
/// The Mac companion points `root` at `~/.iosrecorder/captures`. Artifacts are written first and
/// `meta.json` last, and a folder without a readable `meta.json` is ignored everywhere — so a save
/// cut short leaves files on disk that no query, fetch or retention pass will ever return or remove.
public actor FileRecordStore: RecordStore, StorageReporting {
    private let rootURL: URL
    private let maxRecords: Int?
    private let fileManager = FileManager.default
    /// Result of the last full `meta.json` sweep, reused until the root directory's modification
    /// time changes. Adding or deleting a record creates or removes a folder, which always shows up
    /// there — including when another process does it, which is how `serve` and `mcp` stay in step.
    private var cachedMeta: [StoredRecord] = []
    private var cacheStamp: Date?

    /// - Parameters:
    ///   - rootURL: Directory that holds one folder per record. Created on the first save; it does
    ///     not have to exist yet.
    ///   - maxRecords: Cap on kept records. Each save deletes the oldest folders beyond it, by
    ///     recorded time rather than by size. Without it the directory grows without bound.
    public init(rootURL: URL, maxRecords: Int? = nil) {
        self.rootURL = rootURL
        self.maxRecords = maxRecords
    }

    /// Writes the record's artifacts and then its `meta.json`, and prunes to `maxRecords`.
    ///
    /// Saving an id that already exists overwrites files position by position; artifact files left
    /// over from a longer previous version of the same record stay on disk, unreferenced by the new
    /// `meta.json`.
    ///
    /// - Throws: Whatever the file system reports. A throw part-way through leaves a folder that no
    ///   query will list, since `meta.json` is written last.
    public func save(_ record: Record) async throws {
        let recordDir = rootURL.appendingPathComponent(record.id.rawValue, isDirectory: true)
        try fileManager.createDirectory(at: recordDir, withIntermediateDirectories: true)

        var stored: [StoredArtifact] = []
        for (index, artifact) in record.artifacts.enumerated() {
            let fileName = "\(index)-\(artifact.kind.rawValue).\(Self.fileExtension(for: artifact.mediaType))"
            try artifact.data.write(to: recordDir.appendingPathComponent(fileName))
            stored.append(StoredArtifact(
                kind: artifact.kind.rawValue,
                mediaType: artifact.mediaType,
                file: fileName,
                attributes: artifact.attributes
            ))
        }

        let meta = StoredRecord(
            id: record.id.rawValue,
            session: record.session.rawValue,
            recordedAt: record.recordedAt,
            screenName: record.metadata.screenName,
            appVersion: record.metadata.appVersion,
            tags: record.metadata.tags,
            attributes: record.metadata.attributes,
            artifacts: stored
        )
        try Self.encoder.encode(meta).write(to: recordDir.appendingPathComponent("meta.json"))
        invalidateCache()

        if let maxRecords { pruneToLimit(maxRecords) }
    }

    public func query(_ query: RecordQuery) async throws -> [RecordSummary] {
        let summaries = loadAllMeta()
            .map { $0.summary }
            .filter(query.matches)
            .sorted { $0.recordedAt > $1.recordedAt }
        return Array(summaries.prefix(query.limit))
    }

    /// Reads a record back with its artifact bytes loaded.
    ///
    /// - Throws: `RecordStoreError.notFound` when the folder or its `meta.json` is missing or
    ///   unreadable; a file system error when `meta.json` names an artifact file that is not there.
    public func fetch(_ id: RecordID) async throws -> Record {
        let recordDir = rootURL.appendingPathComponent(id.rawValue, isDirectory: true)
        let metaURL = recordDir.appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? Self.decoder.decode(StoredRecord.self, from: data) else {
            throw RecordStoreError.notFound(id)
        }

        let artifacts: [Artifact] = try meta.artifacts.map { stored in
            let data = try Data(contentsOf: recordDir.appendingPathComponent(stored.file))
            return Artifact(
                kind: ArtifactKind(rawValue: stored.kind),
                mediaType: stored.mediaType,
                data: data,
                attributes: stored.attributes
            )
        }
        return meta.record(artifacts: artifacts)
    }

    /// Removes one record's folder. Succeeds whether or not it was there, and reports nothing when
    /// the file system refuses.
    public func delete(_ id: RecordID) async throws {
        let recordDir = rootURL.appendingPathComponent(id.rawValue, isDirectory: true)
        try? fileManager.removeItem(at: recordDir)
        invalidateCache()
    }

    /// Empties the root directory. Everything directly inside it goes, whether or not it looks like
    /// a record, so point `rootURL` at a directory this store owns.
    public func removeAll() async throws {
        guard let dirs = try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else { return }
        for dir in dirs {
            try? fileManager.removeItem(at: dir)
        }
        invalidateCache()
    }

    /// Count, bytes on disk and the span of recorded times — what the `get_storage_info` tool
    /// reports. The byte total walks every file under the root, so it includes leftovers that the
    /// count does not.
    public func storageInfo() async -> StorageInfo {
        let metas = loadAllMeta()
        let dates = metas.map(\.recordedAt)
        return StorageInfo(
            totalRecords: metas.count,
            totalBytes: totalBytesOnDisk(),
            oldestRecordedAt: dates.min(),
            newestRecordedAt: dates.max(),
            location: rootURL.path
        )
    }

    private func totalBytesOnDisk() -> Int {
        let files = (fileManager.enumerator(at: rootURL, includingPropertiesForKeys: [.fileSizeKey])?
            .allObjects as? [URL]) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    // MARK: - Helpers

    /// Keeps the newest `maxRecords` folders and deletes the rest. Ordered by recorded time, not by
    /// write time, so a record that arrives late with an old timestamp is the first to go.
    private func pruneToLimit(_ maxRecords: Int) {
        let metas = loadAllMeta().sorted { $0.recordedAt > $1.recordedAt }
        guard metas.count > maxRecords else { return }
        for meta in metas.dropFirst(maxRecords) {
            try? fileManager.removeItem(at: rootURL.appendingPathComponent(meta.id, isDirectory: true))
        }
    }

    private func invalidateCache() {
        cacheStamp = nil
    }

    private func rootModificationDate() -> Date? {
        (try? fileManager.attributesOfItem(atPath: rootURL.path))?[.modificationDate] as? Date
    }

    private func loadAllMeta() -> [StoredRecord] {
        // Reading the root's timestamp also picks up changes made by another process, which is the
        // case when `serve` receives while `mcp` reads.
        if let stamp = rootModificationDate(), stamp == cacheStamp { return cachedMeta }

        guard let dirs = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        ) else { return [] }

        let metas = dirs.compactMap { dir -> StoredRecord? in
            let metaURL = dir.appendingPathComponent("meta.json")
            guard let data = try? Data(contentsOf: metaURL) else { return nil }
            return try? Self.decoder.decode(StoredRecord.self, from: data)
        }
        cachedMeta = metas
        cacheStamp = rootModificationDate()
        return metas
    }

    static func fileExtension(for mediaType: String) -> String {
        switch mediaType {
        case "image/png": "png"
        case "image/jpeg": "jpg"
        case "application/json": "json"
        case "text/plain": "log"
        default: "bin"
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct StoredRecord: Codable {
    let id: String
    let session: String
    let recordedAt: Date
    let screenName: String?
    let appVersion: String?
    let tags: [String]
    let attributes: [String: String]
    let artifacts: [StoredArtifact]

    var metadata: RecordMetadata {
        RecordMetadata(screenName: screenName, appVersion: appVersion, tags: tags, attributes: attributes)
    }

    var summary: RecordSummary {
        RecordSummary(
            id: RecordID(rawValue: id),
            session: SessionID(rawValue: session),
            recordedAt: recordedAt,
            metadata: metadata,
            artifactKinds: artifacts.map { ArtifactKind(rawValue: $0.kind) }
        )
    }

    func record(artifacts: [Artifact]) -> Record {
        Record(
            id: RecordID(rawValue: id),
            session: SessionID(rawValue: session),
            recordedAt: recordedAt,
            metadata: metadata,
            artifacts: artifacts
        )
    }
}

private struct StoredArtifact: Codable {
    let kind: String
    let mediaType: String
    let file: String
    let attributes: [String: String]
}
