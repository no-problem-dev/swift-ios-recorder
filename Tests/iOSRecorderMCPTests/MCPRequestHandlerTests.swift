import Testing
import Foundation
@testable import iOSRecorderMCP
import iOSRecorder
import iOSRecorderTestSupport

@Suite struct MCPRequestHandlerTests {
    private func makeHandler(seed: [Record] = []) async -> MCPRequestHandler {
        let store = FakeRecordStore()
        for record in seed { try? await store.save(record) }
        return MCPRequestHandler(store: store)
    }

    private func send(_ handler: MCPRequestHandler, _ object: [String: Any]) async -> [String: Any]? {
        let data = try! JSONSerialization.data(withJSONObject: object)
        guard let out = await handler.handle(data) else { return nil }
        return try! JSONSerialization.jsonObject(with: out) as? [String: Any]
    }

    @Test func initializeReturnsServerInfoAndEchoesID() async {
        let handler = await makeHandler()
        let response = await send(handler, ["jsonrpc": "2.0", "id": 1, "method": "initialize"])
        let result = response?["result"] as? [String: Any]
        let serverInfo = result?["serverInfo"] as? [String: Any]
        #expect(serverInfo?["name"] as? String == "ios-recorder")
        #expect(response?["id"] as? Int == 1)
    }

    @Test func notificationsProduceNoResponse() async {
        let handler = await makeHandler()
        let response = await send(handler, ["jsonrpc": "2.0", "method": "notifications/initialized"])
        #expect(response == nil)
    }

