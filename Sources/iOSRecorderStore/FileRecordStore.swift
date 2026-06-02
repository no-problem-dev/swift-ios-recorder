import Foundation
import iOSRecorder

/// ファイルシステム上の保持実装。1 record = 1 フォルダ（Finder で覗ける）。
///
/// ```
/// <root>/<recordID>/meta.json
/// <root>/<recordID>/0-screenshot.png
/// <root>/<recordID>/1-state.json
/// ```
public actor FileRecordStore: RecordStore {
    private let rootURL: URL
    private let maxRecords: Int?
    private let fileManager = FileManager.default

    /// - Parameter maxRecords: 指定すると save 時に古い記録を自動削除して件数を保つ。
    public init(rootURL: URL, maxRecords: Int? = nil) {
        self.rootURL = rootURL
        self.maxRecords = maxRecords
    }

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

        if let maxRecords { pruneToLimit(maxRecords) }
    }

    public func query(_ query: RecordQuery) async throws -> [RecordSummary] {
        let summaries = loadAllMeta()
            .map { $0.summary }
            .filter(query.matches)
            .sorted { $0.recordedAt > $1.recordedAt }
        return Array(summaries.prefix(query.limit))
    }

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

    public func delete(_ id: RecordID) async throws {
        let recordDir = rootURL.appendingPathComponent(id.rawValue, isDirectory: true)
        try? fileManager.removeItem(at: recordDir)
    }

    public func removeAll() async throws {
        guard let dirs = try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else { return }
        for dir in dirs {
            try? fileManager.removeItem(at: dir)
        }
    }

    // MARK: - Helpers

    /// 新しい順に maxRecords 件だけ残して古いフォルダを削除する。
    private func pruneToLimit(_ maxRecords: Int) {
        let metas = loadAllMeta().sorted { $0.recordedAt > $1.recordedAt }
        guard metas.count > maxRecords else { return }
        for meta in metas.dropFirst(maxRecords) {
            try? fileManager.removeItem(at: rootURL.appendingPathComponent(meta.id, isDirectory: true))
        }
    }

    private func loadAllMeta() -> [StoredRecord] {
        guard let dirs = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return dirs.compactMap { dir in
            let metaURL = dir.appendingPathComponent("meta.json")
            guard let data = try? Data(contentsOf: metaURL) else { return nil }
            return try? Self.decoder.decode(StoredRecord.self, from: data)
        }
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
