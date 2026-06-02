import Testing
import Foundation
@testable import iOSRecorder

private let ctx = RecordContext(session: SessionID(rawValue: "s"))

@Suite struct StateSourceTests {
    @Test func encodesProvidedJSON() async {
        let source = StateSource { Data("{\"a\":1}".utf8) }
        let artifact = await source.measure(ctx)
        #expect(artifact?.kind == .state)
        #expect(String(decoding: artifact!.data, as: UTF8.self) == "{\"a\":1}")
    }

    @Test func encodesEncodableValue() async {
        struct State: Codable, Sendable { let count: Int }
        let source = StateSource(encoding: { State(count: 3) })
        let artifact = await source.measure(ctx)
        #expect(String(decoding: artifact!.data, as: UTF8.self).contains("\"count\":3"))
    }
}

@Suite struct TypedStateSourceTests {
    struct AgentResponse: Codable, Sendable { let intent: String; let confidence: Double }

    @Test func stampsSwiftTypeNameAndCustomKind() async {
        let kind = ArtifactKind(rawValue: "agent_response")
        let source = TypedStateSource(kind: kind) { AgentResponse(intent: "search", confidence: 0.9) }
        let artifact = await source.measure(ctx)
        #expect(artifact?.kind == kind)
        #expect(artifact?.attributes["type"] == "AgentResponse")
        let json = String(decoding: artifact!.data, as: UTF8.self)
        #expect(json.contains("\"intent\":\"search\""))
    }

    @Test func defaultsToStateKind() async {
        let source = TypedStateSource { AgentResponse(intent: "plan", confidence: 0.5) }
        let artifact = await source.measure(ctx)
        #expect(artifact?.kind == .state)
    }

    @Test func nilProviderSkipsMeasurement() async {
        let source = TypedStateSource { Optional<AgentResponse>.none }
        #expect(await source.measure(ctx) == nil)
    }

    @Test func explicitTypeNameOverridesDefault() async {
        let source = TypedStateSource(kind: .state, typeName: "Custom") { ["k": 1] }
        let artifact = await source.measure(ctx)
        #expect(artifact?.attributes["type"] == "Custom")
    }
}

@Suite struct EventSourceTests {
    struct AgentResponse: Codable, Sendable, Equatable { let intent: String }

    @Test func snapshotsBufferedEventsAsArray() async {
        let buffer = EventBuffer<AgentResponse>()
        await buffer.append(AgentResponse(intent: "search"))
        await buffer.append(AgentResponse(intent: "plan"))
        let source = EventSource(kind: ArtifactKind(rawValue: "agent_response"), buffer: buffer)
        let artifact = await source.measure(ctx)
        #expect(artifact?.kind == ArtifactKind(rawValue: "agent_response"))
        #expect(artifact?.attributes["type"] == "AgentResponse")
        #expect(artifact?.attributes["count"] == "2")
        let json = String(decoding: artifact!.data, as: UTF8.self)
        #expect(json.contains("search") && json.contains("plan"))
    }

    @Test func emptyBufferYieldsNoArtifact() async {
        let source = EventSource(buffer: EventBuffer<AgentResponse>())
        #expect(await source.measure(ctx) == nil)
    }

    @Test func bufferEvictsBeyondCapacity() async {
        let buffer = EventBuffer<AgentResponse>(capacity: 2)
        await buffer.append(AgentResponse(intent: "a"))
        await buffer.append(AgentResponse(intent: "b"))
        await buffer.append(AgentResponse(intent: "c"))
        let items = await buffer.snapshot()
        #expect(items.map(\.intent) == ["b", "c"])
    }

    @Test func clearEmptiesBuffer() async {
        let buffer = EventBuffer<AgentResponse>()
        await buffer.append(AgentResponse(intent: "x"))
        await buffer.clear()
        #expect(await buffer.snapshot().isEmpty)
    }
}

@Suite struct LogSourceTests {
    @Test func snapshotsBuffer() async {
        let buffer = LogBuffer()
        await buffer.append("line1")
        await buffer.append("line2")
        let source = LogSource(buffer: buffer)
        let artifact = await source.measure(ctx)
        #expect(String(decoding: artifact!.data, as: UTF8.self) == "line1\nline2")
    }

    @Test func bufferEvictsBeyondCapacity() async {
        let buffer = LogBuffer(capacity: 2)
        await buffer.append("a")
        await buffer.append("b")
        await buffer.append("c")
        #expect(await buffer.snapshot() == "b\nc")
    }

    @Test func emptyLogYieldsNoArtifact() async {
        let source = LogSource { "" }
        let artifact = await source.measure(ctx)
        #expect(artifact == nil)
    }
}
