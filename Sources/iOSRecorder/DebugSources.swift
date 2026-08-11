import Foundation

public extension ArtifactKind {
    /// A run of debug events, folded into one JSON array by ``DebugLogSource``.
    static let debugTimeline = ArtifactKind(rawValue: "debug_timeline")
    /// Numbers derived from that run by ``MetricsSource``.
    static let metrics = ArtifactKind(rawValue: "metrics")
}

/// Folds the tail of a debug log into one JSON array whenever a capture is taken.
///
/// Only the last `maxEvents` entries travel, and an empty log yields no artifact at all — a capture taken before
/// anything was logged simply has no timeline attached. Reading the log hops to the main actor.
public struct DebugLogSource: Source {
    public let kind = ArtifactKind.debugTimeline
    private let log: DebugLog
    private let maxEvents: Int
    private let maxPayloadBytes: Int

    /// - Parameter maxPayloadBytes: Ceiling for each event's payload. Outliers such as a whole prompt are cut
    ///   here, before they can reach storage or the wire; the original size stays in the event's attributes.
    public init(log: DebugLog, maxEvents: Int = 500, maxPayloadBytes: Int = 8192) {
        self.log = log
        self.maxEvents = max(1, maxEvents)
        self.maxPayloadBytes = max(0, maxPayloadBytes)
    }

    public func measure(_ context: RecordContext) async -> Artifact? {
        let limit = maxEvents
        let payloadLimit = maxPayloadBytes
        let events = await MainActor.run {
            log.events.suffix(limit).map { $0.withPayloadLimited(to: payloadLimit) }
        }
        guard !events.isEmpty else { return nil }
        guard let data = try? Self.encoder.encode(events) else { return nil }
        return Artifact(
            kind: .debugTimeline,
            mediaType: "application/json",
            data: data,
            attributes: ["type": "DebugEvent", "count": "\(events.count)"]
        )
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

/// Runs the given extractors over the whole debug log at capture time and folds their numbers into one artifact.
///
/// Unlike the timeline source this reads every event still in the log, not just the tail. Extractors that find
/// nothing produce no artifact rather than an empty one.
public struct MetricsSource: Source {
    public let kind = ArtifactKind.metrics
    private let log: DebugLog
    private let extractors: [any MetricExtractor]

    public init(log: DebugLog, extractors: [any MetricExtractor]) {
        self.log = log
        self.extractors = extractors
    }

    public func measure(_ context: RecordContext) async -> Artifact? {
        let events = await MainActor.run { log.events }
        let metrics = extractors.flatMap { $0.metrics(from: events) }
        guard !metrics.isEmpty else { return nil }
        guard let data = try? DebugLogSource.encoder.encode(metrics) else { return nil }
        return Artifact(
            kind: .metrics,
            mediaType: "application/json",
            data: data,
            attributes: ["type": "DebugMetric", "count": "\(metrics.count)"]
        )
    }
}
