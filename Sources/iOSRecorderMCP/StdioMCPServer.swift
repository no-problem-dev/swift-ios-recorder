import Foundation
import iOSRecorder

/// Speaks MCP over stdin and stdout, one newline-delimited JSON-RPC message per line. This is the
/// process registered with `claude mcp add ios-recorder -- ios-recorder mcp`.
///
/// Stdout carries the protocol, so anything else written there corrupts the session — send
/// diagnostics to stderr.
public struct StdioMCPServer {
    private let handler: MCPRequestHandler

    /// Assembles the server and decides which tools exist.
    ///
    /// The three optional ports each add a tool when supplied and leave it out of `tools/list`
    /// when not:
    /// - `status`: `connection_status`, reporting receiver health.
    /// - `control`: `restart_receiver`, rebuilding the listener. Supplying both this and `status`
    ///   also lets a dead listener be revived automatically before a tool runs.
    /// - `storage`: `get_storage_info`, reporting count and bytes used.
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

    /// Reads requests until stdin reaches end of file, answering each on stdout.
    ///
    /// Does not return before then, which is the point: the host launches this as a child process
    /// and closing its stdin is how the process is told to finish. Requests are handled one at a
    /// time in arrival order. A read failure ends the loop after a line on stderr.
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
