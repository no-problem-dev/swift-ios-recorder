import Foundation

/// Captures any encodable value, tagged with its Swift type name and a kind of the app's choosing.
///
/// Two things it adds over ``StateSource``:
/// - the value's Swift type name lands in `attributes["type"]`, so a consumer can tell payloads apart
/// - the kind is yours to pick, and giving a family its own kind makes ``RecordQuery/kinds`` a usable filter
///
/// A provider returning `nil` skips that capture rather than writing an empty artifact. A value that fails to
/// encode is recorded as `{}`.
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
