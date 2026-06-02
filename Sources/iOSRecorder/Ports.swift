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
    func export(_ record: Record) async throws
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
}
