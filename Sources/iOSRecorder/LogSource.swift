import Foundation

/// 直近のログ行を保持する固定長バッファ。アプリのログ出力先に append しておき、
/// 計測時に snapshot を Record へ添える。
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

/// 直近のログを計測する Source。空なら artifact を作らない。
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
