import Foundation

public extension ArtifactKind {
    /// デバッグイベントの時系列。
    static let debugTimeline = ArtifactKind(rawValue: "debug_timeline")
    /// 抽出済みメトリクス。
    static let metrics = ArtifactKind(rawValue: "metrics")
}

/// capture 時に `DebugLog` の直近イベントを 1 つの artifact（JSON 配列）へ畳む Source。
public struct DebugLogSource: Source {
    public let kind = ArtifactKind.debugTimeline
    private let log: DebugLog
    private let maxEvents: Int

    public init(log: DebugLog, maxEvents: Int = 500) {
        self.log = log
        self.maxEvents = max(1, maxEvents)
    }

    public func measure(_ context: RecordContext) async -> Artifact? {
        let limit = maxEvents
        let events = await MainActor.run { Array(log.events.suffix(limit)) }
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

/// capture 時に `MetricExtractor` 群を `DebugLog` のイベントに回し、メトリクスを 1 artifact へ畳む Source。
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
