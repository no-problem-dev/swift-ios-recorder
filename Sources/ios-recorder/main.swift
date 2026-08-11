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

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Owns the receiver and tracks what has come in: total count, last arrival, uptime and port.
/// This is what the MCP tools connection_status and restart_receiver actually act on.
actor ReceiverHub: ReceiverStatusProviding, ReceiverControlling {
    private let store: FileRecordStore
    private let serviceName: String
    private let startedAt = Date()
    private var receiver: BonjourReceiver?
    private var pump: Task<Void, Never>?
    private var total = 0
    private var lastReceivedAt: Date?
    /// Only the newest pump is allowed to heal, so a stale pump finishing cannot tear down a live receiver.
    private var generation = 0

    init(store: FileRecordStore, serviceName: String = "iOSRecorder") {
        self.store = store
        self.serviceName = serviceName
    }

    func startReceiving() async { await spinUp() }

    private func spinUp() async {
        generation += 1
        let myGeneration = generation
        pump?.cancel()
        receiver?.stop()
        receiver = nil
        guard let r = try? BonjourReceiver(serviceName: serviceName) else { return }
        try? await r.start()
        receiver = r
        let records = r.records()
        pump = Task { [weak self] in
            do {
                for try await record in records {
                    await self?.ingest(record)
                }
            } catch {}
            // The stream ending means the listener failed; if this is still the newest generation, put it back up.
            await self?.healIfCurrent(myGeneration)
        }
    }

    /// Brings a dropped listener back after a short backoff, and only for the newest generation.
    private func healIfCurrent(_ generationAtStart: Int) async {
        guard generationAtStart == generation else { return }
        try? await Task.sleep(for: .seconds(1))
        guard generationAtStart == generation else { return }
        log("receiver listener dropped — self-healing")
        await spinUp()
    }

    private func ingest(_ record: Record) async {
        try? await store.save(record)
        total += 1
        lastReceivedAt = Date()
        log("received \(record.id.rawValue) (\(record.artifacts.count) artifacts)")
    }

    func status() async -> ReceiverStatusSnapshot {
        ReceiverStatusSnapshot(
            listening: receiver != nil,
            port: receiver?.resolvedPort,
            serviceName: serviceName,
            totalReceived: total,
            lastReceivedAt: lastReceivedAt,
            startedAt: startedAt
        )
    }

    func restart() async -> ReceiverStatusSnapshot {
        await spinUp()
        return await status()
    }
}

let storeRoot = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".iosrecorder/captures", isDirectory: true)
let store = FileRecordStore(rootURL: storeRoot, maxRecords: 300)
let hub = ReceiverHub(store: store)

let arguments = CommandLine.arguments
let command = arguments.count > 1 ? arguments[1] : "help"

switch command {
case "serve":
    await hub.startReceiving()
    let snapshot = await hub.status()
    log(snapshot.listening
        ? "ios-recorder serve — 受信中 port=\(snapshot.port.map(String.init) ?? "?")、保存先 \(storeRoot.path)"
        : "ios-recorder serve — 受信機の起動に失敗しました")
    try await Task.sleep(for: .seconds(60 * 60 * 24 * 365))

case "mcp":
    // The receiver rides along in the MCP process Claude Code spawns, so it starts and stops with it.
    // hub backs connection_status / restart_receiver; store backs get_storage_info.
    await hub.startReceiving()
    await StdioMCPServer(store: store, status: hub, control: hub, storage: store).run()

default:
    print(usage)
}
