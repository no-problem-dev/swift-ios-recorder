import Foundation

/// Counts events grouped by `category.name`, which covers most of what a timeline is asked, with no domain code.
///
/// A group that never occurred produces no metric at all rather than a zero, so an absent `decode_failed` row
/// means nothing happened, not that counting failed.
public struct CountMetricExtractor: MetricExtractor {
    private let category: String?

    /// - Parameter category: Count only within this category; `nil` counts every event in the timeline.
    public init(category: String? = nil) {
        self.category = category
    }

    public func metrics(from events: [DebugEvent]) -> [DebugMetric] {
        let filtered = category.map { c in events.filter { $0.category == c } } ?? events
        let groups = Dictionary(grouping: filtered) { "\($0.category).\($0.name)" }
        return groups.compactMap { key, group -> DebugMetric? in
            guard let first = group.first else { return nil }
            return DebugMetric(name: key, value: Double(group.count), unit: "count", category: first.category)
        }
        .sorted { $0.name < $1.name }
    }
}

/// Measures how long the whole timeline spans, from earliest event to latest.
///
/// Yields nothing when there are fewer than two distinct timestamps, so a single event reports no duration
/// rather than zero.
public struct SpanMetricExtractor: MetricExtractor {
    public init() {}

    public func metrics(from events: [DebugEvent]) -> [DebugMetric] {
        let times = events.map(\.at)
        guard let first = times.min(), let last = times.max(), last > first else { return [] }
        return [DebugMetric(name: "timeline.durationSeconds", value: last.timeIntervalSince(first), unit: "s", category: "metric")]
    }
}
