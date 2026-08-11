import Foundation
import iOSRecorder

/// Returns one fixed artifact every time, or `nil` to stand in for a source that had nothing to measure.
public struct FakeSource: Source {
    public let kind: ArtifactKind
    private let artifact: Artifact?

    public init(kind: ArtifactKind = .log, artifact: Artifact? = .log(text: "fake")) {
        self.kind = kind
        self.artifact = artifact
    }

    public func measure(_ context: RecordContext) async -> Artifact? { artifact }
}

/// Keeps every saved capture in memory, in order, with no eviction, so a test can assert on the whole history.
///
/// Saving appends without replacing an existing id, unlike the real stores, so a test that saves the same
/// capture twice sees two entries and fetches the first.
public actor FakeRecordStore: RecordStore {
    public private(set) var saved: [Record] = []

    public init() {}

    public func save(_ record: Record) async throws {
        saved.append(record)
    }

    public func query(_ query: RecordQuery) async throws -> [RecordSummary] {
        saved.map(RecordSummary.init(record:)).filter(query.matches)
    }

    public func fetch(_ id: RecordID) async throws -> Record {
        guard let record = saved.first(where: { $0.id == id }) else {
            throw RecordStoreError.notFound(id)
        }
        return record
    }

    public func delete(_ id: RecordID) async throws {
        saved.removeAll { $0.id == id }
    }

    public func removeAll() async throws {
        saved.removeAll()
    }

    public func savedCount() -> Int { saved.count }
}

/// Records what it was asked to export, or throws on every call when built to fail.
public actor FakeExporter: Exporter {
    public private(set) var exported: [Record] = []
    private let shouldThrow: Bool
    public nonisolated let label: String

    public init(shouldThrow: Bool = false, label: String = "FakeExporter") {
        self.shouldThrow = shouldThrow
        self.label = label
    }

    public func export(_ record: Record) async throws {
        if shouldThrow { throw ExporterError.transportFailed("fake") }
        exported.append(record)
    }

    public func exportedCount() -> Int { exported.count }
}

/// Goes offline and back online mid-test, which is what the outbox retry path needs to be exercised.
public actor FlakyExporter: Exporter {
    public private(set) var exported: [Record] = []
    private var online: Bool
    public nonisolated let label = "FlakyExporter"

    public init(online: Bool = false) {
        self.online = online
    }

    public func setOnline(_ value: Bool) { online = value }

    public func export(_ record: Record) async throws {
        guard online else { throw ExporterError.transportFailed("offline") }
        exported.append(record)
    }

    public func exportedCount() -> Int { exported.count }
}

/// Fails every call, standing in for a store whose backing directory is gone or unreadable.
///
/// This is what separates "there are no captures" from "the captures cannot be read" — two answers a
/// caller has to be able to tell apart, and which a swallowed error collapses into one.
public actor FailingRecordStore: RecordStore, StorageReporting {
    public struct Failure: Error, Equatable {
        public let operation: String
        public init(operation: String) { self.operation = operation }
    }

    public init() {}

    public func save(_ record: Record) async throws { throw Failure(operation: "save") }
    public func query(_ query: RecordQuery) async throws -> [RecordSummary] { throw Failure(operation: "query") }
    public func fetch(_ id: RecordID) async throws -> Record { throw Failure(operation: "fetch") }
    public func delete(_ id: RecordID) async throws { throw Failure(operation: "delete") }
    public func removeAll() async throws { throw Failure(operation: "removeAll") }

    public func storageInfo() async -> StorageInfo {
        StorageInfo(totalRecords: 0, totalBytes: 0, oldestRecordedAt: nil, newestRecordedAt: nil, location: "unreadable")
    }
}
