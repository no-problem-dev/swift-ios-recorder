import Foundation

/// 任意の値を時系列で push しておく型付き固定長バッファ。`LogBuffer` の Generics 版。
/// AI がレスポンスを吐いた瞬間などに `append` しておき、計測時に `EventSource` が snapshot する。
public actor EventBuffer<Value: Sendable> {
    private var items: [Value] = []
    private let capacity: Int

    public init(capacity: Int = 100) {
        self.capacity = max(1, capacity)
    }

    public func append(_ value: Value) {
        items.append(value)
        if items.count > capacity {
            items.removeFirst(items.count - capacity)
        }
    }

    public func snapshot() -> [Value] { items }

    public func clear() { items.removeAll() }
}

/// `EventBuffer` に積まれた値の列を計測時に 1 つの Artifact（JSON 配列）に畳み込む Source。
/// 空なら artifact を作らない。要素の Swift 型名を `attributes["type"]` に刻む。
public struct EventSource<Value: Encodable & Sendable>: Source {
    public let kind: ArtifactKind
    private let typeName: String
    private let buffer: EventBuffer<Value>

    public init(
        kind: ArtifactKind = .state,
        typeName: String = String(describing: Value.self),
        buffer: EventBuffer<Value>
    ) {
        self.kind = kind
        self.typeName = typeName
        self.buffer = buffer
    }

    public func measure(_ context: RecordContext) async -> Artifact? {
        let items = await buffer.snapshot()
        guard !items.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return nil }
        return Artifact(
            kind: kind,
            mediaType: "application/json",
            data: data,
            attributes: ["type": typeName, "count": "\(items.count)"]
        )
    }
}
