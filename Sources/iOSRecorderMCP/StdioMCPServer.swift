import Foundation
import iOSRecorder

/// 改行区切りの JSON-RPC を stdin から読み、stdout に応答を書く MCP stdio サーバー。
/// `claude mcp add ios-recorder -- ios-recorder mcp` で登録される実体。
public struct StdioMCPServer {
    private let handler: MCPRequestHandler

    /// MCP サーバーを初期化する。
    ///
    /// `status`/`control`/`storage` は任意。渡すとそれぞれ追加ツールが有効になる:
    /// - `status`: `connection_status` ツールを公開（受信機の健全性）。
    /// - `control`: `restart_receiver` ツールを公開（リスナー再起動）。
    /// - `storage`: `get_storage_info` ツールを公開（件数・使用バイト数）。
    public init(
        store: any RecordStore,
        name: String = "ios-recorder",
        version: String = "0.1.0",
        status: (any ReceiverStatusProviding)? = nil,
        control: (any ReceiverControlling)? = nil,
        storage: (any StorageReporting)? = nil
    ) {
        self.handler = MCPRequestHandler(
            store: store, name: name, version: version,
            status: status, control: control, storage: storage)
    }

    /// stdin から JSON-RPC リクエストを 1 行ずつ読み、stdout に応答を書き続ける主エントリポイント。
    ///
    /// stdin が EOF を返すまで戻らない。`claude mcp add` で登録した子プロセスとして起動し、
    /// この関数を `await` したまま待機させる用途を想定している。
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
