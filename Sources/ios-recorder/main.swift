import Foundation
import iOSRecorder
import iOSRecorderStore
import iOSRecorderBonjour
import iOSRecorderMCP

let usage = """
ios-recorder — iOSRecorder companion (Mac)

USAGE:
  ios-recorder mcp      MCP サーバー + 受信機（claude mcp add で登録）。
                        Claude Code の起動に連動して受信機も起動/停止する。
  ios-recorder serve    受信機のみを単体起動（headless 運用向け）

記録の保存先: ~/.iosrecorder/captures
"""

/// Bonjour 受信機を起動し、届いた記録を store に保存し続ける（best-effort）。
/// 戻り値の receiver は呼び出し側で保持し続けること（解放するとリスナーが止まる）。
@discardableResult
func startReceiver(into store: FileRecordStore) async -> BonjourReceiver? {
    guard let receiver = try? BonjourReceiver(serviceName: "iOSRecorder") else { return nil }
    try? await receiver.start()
    let records = receiver.records()
    Task {
        do {
            for try await record in records {
                try? await store.save(record)
                log("received \(record.id.rawValue) (\(record.artifacts.count) artifacts)")
            }
        } catch {}
    }
    return receiver
}

let storeRoot = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".iosrecorder/captures", isDirectory: true)
let store = FileRecordStore(rootURL: storeRoot, maxRecords: 300)

let arguments = CommandLine.arguments
let command = arguments.count > 1 ? arguments[1] : "help"

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

switch command {
case "serve":
    let receiver = await startReceiver(into: store)
    log(receiver == nil
        ? "ios-recorder serve — 受信機の起動に失敗しました"
        : "ios-recorder serve — 受信中、保存先 \(storeRoot.path)")
    // 受信機は別タスクで動き続ける。プロセスを生かしておく。
    try await Task.sleep(for: .seconds(60 * 60 * 24 * 365))
    _ = receiver

case "mcp":
    // Claude Code が spawn する MCP プロセスに受信機を同居させる。
    // → Claude Code の起動/終了に受信機のライフサイクルが連動する（別デーモン不要）。
    let receiver = await startReceiver(into: store)
    await StdioMCPServer(store: store).run()
    _ = receiver

default:
    print(usage)
}
