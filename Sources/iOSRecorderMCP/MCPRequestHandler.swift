import Foundation
import iOSRecorder

/// MCP（JSON-RPC 2.0）リクエストを処理する純ハンドラ。トランスポート非依存なので
/// JSON を渡すだけで単体テストできる。list_captures / get_capture を公開する。
public actor MCPRequestHandler {
    private let server: RecordMCPServer
    private let serverName: String
    private let serverVersion: String

    public init(store: any RecordStore, name: String = "ios-recorder", version: String = "0.1.0") {
        self.server = RecordMCPServer(store: store)
        self.serverName = name
        self.serverVersion = version
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
        [
            "tools": [
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
                    "description": "指定 id の記録を取得（画像 + state + ログ）。画像は maxDimension(既定 1024)px に縮小して返す。",
                    "inputSchema": [
                        "type": "object",
                        "properties": [
                            "id": ["type": "string"],
                            "maxDimension": ["type": "integer", "description": "画像の最大辺(px)。既定 1024。0 で原寸。"]
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
        ]
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
            do {
                let record = try await server.getCapture(RecordID(rawValue: rawID))
                return response(id: id, result: ["content": Self.recordContent(record, maxDimension: maxDimension)])
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
        default:
            return response(id: id, error: (-32602, "unknown tool: \(name)"))
        }
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

    private static func recordContent(_ record: Record, maxDimension: Int) -> [[String: Any]] {
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
            if artifact.mediaType.hasPrefix("image/") {
                let (imageData, mimeType) = ImageDownscaler.downscale(artifact.data, maxDimension: maxDimension)
                    ?? (artifact.data, artifact.mediaType)
                content.append([
                    "type": "image",
                    "data": imageData.base64EncodedString(),
                    "mimeType": mimeType
                ])
            } else {
                content.append([
                    "type": "text",
                    "text": "[\(artifact.kind.rawValue)] " + String(decoding: artifact.data, as: UTF8.self)
                ])
            }
        }
        return content
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func orNull(_ value: String?) -> Any {
        value.map { $0 as Any } ?? NSNull()
    }
}
