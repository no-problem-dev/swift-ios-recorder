import Foundation

/// ストリーミング・デバッグログの単位。あらゆるデバッグデータ（AI 動作・UI 生成・通信・任意構造体）を
/// この時刻付き封筒に正規化する。`payload` は Artifact.data と同じく不透明。
public struct DebugEvent: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let at: Date
    /// 開いた識別子。例: "agent" / "a2ui" / "network" / "metric"。
    public let category: String
    /// イベント名。例: "tool_call" / "surface_created" / "decode_failed"。
    public let name: String
    /// 人間・AI が 1 行で読めるサマリ。
    public let summary: String
    /// 構造化の補足（toolName, surfaceId, tokens 等）。
    public let attributes: [String: String]
    /// 任意の生データ（不透明）。
    public let payload: Data?

    public init(
        id: UUID = UUID(),
        at: Date = Date(),
        category: String,
        name: String,
        summary: String,
        attributes: [String: String] = [:],
        payload: Data? = nil
    ) {
        self.id = id
        self.at = at
        self.category = category
        self.name = name
        self.summary = summary
        self.attributes = attributes
        self.payload = payload
    }
}

public extension DebugEvent {
    /// 不透明な `payload` と型ヒント `attributes["payloadType"]` を落とした複製。
    /// Bonjour/MCP へ畳む時に冗長な base64 を除き、summary/attributes だけ残す。
    func withoutPayload() -> DebugEvent {
        var attrs = attributes
        attrs.removeValue(forKey: "payloadType")
        return DebugEvent(
            id: id, at: at, category: category, name: name,
            summary: summary, attributes: attrs, payload: nil
        )
    }

    /// 任意の Encodable 値を payload に詰める。利用側が差し込んだどんな構造体でも
    /// 「全データ」を JSON として保持し、詳細ビューで構造表示できる。
    init(
        category: String,
        name: String,
        summary: String,
        attributes: [String: String] = [:],
        at: Date = Date(),
        encoding value: some Encodable & Sendable
    ) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var attrs = attributes
        attrs["payloadType"] = String(describing: type(of: value))
        self.init(
            at: at,
            category: category,
            name: name,
            summary: summary,
            attributes: attrs,
            payload: try? encoder.encode(value)
        )
    }

    /// 生テキストを payload に詰める（JSON でないログ・LLM 出力など）。
    init(
        category: String,
        name: String,
        summary: String,
        attributes: [String: String] = [:],
        at: Date = Date(),
        text: String
    ) {
        self.init(
            at: at,
            category: category,
            name: name,
            summary: summary,
            attributes: attributes,
            payload: Data(text.utf8)
        )
    }
}
