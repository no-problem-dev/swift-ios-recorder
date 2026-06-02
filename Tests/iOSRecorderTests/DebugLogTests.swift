import Testing
import Foundation
@testable import iOSRecorder

private let ctx = RecordContext(session: SessionID(rawValue: "s"))
private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func event(_ category: String, _ name: String, _ summary: String = "x", offset: TimeInterval = 0, attrs: [String: String] = [:]) -> DebugEvent {
    DebugEvent(at: t0.addingTimeInterval(offset), category: category, name: name, summary: summary, attributes: attrs)
}

@MainActor
@Suite struct DebugLogTests {
    @Test func emitsAndFiltersByCategory() {
        let log = DebugLog()
        log.emit(event("agent", "tool_call"))
        log.emit(event("a2ui", "surface_created"))
        log.emit(event("agent", "completed"))
        #expect(log.events.count == 3)
        #expect(log.events(in: "agent").count == 2)
        #expect(log.categories == ["agent", "a2ui"])
    }

    @Test func evictsBeyondCapacity() {
        let log = DebugLog(capacity: 2)
        log.emit(event("agent", "a"))
        log.emit(event("agent", "b"))
        log.emit(event("agent", "c"))
        #expect(log.events.map(\.name) == ["b", "c"])
    }
}

@MainActor
@Suite struct DebugSourcesTests {
    @Test func debugLogSourceFoldsEventsIntoTimelineArtifact() async {
        let log = DebugLog()
        log.emit(event("agent", "tool_call", "🔧 web_search", attrs: ["toolName": "web_search"]))
        log.emit(event("a2ui", "surface_created", "surface s1"))
        let source = DebugLogSource(log: log)
        let artifact = await source.measure(ctx)
        #expect(artifact?.kind == .debugTimeline)
        #expect(artifact?.attributes["count"] == "2")
        let json = String(decoding: artifact!.data, as: UTF8.self)
        #expect(json.contains("web_search"))
        #expect(json.contains("surface_created"))
    }

    @Test func emptyLogYieldsNoArtifact() async {
        let source = DebugLogSource(log: DebugLog())
        #expect(await source.measure(ctx) == nil)
    }

    @Test func metricsSourceRunsExtractors() async {
        let log = DebugLog()
        log.emit(event("agent", "tool_call"))
        log.emit(event("agent", "tool_call"))
        log.emit(event("a2ui", "surface_created"))
        let source = MetricsSource(log: log, extractors: [CountByCategoryExtractor()])
        let artifact = await source.measure(ctx)
        #expect(artifact?.kind == .metrics)
        let json = String(decoding: artifact!.data, as: UTF8.self)
        #expect(json.contains("agent"))
        #expect(json.contains("\"value\":2"))
    }
}

/// テスト用: カテゴリごとのイベント数を数えるだけの抽出器。
private struct CountByCategoryExtractor: MetricExtractor {
    func metrics(from events: [DebugEvent]) -> [DebugMetric] {
        Dictionary(grouping: events, by: \.category).map { category, group in
            DebugMetric(name: "events", value: Double(group.count), unit: "count", category: category)
        }
    }
}

@Suite struct DebugMetricsTests {
    @Test func countsByCategoryAndName() {
        let events = [
            event("agent", "tool_call"), event("agent", "tool_call"),
            event("agent", "completed"), event("a2ui", "decode_failed")
        ]
        let metrics = CountMetricExtractor().metrics(from: events)
        let toolCalls = metrics.first { $0.name == "agent.tool_call" }
        #expect(toolCalls?.value == 2)
        #expect(metrics.first { $0.name == "a2ui.decode_failed" }?.value == 1)
    }

    @Test func filtersByCategory() {
        let events = [event("agent", "tool_call"), event("a2ui", "surface_created")]
        let metrics = CountMetricExtractor(category: "a2ui").metrics(from: events)
        #expect(metrics.count == 1)
        #expect(metrics.first?.category == "a2ui")
    }

    @Test func spanMeasuresDuration() {
        let events = [event("agent", "a", offset: 0), event("agent", "b", offset: 2.5)]
        let span = SpanMetricExtractor().metrics(from: events)
        #expect(span.first?.name == "timeline.durationSeconds")
        #expect(span.first?.value == 2.5)
    }

    @Test func spanEmptyForSingleEvent() {
        #expect(SpanMetricExtractor().metrics(from: [event("agent", "a")]).isEmpty)
    }
}

@Suite struct DebugReportTests {
    @Test func rendersMarkdown() {
        let report = DebugReport(title: "Agent Trace", sections: [
            .init(title: "Steps", lines: ["thinking", "tool_call web_search", "completed"])
        ])
        let md = report.markdown()
        #expect(md.contains("# Agent Trace"))
        #expect(md.contains("## Steps"))
        #expect(md.contains("- tool_call web_search"))
    }
}