    @Test func toolsListExposesAllTools() async {
        let handler = await makeHandler()
        let response = await send(handler, ["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let tools = (response?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        let names = Set(tools?.compactMap { $0["name"] as? String } ?? [])
        #expect(names == ["list_captures", "get_capture", "search_events", "get_event", "delete_capture", "clear_captures"])
    }

    @Test func deleteAndClearToolsRespond() async {
        let handler = await makeHandler(seed: [RecordFixtures.make(id: RecordID(rawValue: "z"))])
        let del = await send(handler, [
            "jsonrpc": "2.0", "id": 8, "method": "tools/call",
            "params": ["name": "delete_capture", "arguments": ["id": "z"]]
        ])
        #expect(((del?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String == "deleted z")

        let clear = await send(handler, [
            "jsonrpc": "2.0", "id": 9, "method": "tools/call",
            "params": ["name": "clear_captures", "arguments": [:]]
        ])
        #expect((clear?["result"] as? [String: Any])?["content"] != nil)
    }

    @Test func listCapturesReturnsSummaryText() async {
        let handler = await makeHandler(seed: [
            RecordFixtures.make(id: RecordID(rawValue: "rec1"), screenName: "Login")
        ])
        let response = await send(handler, [
            "jsonrpc": "2.0", "id": 3, "method": "tools/call",
            "params": ["name": "list_captures", "arguments": [:]]
        ])
        let content = (response?["result"] as? [String: Any])?["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String
        #expect(text?.contains("rec1") == true)
        #expect(text?.contains("Login") == true)
    }

    @Test func listCapturesAppliesFilter() async {
        let handler = await makeHandler(seed: [
            RecordFixtures.make(id: RecordID(rawValue: "a"), screenName: "Login"),
            RecordFixtures.make(id: RecordID(rawValue: "b"), screenName: "Home")
        ])
        let response = await send(handler, [
            "jsonrpc": "2.0", "id": 4, "method": "tools/call",
            "params": ["name": "list_captures", "arguments": ["screenName": "Login"]]
        ])
        let content = (response?["result"] as? [String: Any])?["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String
        #expect(text?.contains("\"a\"") == true)
        #expect(text?.contains("\"b\"") == false)
    }

    @Test func getCaptureReturnsImageAndTextContent() async {
        let record = RecordFixtures.make(
            id: RecordID(rawValue: "rec2"),
            artifacts: [.screenshot(pngData: Data([1, 2, 3])), .log(text: "hello")]
        )
        let handler = await makeHandler(seed: [record])
        let response = await send(handler, [
            "jsonrpc": "2.0", "id": 5, "method": "tools/call",
            "params": ["name": "get_capture", "arguments": ["id": "rec2"]]
        ])
        let content = (response?["result"] as? [String: Any])?["content"] as? [[String: Any]]
        let image = content?.first { $0["type"] as? String == "image" }
        #expect(image?["mimeType"] as? String == "image/png")
        #expect(image?["data"] as? String == Data([1, 2, 3]).base64EncodedString())
        #expect(content?.contains { ($0["text"] as? String)?.contains("hello") == true } == true)
    }

    @Test func getCaptureSurfacesArtifactType() async {
        let typed = Artifact(
            kind: ArtifactKind(rawValue: "agent_response"),
            mediaType: "application/json",
            data: Data("{\"intent\":\"search\"}".utf8),
            attributes: ["type": "AgentResponse"]
        )
        let record = RecordFixtures.make(id: RecordID(rawValue: "rec3"), artifacts: [typed])
        let handler = await makeHandler(seed: [record])
        let response = await send(handler, [
            "jsonrpc": "2.0", "id": 10, "method": "tools/call",
            "params": ["name": "get_capture", "arguments": ["id": "rec3"]]
        ])
        let content = (response?["result"] as? [String: Any])?["content"] as? [[String: Any]]
        let text = content?.compactMap { $0["text"] as? String }.first { $0.contains("agent_response") }
        #expect(text?.contains("<AgentResponse>") == true)
        #expect(text?.contains("\"intent\":\"search\"") == true)
    }

    @Test func getCaptureElidesBinaryResponseBody() async {
        let entry: [String: Any] = [
            "id": UUID().uuidString, "method": "GET",
            "url": "https://img.example/x.jpg", "host": "img.example",
            "requestHeaders": [String: String](),
            "responseHeaders": ["Content-Type": "image/jpeg", "Content-Length": "124534"],
            "responseBody": String(repeating: "A", count: 4096),
            "startedAt": "2026-06-06T00:00:00Z", "duration": 0.1
        ]
        let data = try! JSONSerialization.data(withJSONObject: [entry])
        let net = Artifact(kind: ArtifactKind(rawValue: "network"), mediaType: "application/json",
                           data: data, attributes: ["type": "NetworkLog"])
        let handler = await makeHandler(seed: [RecordFixtures.make(id: RecordID(rawValue: "n1"), artifacts: [net])])
        let response = await send(handler, [
            "jsonrpc": "2.0", "id": 30, "method": "tools/call",
            "params": ["name": "get_capture", "arguments": ["id": "n1"]]
        ])
        let content = (response?["result"] as? [String: Any])?["content"] as? [[String: Any]]
        let text = content?.compactMap { $0["text"] as? String }.first { $0.contains("network") }
        #expect(text?.contains("elided") == true)
        #expect(text?.contains("image/jpeg") == true)
        #expect(text?.contains("124534") == true)
        #expect(text?.contains(String(repeating: "A", count: 4096)) == false)
    }

    @Test func getCaptureKeepsTextualResponseBody() async {
        let entry: [String: Any] = [
            "id": UUID().uuidString, "method": "POST",
            "url": "https://api.example/v1", "host": "api.example",
            "requestHeaders": [String: String](),
            "responseHeaders": ["Content-Type": "application/json; charset=UTF-8"],
            "responseBody": "{\"keepme\":true}",
            "startedAt": "2026-06-06T00:00:00Z", "duration": 0.1
        ]
        let data = try! JSONSerialization.data(withJSONObject: [entry])
        let net = Artifact(kind: ArtifactKind(rawValue: "network"), mediaType: "application/json",
                           data: data, attributes: ["type": "NetworkLog"])
        let handler = await makeHandler(seed: [RecordFixtures.make(id: RecordID(rawValue: "n2"), artifacts: [net])])
        let response = await send(handler, [
            "jsonrpc": "2.0", "id": 34, "method": "tools/call",
            "params": ["name": "get_capture", "arguments": ["id": "n2"]]
        ])
        let content = (response?["result"] as? [String: Any])?["content"] as? [[String: Any]]
        let text = content?.compactMap { $0["text"] as? String }.first { $0.contains("network") }
        #expect(text?.contains("keepme") == true)
        #expect(text?.contains("elided") == false)
    }

    @Test func getCaptureStripsDebugTimelinePayload() async {
        let event: [String: Any] = [
            "id": UUID().uuidString, "at": "2026-06-06T00:00:00Z",
            "category": "agent", "name": "tool_call", "summary": "web_search call",
            "attributes": ["payloadType": "TokenUsage", "tool": "web_search"],
            "payload": Data("SECRETPAYLOAD".utf8).base64EncodedString()
        ]
        let data = try! JSONSerialization.data(withJSONObject: [event])
        let timeline = Artifact(kind: ArtifactKind(rawValue: "debug_timeline"), mediaType: "application/json",
                                data: data, attributes: ["type": "DebugEvent"])
        let handler = await makeHandler(seed: [RecordFixtures.make(id: RecordID(rawValue: "t1"), artifacts: [timeline])])
        let response = await send(handler, [
            "jsonrpc": "2.0", "id": 31, "method": "tools/call",
            "params": ["name": "get_capture", "arguments": ["id": "t1"]]
        ])
        let content = (response?["result"] as? [String: Any])?["content"] as? [[String: Any]]
        let text = content?.compactMap { $0["text"] as? String }.first { $0.contains("debug_timeline") }
        #expect(text?.contains("web_search call") == true)   // summary は残る
        #expect(text?.contains("payload") == false)          // payload / payloadType は消える
        #expect(text?.contains(Data("SECRETPAYLOAD".utf8).base64EncodedString()) == false)
    }

    private static func timelineArtifact(_ events: [[String: Any]]) -> Artifact {
        Artifact(kind: ArtifactKind(rawValue: "debug_timeline"), mediaType: "application/json",
                 data: try! JSONSerialization.data(withJSONObject: events),
                 attributes: ["type": "DebugEvent"])
    }

    private static func event(
        id: UUID = UUID(), at: String = "2026-06-06T00:00:00Z",
        category: String, name: String, summary: String,
        attributes: [String: String] = [:], payload: String? = nil
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "id": id.uuidString, "at": at,
            "category": category, "name": name, "summary": summary,
            "attributes": attributes
        ]
        if let payload { dict["payload"] = Data(payload.utf8).base64EncodedString() }
        return dict
    }

    @Test func searchEventsFiltersByCategoryAndReportsPayloadMeta() async {
        let promptID = UUID()
        let record = RecordFixtures.make(id: RecordID(rawValue: "s1"), artifacts: [Self.timelineArtifact([
            Self.event(id: promptID, category: "session", name: "system_prompt", summary: "system prompt 12 文字",
                       attributes: ["length": "12"], payload: "FULL PROMPT."),
            Self.event(category: "agent", name: "tool_call", summary: "🔧 web_search")
        ])])
        let handler = await makeHandler(seed: [record])
        let response = await send(handler, [
            "jsonrpc": "2.0", "id": 40, "method": "tools/call",
            "params": ["name": "search_events", "arguments": ["category": "session"]]
        ])
        let text = ((response?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String
        let hits = try! JSONSerialization.jsonObject(with: Data(text!.utf8)) as! [[String: Any]]
        #expect(hits.count == 1)
        #expect(hits.first?["eventId"] as? String == promptID.uuidString)
        #expect(hits.first?["captureId"] as? String == "s1")
        #expect(hits.first?["payloadBytes"] as? Int == 12)
        #expect(text?.contains("FULL PROMPT.") == false)
    }

    @Test func searchEventsMatchesTextAcrossSummaryAndAttributes() async {
        let record = RecordFixtures.make(id: RecordID(rawValue: "s2"), artifacts: [Self.timelineArtifact([
            Self.event(category: "agent", name: "tool_call", summary: "🔧 web_search", attributes: ["tool": "web_search"]),
            Self.event(category: "agent", name: "thinking", summary: "考え中")
        ])])
        let handler = await makeHandler(seed: [record])
        let response = await send(handler, [
            "jsonrpc": "2.0", "id": 41, "method": "tools/call",
            "params": ["name": "search_events", "arguments": ["text": "WEB_SEARCH", "limit": 10]]
        ])
        let text = ((response?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String
        let hits = try! JSONSerialization.jsonObject(with: Data(text!.utf8)) as! [[String: Any]]
        #expect(hits.count == 1)
        #expect(hits.first?["name"] as? String == "tool_call")
    }

    @Test func getEventReturnsFullPayloadText() async {
        let promptID = UUID()
        let record = RecordFixtures.make(id: RecordID(rawValue: "e1"), artifacts: [Self.timelineArtifact([
            Self.event(id: promptID, category: "session", name: "system_prompt", summary: "system prompt",
                       payload: "ROLE + SCHEMA + EXAMPLES")
        ])])
        let handler = await makeHandler(seed: [record])
        let response = await send(handler, [
            "jsonrpc": "2.0", "id": 42, "method": "tools/call",
            "params": ["name": "get_event", "arguments": ["captureId": "e1", "eventId": promptID.uuidString]]
        ])
        let text = ((response?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String
        let dict = try! JSONSerialization.jsonObject(with: Data(text!.utf8)) as! [String: Any]
        #expect(dict["payload"] as? String == "ROLE + SCHEMA + EXAMPLES")
        #expect(dict["payloadBytes"] as? Int == 24)
    }

    @Test func getEventRespectsMaxBytes() async {
        let eventID = UUID()
        let record = RecordFixtures.make(id: RecordID(rawValue: "e2"), artifacts: [Self.timelineArtifact([
            Self.event(id: eventID, category: "session", name: "system_prompt", summary: "long",
                       payload: String(repeating: "p", count: 5000))
        ])])
        let handler = await makeHandler(seed: [record])
        let response = await send(handler, [
            "jsonrpc": "2.0", "id": 43, "method": "tools/call",
            "params": ["name": "get_event", "arguments": ["captureId": "e2", "eventId": eventID.uuidString, "maxBytes": 100]]
        ])
        let text = ((response?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String
        let dict = try! JSONSerialization.jsonObject(with: Data(text!.utf8)) as! [String: Any]
        let payload = dict["payload"] as? String
        #expect(payload?.contains("truncated") == true)
        #expect((payload?.utf8.count ?? .max) < 400)
    }

    @Test func getEventMissingReturnsIsError() async {
        let handler = await makeHandler(seed: [RecordFixtures.make(id: RecordID(rawValue: "e3"))])
        let response = await send(handler, [
            "jsonrpc": "2.0", "id": 44, "method": "tools/call",
            "params": ["name": "get_event", "arguments": ["captureId": "e3", "eventId": UUID().uuidString]]
        ])
        #expect((response?["result"] as? [String: Any])?["isError"] as? Bool == true)
    }

    @Test func getCaptureFiltersByKinds() async {
        let record = RecordFixtures.make(id: RecordID(rawValue: "k1"), artifacts: [
            .state(json: Data("{\"a\":1}".utf8)),
            .log(text: "LOGLINE")
        ])
        let handler = await makeHandler(seed: [record])
        let response = await send(handler, [
            "jsonrpc": "2.0", "id": 32, "method": "tools/call",
            "params": ["name": "get_capture", "arguments": ["id": "k1", "kinds": ["log"]]]
        ])
        let content = (response?["result"] as? [String: Any])?["content"] as? [[String: Any]]
        let texts = content?.compactMap { $0["text"] as? String } ?? []
        #expect(texts.contains { $0.contains("LOGLINE") })
        #expect(texts.contains { $0.contains("[state") } == false)
    }

    @Test func getCaptureRespectsMaxBytes() async {
        let record = RecordFixtures.make(id: RecordID(rawValue: "m1"),
                                         artifacts: [.log(text: String(repeating: "x", count: 5000))])
        let handler = await makeHandler(seed: [record])
        let response = await send(handler, [
            "jsonrpc": "2.0", "id": 33, "method": "tools/call",
            "params": ["name": "get_capture", "arguments": ["id": "m1", "maxBytes": 100]]
        ])
        let content = (response?["result"] as? [String: Any])?["content"] as? [[String: Any]]
        let text = content?.compactMap { $0["text"] as? String }.first { $0.contains("[log") }
        #expect(text?.contains("truncated") == true)
        #expect((text?.utf8.count ?? .max) < 400)
    }

    @Test func getCaptureMissingReturnsIsError() async {
        let handler = await makeHandler()
        let response = await send(handler, [
            "jsonrpc": "2.0", "id": 6, "method": "tools/call",
            "params": ["name": "get_capture", "arguments": ["id": "ghost"]]
        ])
        let result = response?["result"] as? [String: Any]
        #expect(result?["isError"] as? Bool == true)
    }

    @Test func unknownMethodReturnsMethodNotFound() async {
        let handler = await makeHandler()
        let response = await send(handler, ["jsonrpc": "2.0", "id": 7, "method": "bogus"])
        let error = response?["error"] as? [String: Any]
        #expect(error?["code"] as? Int == -32601)
    }

    @Test func connectionStatusToolHiddenWithoutProvider() async {
        let handler = await makeHandler()
        let response = await send(handler, ["jsonrpc": "2.0", "id": 20, "method": "tools/list"])
        let tools = (response?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        let names = Set(tools?.compactMap { $0["name"] as? String } ?? [])
        #expect(names.contains("connection_status") == false)
    }

    @Test func connectionStatusToolReportsReceiverHealth() async {
        let store = FakeRecordStore()
        let status = FakeStatus(snapshot: ReceiverStatusSnapshot(
            listening: true, port: 63181, serviceName: "iOSRecorder",
            totalReceived: 7, lastReceivedAt: Date(timeIntervalSince1970: 1_700_000_000),
            startedAt: Date(timeIntervalSince1970: 1_699_990_000)
        ))
        let handler = MCPRequestHandler(store: store, status: status)

        let list = await send(handler, ["jsonrpc": "2.0", "id": 21, "method": "tools/list"])
        let names = Set((((list?["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String })
        #expect(names.contains("connection_status"))

        let response = await send(handler, [
            "jsonrpc": "2.0", "id": 22, "method": "tools/call",
            "params": ["name": "connection_status", "arguments": [:]]
        ])
        let text = ((response?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String
        #expect(text?.contains("\"listening\" : true") == true)
        #expect(text?.contains("\"totalReceived\" : 7") == true)
        #expect(text?.contains("\"port\" : 63181") == true)
    }

    @Test func toolCallAutoRecoversWhenListenerDown() async {
        let down = FakeStatus(snapshot: ReceiverStatusSnapshot(listening: false, startedAt: Date()))
        let control = FakeControl(snapshot: ReceiverStatusSnapshot(listening: true, startedAt: Date()))
        let handler = MCPRequestHandler(store: FakeRecordStore(), status: down, control: control)
        _ = await send(handler, [
            "jsonrpc": "2.0", "id": 24, "method": "tools/call",
            "params": ["name": "list_captures", "arguments": [:]]
        ])
        #expect(await control.restartCount == 1)
    }

    @Test func toolCallDoesNotRestartWhenListenerHealthy() async {
        let up = FakeStatus(snapshot: ReceiverStatusSnapshot(listening: true, startedAt: Date()))
        let control = FakeControl(snapshot: ReceiverStatusSnapshot(listening: true, startedAt: Date()))
        let handler = MCPRequestHandler(store: FakeRecordStore(), status: up, control: control)
        _ = await send(handler, [
            "jsonrpc": "2.0", "id": 25, "method": "tools/call",
            "params": ["name": "list_captures", "arguments": [:]]
        ])
        #expect(await control.restartCount == 0)
    }

    @Test func restartReceiverToolInvokesControl() async {
        let store = FakeRecordStore()
        let control = FakeControl(snapshot: ReceiverStatusSnapshot(listening: true, port: 50000, startedAt: Date()))
        let handler = MCPRequestHandler(store: store, control: control)
        let response = await send(handler, [
            "jsonrpc": "2.0", "id": 23, "method": "tools/call",
            "params": ["name": "restart_receiver", "arguments": [:]]
        ])
        let text = ((response?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String
        #expect(text?.contains("restarted") == true)
        #expect(await control.restartCount == 1)
    }
}

private struct FakeStatus: ReceiverStatusProviding {
    let snapshot: ReceiverStatusSnapshot
    func status() async -> ReceiverStatusSnapshot { snapshot }
}

private actor FakeControl: ReceiverControlling {
    let snapshot: ReceiverStatusSnapshot
    private(set) var restartCount = 0
    init(snapshot: ReceiverStatusSnapshot) { self.snapshot = snapshot }
    func restart() async -> ReceiverStatusSnapshot { restartCount += 1; return snapshot }
}
