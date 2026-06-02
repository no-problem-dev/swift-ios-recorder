import Foundation

/// 任意の `Encodable` 値を計測する汎用 Source。`StateSource` との違いは 2 つ:
/// - 値の Swift 型名を `attributes["type"]` に刻む（MCP/消費者が型で識別できる）
/// - `kind` を指定できる（既定 `.state`。`ArtifactKind(rawValue: "agent_response")` 等で
///   族ごとに分けると `RecordQuery.kinds` 経由でそのまま絞り込める）
///
/// provider が `nil` を返した瞬間は artifact を作らない（その回の計測をスキップ）。
public struct TypedStateSource<Value: Encodable & Sendable>: Source {
    public let kind: ArtifactKind
    private let typeName: String
    private let provider: @Sendable () async -> Value?

    public init(
        kind: ArtifactKind = .state,
        typeName: String = String(describing: Value.self),
        _ provider: @escaping @Sendable () async -> Value?
    ) {
        self.kind = kind
        self.typeName = typeName
        self.provider = provider
    }

    public func measure(_ context: RecordContext) async -> Artifact? {
        guard let value = await provider() else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return Artifact(
            kind: kind,
            mediaType: "application/json",
            data: data,
            attributes: ["type": typeName]
        )
    }
}
