import Foundation
import iOSRecorder

public extension ArtifactKind {
    /// Recent HTTP traffic. Declared by the target that produces it rather than by the core, which
    /// is how a new kind gets added without touching the core.
    static let network = ArtifactKind(rawValue: "network")
}

/// Folds the live traffic buffer into one JSON artifact at the moment of capture.
///
/// The buffer is a continuous stream and a record is a single instant, so what lands in the record
/// is the newest `maxEntries` exchanges as they stood when the trigger fired — including ones that
/// started long before it. Every entry goes through `NetworkLog.redacted(bodyLimit:)` on the way.
public struct NetworkSource: Source {
    public let kind = ArtifactKind.network
    private let store: NetworkLogStore
    private let maxEntries: Int
    private let bodyLimit: Int

    public init(store: NetworkLogStore, maxEntries: Int = 50, bodyLimit: Int = 4096) {
        self.store = store
        self.maxEntries = max(1, maxEntries)
        self.bodyLimit = bodyLimit
    }

    public func measure(_ context: RecordContext) async -> Artifact? {
        let entries = await snapshot()
        guard !entries.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return nil }
        return Artifact(
            kind: .network,
            mediaType: "application/json",
            data: data,
            attributes: ["type": "NetworkLog", "count": "\(entries.count)"]
        )
    }

    private func snapshot() async -> [NetworkLog] {
        let limit = maxEntries
        let limitBytes = bodyLimit
        return await MainActor.run {
            store.logs.prefix(limit).map { $0.redacted(bodyLimit: limitBytes) }
        }
    }
}
