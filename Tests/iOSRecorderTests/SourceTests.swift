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
