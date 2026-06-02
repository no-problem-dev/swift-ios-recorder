import Foundation

/// アプリの state を JSON として計測する Source。
/// 値は measure 時点で評価される（クロージャ渡し）。
public struct StateSource: Source {
    public let kind = ArtifactKind.state
    private let provider: @Sendable () async -> Data

    public init(_ provider: @escaping @Sendable () async -> Data) {
        self.provider = provider
    }

    /// Encodable な値を measure 時点で JSON 化する。
    public init<Value: Encodable & Sendable>(encoding provider: @escaping @Sendable () async -> Value) {
        self.provider = {
            let value = await provider()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return (try? encoder.encode(value)) ?? Data("{}".utf8)
        }
    }

    public func measure(_ context: RecordContext) async -> Artifact? {
        .state(json: await provider())
    }
}
