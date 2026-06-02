import Foundation
import iOSRecorder

public extension ArtifactKind {
    /// 直近の HTTP 通信ログ。新種を core に足さず、生産者（このターゲット）側で定義する。
    static let network = ArtifactKind(rawValue: "network")
}

/// ライブな通信バッファを capture 時点でスナップショットし、1 つの Artifact にする Source。
/// 連続ストリームを「1 トリガ = 1 Record」の不変項に合わせて畳み込む。
/// 外に出す前に機密ヘッダのマスクとボディ truncate を必ず通す。
public struct NetworkSource: Source {
    public let kind = ArtifactKind.network
    private let store: NetworkLogStore
    private let maxEntries: Int
    private let bodyLimit: Int

    public init(store: NetworkLogStore, maxEntries: Int = 50, bodyLimit: Int = 4096) {
        self.store = store
        self.maxEntries = max(1, maxEntries)
        self.bodyLimit = bodyLimit
    }

    public func measure(_ context: RecordContext) async -> Artifact? {
        let entries = await snapshot()
        guard !entries.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return nil }
        return Artifact(
            kind: .network,
            mediaType: "application/json",
            data: data,
            attributes: ["type": "NetworkLog", "count": "\(entries.count)"]
        )
    }

    private func snapshot() async -> [NetworkLog] {
        let limit = maxEntries
        let limitBytes = bodyLimit
        return await MainActor.run {
            store.logs.prefix(limit).map { $0.redacted(bodyLimit: limitBytes) }
        }
    }
}
