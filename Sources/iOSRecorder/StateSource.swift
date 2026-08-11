import Foundation

/// Captures app state as JSON, read at the moment of capture rather than when the source was built.
///
/// Always produces an artifact, even for empty data — use ``TypedStateSource`` when a capture should be able to
/// skip the state entirely.
public struct StateSource: Source {
    public let kind = ArtifactKind.state
    private let provider: @Sendable () async -> Data

    public init(_ provider: @escaping @Sendable () async -> Data) {
        self.provider = provider
    }

    /// Encodes whatever the provider returns, at the moment of capture.
    ///
    /// A value that fails to encode is recorded as `{}`, which is indistinguishable from genuinely empty state.
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
