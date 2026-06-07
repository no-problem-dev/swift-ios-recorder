import Testing
import Foundation
@testable import iOSRecorder

@Suite struct DebugEventPayloadLimitTests {
    @Test func smallPayloadIsUntouched() {
        let event = DebugEvent(category: "session", name: "prompt", summary: "s", text: "short")
        let limited = event.withPayloadLimited(to: 8192)
        #expect(limited.payload == event.payload)
        #expect(limited.attributes["payloadTruncated"] == nil)
    }

    @Test func oversizedPayloadIsTruncatedWithMeta() {
        let big = String(repeating: "p", count: 10_000)
        let event = DebugEvent(category: "session", name: "system_prompt", summary: "s", text: big)
        let limited = event.withPayloadLimited(to: 1024)
        #expect(limited.payload!.count <= 1024)
        #expect(limited.attributes["payloadTruncated"] == "true")
        #expect(limited.attributes["payloadOriginalBytes"] == "10000")
        #expect(limited.id == event.id)
        #expect(limited.summary == event.summary)
    }

    @Test func truncationRespectsUTF8Boundaries() {
        // "あ" = 3 bytes。limit 1000 は 3 の倍数でない → 境界を落として有効な UTF-8 に保つ。
        let event = DebugEvent(category: "agent", name: "completed", summary: "s",
                               text: String(repeating: "あ", count: 1000))
        let limited = event.withPayloadLimited(to: 1000)
        let decoded = String(data: limited.payload!, encoding: .utf8)
        #expect(decoded != nil)
        #expect(decoded!.allSatisfy { $0 == "あ" })
    }

    @Test func nilPayloadStaysNil() {
        let event = DebugEvent(category: "a", name: "n", summary: "s")
        #expect(event.withPayloadLimited(to: 10).payload == nil)
    }
}

@MainActor
@Suite struct DebugLogSourcePayloadTests {
    private let ctx = RecordContext(session: SessionID(rawValue: "s"))

    @Test func capsEachEventPayloadAtCaptureTime() async {
        let log = DebugLog()
        log.emit(DebugEvent(category: "session", name: "system_prompt", summary: "53KB prompt",
                              text: String(repeating: "x", count: 50_000)))
        log.emit(DebugEvent(category: "agent", name: "done", summary: "ok", text: "tiny"))

        let source = DebugLogSource(log: log, maxPayloadBytes: 1024)
        let artifact = await source.measure(ctx)

        let events = try! JSONDecoder.iso().decode([DebugEvent].self, from: artifact!.data)
        #expect(events.count == 2)
        let prompt = events.first { $0.name == "system_prompt" }!
        #expect(prompt.payload!.count <= 1024)
        #expect(prompt.attributes["payloadOriginalBytes"] == "50000")
        let done = events.first { $0.name == "done" }!
        #expect(String(data: done.payload!, encoding: .utf8) == "tiny")
        // artifact 全体が劇的に小さくなっている（53KB → 数 KB）
        #expect(artifact!.data.count < 5_000)
    }

    @Test func defaultLimitKeepsTypicalEventsIntact() async {
        let log = DebugLog()
        log.emit(DebugEvent(category: "a2ui", name: "surface", summary: "s", text: String(repeating: "y", count: 4_000)))
        let source = DebugLogSource(log: log)
        let artifact = await source.measure(ctx)
        let events = try! JSONDecoder.iso().decode([DebugEvent].self, from: artifact!.data)
        #expect(events.first?.payload?.count == 4_000)
        #expect(events.first?.attributes["payloadTruncated"] == nil)
    }
}

private extension JSONDecoder {
    static func iso() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
