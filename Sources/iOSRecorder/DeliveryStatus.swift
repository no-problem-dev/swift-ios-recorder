import Foundation

/// The result of one export attempt, kept so a failed delivery stays visible instead of vanishing.
///
/// `error` holds the thrown error's description; it is the only trace of a failure, since exporting never
/// throws back to whoever asked for the capture.
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

/// What a list row can say about one capture's delivery, folded down from its per-exporter outcomes.
public enum DeliveryState: Sendable, Equatable {
    /// No exporter is attached, so the capture only ever existed on the device.
    case notExported
    /// Every exporter accepted it.
    case delivered
    /// Not sent yet, or the last attempt failed; `reason` carries the error text when there was one.
    case pending(reason: String?)

    public var isDelivered: Bool { if case .delivered = self { return true } else { return false } }
}
