import Foundation
import iOSRecorder

/// 改行区切りの JSON-RPC を stdin から読み、stdout に応答を書く MCP stdio サーバー。
/// `claude mcp add ios-recorder -- ios-recorder mcp` で登録される実体。
public struct StdioMCPServer {
    private let handler: MCPRequestHandler

    public init(
        store: any RecordStore,
        name: String = "ios-recorder",
        version: String = "0.1.0",
        status: (any ReceiverStatusProviding)? = nil,
        control: (any ReceiverControlling)? = nil
    ) {
        self.handler = MCPRequestHandler(store: store, name: name, version: version, status: status, control: control)
    }

    public func run() async {
        let output = FileHandle.standardOutput
        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                guard let data = line.data(using: .utf8), !data.isEmpty else { continue }
                if let response = await handler.handle(data) {
                    output.write(response)
                    output.write(Data([0x0A]))
                }
            }
        } catch {
            FileHandle.standardError.write(Data("ios-recorder mcp: \(error)\n".utf8))
        }
    }
}
