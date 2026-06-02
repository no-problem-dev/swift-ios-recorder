import Foundation

/// 1 回の export 試行の結果。握り潰さず観測できるようにするための記録。
public struct ExportOutcome: Sendable, Equatable, Codable {
    public let recordID: RecordID
    public let exporter: String
    public let succeeded: Bool
    public let error: String?
    public let at: Date

    public init(recordID: RecordID, exporter: String, succeeded: Bool, error: String? = nil, at: Date) {
        self.recordID = recordID
        self.exporter = exporter
        self.succeeded = succeeded
        self.error = error
        self.at = at
    }
}

/// あるキャプチャの配送状態（UI 表示用に畳んだ要約）。
public enum DeliveryState: Sendable, Equatable {
    /// exporter が無い（保持のみ）。
    case notExported
    /// 全 exporter 成功。
    case delivered
    /// まだ未送 or 送信失敗（再送待ち）。
    case pending(reason: String?)

    public var isDelivered: Bool { if case .delivered = self { return true } else { return false } }
}
