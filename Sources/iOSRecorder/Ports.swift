import Foundation

/// 計測の文脈。Source に渡される。
public struct RecordContext: Sendable {
    public let session: SessionID
    public let screenName: String?
    public let attributes: [String: String]

    public init(session: SessionID, screenName: String? = nil, attributes: [String: String] = [:]) {
        self.session = session
        self.screenName = screenName
        self.attributes = attributes
    }
}

/// 計測ポート: 何を測るか。種別ごとに 1 実装（拡張軸）。
public protocol Source: Sendable {
    var kind: ArtifactKind { get }
    func measure(_ context: RecordContext) async -> Artifact?
}

/// 保持ポート: 保存・検索・取得・全削除（コアのユースケース本体）。
public protocol RecordStore: Sendable {
    func save(_ record: Record) async throws
    func query(_ query: RecordQuery) async throws -> [RecordSummary]
    func fetch(_ id: RecordID) async throws -> Record
    func delete(_ id: RecordID) async throws
    func removeAll() async throws
}

/// 出力ポート: 保持した記録を外へ出す能力（Bonjour / iCloud / file …）。
public protocol Exporter: Sendable {
    /// 観測用ラベル（どの出力経路か）。既定は型名。
    var label: String { get }
    func export(_ record: Record) async throws
}

public extension Exporter {
    var label: String { String(describing: type(of: self)) }
}

/// 受信ポート（下流の消費者側）: Export の対向。
public protocol RecordReceiver: Sendable {
    func records() -> AsyncThrowingStream<Record, any Error>
}

/// 直列化ポート: ワイヤ形式（JSON / Protobuf …）。
public protocol RecordCodec: Sendable {
    func encode(_ record: Record) throws -> Data
    func decode(_ data: Data) throws -> Record
}

public enum RecordStoreError: Error, Sendable, Equatable {
    case notFound(RecordID)
}

public enum ExporterError: Error, Sendable, Equatable {
    case notImplemented(String)
    case transportFailed(String)
    /// 記録が転送路の上限を超えていて、再試行しても永遠に送れない。
    /// outbox はこれを退避せず破棄してよい（先頭詰まり防止）。
    case payloadTooLarge(bytes: Int)
}

/// 保持領域の使用状況。MCP の get_storage_info が返す。
public struct StorageInfo: Sendable, Codable, Equatable {
    public let totalRecords: Int
    public let totalBytes: Int
    public let oldestRecordedAt: Date?
    public let newestRecordedAt: Date?
    public let location: String?

    public init(
        totalRecords: Int,
        totalBytes: Int,
        oldestRecordedAt: Date? = nil,
        newestRecordedAt: Date? = nil,
        location: String? = nil
    ) {
        self.totalRecords = totalRecords
        self.totalBytes = totalBytes
        self.oldestRecordedAt = oldestRecordedAt
        self.newestRecordedAt = newestRecordedAt
        self.location = location
    }
}

/// 保持領域の使用状況を報告できる能力（Store 実装が任意で備える）。
public protocol StorageReporting: Sendable {
    func storageInfo() async -> StorageInfo
}
