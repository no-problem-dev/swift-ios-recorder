import Foundation

/// A fixed-size backlog of typed values to push into as things happen, for a later capture to pick up.
///
/// Append at the moment of interest — a model response arriving, say — and the values wait there until someone
/// captures. Once `capacity` is reached the oldest values are dropped.
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

/// Folds whatever is sitting in an ``EventBuffer`` into one JSON array at capture time.
///
/// An empty buffer yields no artifact. Measuring does not drain the buffer, so back-to-back captures repeat the
/// same values until something clears it. The element's Swift type name is written to `attributes["type"]`.
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
