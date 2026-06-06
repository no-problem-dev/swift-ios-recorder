import Foundation
import iOSRecorder

/// MCP（JSON-RPC 2.0）リクエストを処理する純ハンドラ。トランスポート非依存なので
/// JSON を渡すだけで単体テストできる。list_captures / get_capture を公開する。
public actor MCPRequestHandler {
    private let server: RecordMCPServer
    private let serverName: String
    private let serverVersion: String
    private let status: (any ReceiverStatusProviding)?
    private let control: (any ReceiverControlling)?

    public init(
        store: any RecordStore,
        name: String = "ios-recorder",
        version: String = "0.1.0",
        status: (any ReceiverStatusProviding)? = nil,
        control: (any ReceiverControlling)? = nil
    ) {
        self.server = RecordMCPServer(store: store)
        self.serverName = name
        self.serverVersion = version
        self.status = status
        self.control = control
    }

    /// JSON-RPC リクエスト 1 件を処理。通知（応答不要）なら nil。
    public func handle(_ requestData: Data) async -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any] else {
            return Self.encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "parse error"]])
        }
        guard let method = object["method"] as? String else { return nil }
        let id = object["id"]

        switch method {
        case "initialize":
            return response(id: id, result: initializeResult())
        case "tools/list":
            return response(id: id, result: toolsListResult())
        case "tools/call":
            await autoRecoverIfNeeded()
            return await toolsCall(id: id, params: object["params"] as? [String: Any] ?? [:])
        default:
            if method.hasPrefix("notifications/") { return nil }
            return response(id: id, error: (-32601, "method not found: \(method)"))
        }
    }

    // MARK: - Methods

    private func initializeResult() -> [String: Any] {
        [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": serverName, "version": serverVersion]
        ]
    }

    private func toolsListResult() -> [String: Any] {
        var tools: [[String: Any]] = baseTools()
        if status != nil {
            tools.append([
                "name": "connection_status",
                "description": "Mac 受信機の健全性を返す（listening/port/累計受信数/最終受信時刻/稼働時間）。iPhone で撮影 → これを叩いて『たった今受信・件数+1』を確認できる。",
                "inputSchema": ["type": "object", "properties": [String: Any]()]
            ])
        }
        if control != nil {
            tools.append([
                "name": "restart_receiver",
                "description": "受信機の listener を貼り直し、Bonjour を再広告する。届かない時の再接続用。",
                "inputSchema": ["type": "object", "properties": [String: Any]()]
            ])
        }
        return ["tools": tools]
    }

    private func baseTools() -> [[String: Any]] {
        [
                [
                    "name": "list_captures",
                    "description": "デバイスから届いた記録の一覧（画像は含まない）。screenName/text/kinds/limit で絞り込み。",
                    "inputSchema": [
                        "type": "object",
                        "properties": [
                            "screenName": ["type": "string"],
                            "text": ["type": "string"],
                            "session": ["type": "string"],
                            "limit": ["type": "integer"],
                            "sinceMinutes": ["type": "integer", "description": "直近 N 分の記録だけに絞る"],
                            "kinds": ["type": "array", "items": ["type": "string"]]
                        ]
                    ]
                ],
                [
                    "name": "get_capture",
                    "description": "指定 id の記録を取得（画像 + state + ログ + network + debug_timeline）。非画像は [kind <型名>] 付きテキスト、画像は maxDimension(既定 1024)px に縮小。network のバイナリ応答ボディ（画像等）は省略し、debug_timeline の payload は除去して返す。kinds で種別を絞り、maxBytes で各 artifact のテキスト量を制限できる。",
                    "inputSchema": [
                        "type": "object",
                        "properties": [
                            "id": ["type": "string"],
                            "maxDimension": ["type": "integer", "description": "画像の最大辺(px)。既定 1024。0 で原寸。"],
                            "kinds": ["type": "array", "items": ["type": "string"], "description": "返す artifact 種別を絞る（例: [\"debug_timeline\"]）。未指定で全種別。"],
                            "maxBytes": ["type": "integer", "description": "各 artifact テキストの最大バイト数。超過分は truncate。未指定で無制限。"]
                        ],
                        "required": ["id"]
                    ]
                ],
                [
                    "name": "delete_capture",
                    "description": "指定 id の記録を削除する。",
                    "inputSchema": [
                        "type": "object",
                        "properties": ["id": ["type": "string"]],
                        "required": ["id"]
                    ]
                ],
                [
                    "name": "clear_captures",
                    "description": "保存済みの記録をすべて削除する。",
                    "inputSchema": ["type": "object", "properties": [String: Any]()]
                ]
            ]
    }

    /// ツール実行直前のセーフティネット: listener が落ちている時だけ無言で貼り直す。
    /// 健全な時は何もしない（port チャーンで in-flight を壊さないため無条件にはしない）。
    private func autoRecoverIfNeeded() async {
        guard let status, let control else { return }
        if await status.status().listening == false {
            _ = await control.restart()
        }
    }

    private func toolsCall(id: Any?, params: [String: Any]) async -> Data? {
        guard let name = params["name"] as? String else {
            return response(id: id, error: (-32602, "missing tool name"))
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]

        switch name {
        case "list_captures":
            let summaries = (try? await server.listCaptures(Self.query(from: arguments))) ?? []
            return response(id: id, result: ["content": [["type": "text", "text": Self.summariesJSON(summaries)]]])
        case "get_capture":
            guard let rawID = arguments["id"] as? String else {
                return response(id: id, error: (-32602, "missing argument: id"))
            }
            let maxDimension = arguments["maxDimension"] as? Int ?? 1024
            let kinds = (arguments["kinds"] as? [String]).map { Set($0.map { ArtifactKind(rawValue: $0) }) }
            let maxBytes = arguments["maxBytes"] as? Int
            do {
                let record = try await server.getCapture(RecordID(rawValue: rawID))
                return response(id: id, result: ["content": Self.recordContent(
                    record, maxDimension: maxDimension, kinds: kinds, maxBytes: maxBytes)])
            } catch {
                return response(id: id, result: [
                    "content": [["type": "text", "text": "capture not found: \(rawID)"]],
                    "isError": true
                ])
            }
        case "delete_capture":
            guard let rawID = arguments["id"] as? String else {
                return response(id: id, error: (-32602, "missing argument: id"))
            }
            try? await server.deleteCapture(RecordID(rawValue: rawID))
            return response(id: id, result: ["content": [["type": "text", "text": "deleted \(rawID)"]]])
        case "clear_captures":
            try? await server.clearCaptures()
            return response(id: id, result: ["content": [["type": "text", "text": "cleared all captures"]]])
        case "connection_status":
            guard let status else { return response(id: id, error: (-32602, "connection_status unavailable")) }
            let snapshot = await status.status()
            return response(id: id, result: ["content": [["type": "text", "text": Self.statusJSON(snapshot)]]])
        case "restart_receiver":
            guard let control else { return response(id: id, error: (-32602, "restart_receiver unavailable")) }
            let snapshot = await control.restart()
            return response(id: id, result: ["content": [["type": "text", "text": "restarted\n" + Self.statusJSON(snapshot)]]])
        default:
            return response(id: id, error: (-32602, "unknown tool: \(name)"))
        }
    }

    private static func statusJSON(_ s: ReceiverStatusSnapshot) -> String {
        var dict: [String: Any] = [
            "listening": s.listening,
            "totalReceived": s.totalReceived,
            "startedAt": iso(s.startedAt),
            "uptimeSeconds": Int(Date().timeIntervalSince(s.startedAt))
        ]
        dict["port"] = s.port.map { Int($0) } ?? NSNull()
        dict["serviceName"] = orNull(s.serviceName)
        if let last = s.lastReceivedAt {
            dict["lastReceivedAt"] = iso(last)
            dict["secondsSinceLastReceive"] = Int(Date().timeIntervalSince(last))
        } else {
            dict["lastReceivedAt"] = NSNull()
        }
        let data = (try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - JSON-RPC envelope

    private func response(id: Any?, result: [String: Any]) -> Data {
        Self.encode(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
    }

    private func response(id: Any?, error: (code: Int, message: String)) -> Data {
        Self.encode(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": error.code, "message": error.message]])
    }

    private static func encode(_ dictionary: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: dictionary)) ?? Data()
    }

    // MARK: - Mapping

    private static func query(from arguments: [String: Any]) -> RecordQuery {
        var query = RecordQuery()
        if let screenName = arguments["screenName"] as? String { query.screenName = screenName }
        if let text = arguments["text"] as? String { query.text = text }
        if let session = arguments["session"] as? String { query.session = SessionID(rawValue: session) }
        if let limit = arguments["limit"] as? Int { query.limit = limit }
        if let kinds = arguments["kinds"] as? [String] { query.kinds = Set(kinds.map { ArtifactKind(rawValue: $0) }) }
        if let sinceMinutes = arguments["sinceMinutes"] as? Int, sinceMinutes > 0 {
            let cutoff = Date().addingTimeInterval(-Double(sinceMinutes) * 60)
            query.timeRange = cutoff ... Date.distantFuture
        }
        return query
    }

    private static func summariesJSON(_ summaries: [RecordSummary]) -> String {
        let array = summaries.map { summary -> [String: Any] in
            [
                "id": summary.id.rawValue,
                "recordedAt": iso(summary.recordedAt),
                "screenName": orNull(summary.metadata.screenName),
                "kinds": summary.artifactKinds.map(\.rawValue),
                "tags": summary.metadata.tags
            ]
        }
        let data = (try? JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted, .sortedKeys])) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func recordContent(
        _ record: Record,
        maxDimension: Int,
        kinds: Set<ArtifactKind>? = nil,
        maxBytes: Int? = nil
    ) -> [[String: Any]] {
        var content: [[String: Any]] = []
        let meta: [String: Any] = [
            "id": record.id.rawValue,
            "session": record.session.rawValue,
            "recordedAt": iso(record.recordedAt),
            "screenName": orNull(record.metadata.screenName),
            "appVersion": orNull(record.metadata.appVersion),
            "tags": record.metadata.tags
        ]
        if let metaData = try? JSONSerialization.data(withJSONObject: meta, options: [.sortedKeys]) {
            content.append(["type": "text", "text": String(decoding: metaData, as: UTF8.self)])
        }
        for artifact in record.artifacts {
            if let kinds, !kinds.contains(artifact.kind) { continue }
            if artifact.mediaType.hasPrefix("image/") {
                let (imageData, mimeType) = ImageDownscaler.downscale(artifact.data, maxDimension: maxDimension)
                    ?? (artifact.data, artifact.mediaType)
                content.append([
                    "type": "image",
                    "data": imageData.base64EncodedString(),
                    "mimeType": mimeType
                ])
            } else {
                let typeLabel = artifact.attributes["type"].map { " <\($0)>" } ?? ""
                var body = bodyText(for: artifact)
                if let maxBytes { body = cap(body, maxBytes: maxBytes) }
                content.append([
                    "type": "text",
                    "text": "[\(artifact.kind.rawValue)\(typeLabel)] " + body
                ])
            }
        }
        return content
    }

    /// 非画像 artifact のテキスト本文。network/debug_timeline は読み出し時にサニタイズする
    /// （バイナリ応答ボディの省略・base64 payload の除去）。それ以外は従来どおり。
    private static func bodyText(for artifact: Artifact) -> String {
        switch artifact.kind.rawValue {
        case "network":
            if let sanitized = sanitizedNetworkJSON(artifact.data) { return sanitized }
        case "debug_timeline":
            if let stripped = strippedTimelineJSON(artifact.data) { return stripped }
        default:
            break
        }
        let isText = artifact.mediaType.hasPrefix("text/") || artifact.mediaType == "application/json"
        return isText
            ? String(decoding: artifact.data, as: UTF8.self)
            : "base64(\(artifact.mediaType)): " + artifact.data.base64EncodedString()
    }

    /// network artifact の各エントリで、Content-Type が非テキスト（画像/動画/バイナリ）の
    /// responseBody をプレースホルダに置換する。token を食う mojibake を AI に渡さない。
    private static func sanitizedNetworkJSON(_ data: Data) -> String? {
        guard var entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        for index in entries.indices {
            let headers = entries[index]["responseHeaders"] as? [String: Any] ?? [:]
            let contentType = headerValue(headers, "Content-Type") ?? ""
            if !isTextualContentType(contentType), let bodyValue = entries[index]["responseBody"] as? String {
                let size = headerValue(headers, "Content-Length") ?? "\(bodyValue.utf8.count)"
                let label = contentType.isEmpty ? "binary" : contentType
                entries[index]["responseBody"] = "<elided \(label), \(size) bytes>"
            }
        }
        guard let out = try? JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(decoding: out, as: UTF8.self)
    }

    /// debug_timeline artifact の各イベントから、summary と冗長な base64 `payload` を除去する。
    /// summary が人間/AI 可読な要約を持つため payload は MCP 出力では不要。
    private static func strippedTimelineJSON(_ data: Data) -> String? {
        guard var events = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        for index in events.indices {
            events[index].removeValue(forKey: "payload")
            if var attrs = events[index]["attributes"] as? [String: Any] {
                attrs.removeValue(forKey: "payloadType")
                events[index]["attributes"] = attrs
            }
        }
        guard let out = try? JSONSerialization.data(withJSONObject: events, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(decoding: out, as: UTF8.self)
    }

    private static func headerValue(_ headers: [String: Any], _ name: String) -> String? {
        for (key, value) in headers where key.caseInsensitiveCompare(name) == .orderedSame {
            return value as? String
        }
        return nil
    }

    private static func isTextualContentType(_ contentType: String) -> Bool {
        let lower = contentType.lowercased()
        if lower.isEmpty { return true }   // 不明な時は保持（過剰省略を避ける）
        if lower.hasPrefix("text/") { return true }
        return lower.contains("json") || lower.contains("xml") || lower.contains("javascript")
            || lower.contains("html") || lower.contains("csv") || lower.contains("x-www-form-urlencoded")
    }

    /// UTF-8 バイト数で上限を超えたテキストを truncate する（最後の安全網）。
    private static func cap(_ text: String, maxBytes: Int) -> String {
        let utf8 = Array(text.utf8)
        guard utf8.count > maxBytes else { return text }
        let head = String(decoding: utf8.prefix(maxBytes), as: UTF8.self)
        return head + "\n…(truncated to \(maxBytes) bytes, \(utf8.count) total)"
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func orNull(_ value: String?) -> Any {
        value.map { $0 as Any } ?? NSNull()
    }
}
