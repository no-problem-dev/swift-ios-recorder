import Foundation

/// イベントを `category.name` 単位で数える汎用メトリクス抽出器。
/// ドメイン固有コード不要で、正規化済み DebugEvent から tool_call 数や decode_failed 数等を出せる。
public struct CountMetricExtractor: MetricExtractor {
    private let category: String?

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

/// 最初と最後のイベントの時間差（タイムライン全体の所要時間）を出す抽出器。
public struct SpanMetricExtractor: MetricExtractor {
    public init() {}

    public func metrics(from events: [DebugEvent]) -> [DebugMetric] {
        let times = events.map(\.at)
        guard let first = times.min(), let last = times.max(), last > first else { return [] }
        return [DebugMetric(name: "timeline.durationSeconds", value: last.timeIntervalSince(first), unit: "s", category: "metric")]
    }
}
