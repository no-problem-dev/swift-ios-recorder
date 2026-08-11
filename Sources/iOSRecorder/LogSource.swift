import Foundation

/// Holds the last `capacity` log lines so a capture can carry recent output along with it.
///
/// Point the app's logging at ``append(_:)``; older lines fall off the front, and ``snapshot()`` joins what is
/// left with newlines.
public actor LogBuffer {
    private var lines: [String] = []
    private let capacity: Int

    public init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
    }

    public func append(_ line: String) {
        lines.append(line)
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
    }

    public func snapshot() -> String {
        lines.joined(separator: "\n")
    }

    public func clear() {
        lines.removeAll()
    }
}

/// Attaches whatever text the provider returns at capture time; empty text yields no artifact rather than an empty one.
public struct LogSource: Source {
    public let kind = ArtifactKind.log
    private let provider: @Sendable () async -> String

    public init(_ provider: @escaping @Sendable () async -> String) {
        self.provider = provider
    }

    public init(buffer: LogBuffer) {
        self.provider = { await buffer.snapshot() }
    }

    public func measure(_ context: RecordContext) async -> Artifact? {
        let text = await provider()
        return text.isEmpty ? nil : .log(text: text)
    }
}
