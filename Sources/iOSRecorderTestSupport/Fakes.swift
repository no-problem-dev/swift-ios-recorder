import Foundation
import iOSRecorder

/// 任意の Artifact（または nil）を返す Source。
public struct FakeSource: Source {
    public let kind: ArtifactKind
    private let artifact: Artifact?

    public init(kind: ArtifactKind = .log, artifact: Artifact? = .log(text: "fake")) {
        self.kind = kind
        self.artifact = artifact
    }

    public func measure(_ context: RecordContext) async -> Artifact? { artifact }
}

/// 保存した記録を覚えておく in-memory な RecordStore。
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

/// export 呼び出しを記録する Exporter。任意で失敗させられる。
public actor FakeExporter: Exporter {
    public private(set) var exported: [Record] = []
    private let shouldThrow: Bool

    public init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    public func export(_ record: Record) async throws {
        if shouldThrow { throw ExporterError.transportFailed("fake") }
        exported.append(record)
    }

    public func exportedCount() -> Int { exported.count }
}
