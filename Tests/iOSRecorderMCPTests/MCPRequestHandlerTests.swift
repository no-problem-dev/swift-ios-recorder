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
        #expect(names == ["list_captures", "get_capture", "delete_capture", "clear_captures"])
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
