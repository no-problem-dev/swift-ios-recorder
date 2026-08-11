import Foundation

/// Runs every source on demand, saves the record they add up to, and hands it to the exporters. One per debug session.
///
/// Saving is the only step that can fail the caller. Export failures are kept as ``ExportOutcome`` and read back
/// through ``deliveryState(for:)``, so a capture is never lost because the receiver was unreachable.
public actor Session {
    public nonisolated let id: SessionID
    public nonisolated let appVersion: String?
    private let sources: [any Source]
    private let store: any RecordStore
    private var exporters: [any Exporter]
    /// Delivery results per capture, capped at `outcomeCapacity`. Older captures lose their
    /// history and read back as pending even if they were delivered.
    private var outcomes: [RecordID: [ExportOutcome]] = [:]
    private var outcomeOrder: [RecordID] = []
    private let outcomeCapacity = 200

    public init(
        id: SessionID = .generate(),
        appVersion: String? = nil,
        sources: [any Source],
        store: any RecordStore,
        exporters: [any Exporter] = []
    ) {
        self.id = id
        self.appVersion = appVersion
        self.sources = sources
        self.store = store
        self.exporters = exporters
    }

    /// Adds an export route to a running session; captures taken before this are not sent, pass them to ``reexport(_:)``.
    public func attach(_ exporter: any Exporter) {
        exporters.append(exporter)
    }

    /// Puts an already-saved capture through the exporters again, replacing whatever outcomes it had.
    @discardableResult
    public func reexport(_ record: Record) async -> [ExportOutcome] {
        await deliver(record)
    }

    /// One outcome per exporter, or empty when the capture is old enough to have been evicted from the outcome log.
    public func outcomes(for id: RecordID) -> [ExportOutcome] {
        outcomes[id] ?? []
    }

    /// Collapses the per-exporter outcomes into the single state a list row can show.
    ///
    /// Anything with no recorded outcome reads as `.pending`, which includes captures whose history has aged out
    /// of the log — an old capture can therefore claim to be pending long after it was delivered.
    public func deliveryState(for id: RecordID) -> DeliveryState {
        guard !exporters.isEmpty else { return .notExported }
        let results = outcomes[id] ?? []
        if results.isEmpty { return .pending(reason: nil) }
        if results.allSatisfy(\.succeeded) { return .delivered }
        let reason = results.first(where: { !$0.succeeded })?.error
        return .pending(reason: reason)
    }

    /// Outcomes across every capture still in the log, newest capture first.
    public func recentOutcomes(limit: Int = 50) -> [ExportOutcome] {
        outcomeOrder.reversed().flatMap { outcomes[$0] ?? [] }.prefix(limit).map { $0 }
    }

    /// Sends to every exporter in turn; one that throws does not stop the others.
    private func deliver(_ record: Record) async -> [ExportOutcome] {
        var results: [ExportOutcome] = []
        for exporter in exporters {
            do {
                try await exporter.export(record)
                results.append(ExportOutcome(recordID: record.id, exporter: exporter.label, succeeded: true, at: Date()))
            } catch {
                results.append(ExportOutcome(recordID: record.id, exporter: exporter.label, succeeded: false, error: "\(error)", at: Date()))
            }
        }
        track(outcomes: results, for: record.id)
        return results
    }

    private func track(outcomes results: [ExportOutcome], for id: RecordID) {
        if outcomes[id] == nil { outcomeOrder.append(id) }
        outcomes[id] = results
        while outcomeOrder.count > outcomeCapacity {
            let evicted = outcomeOrder.removeFirst()
            outcomes[evicted] = nil
        }
    }

    /// Measures every source concurrently and saves the one capture they add up to.
    ///
    /// Sources that return `nil` are simply absent from the result, and artifacts arrive in completion order
    /// rather than the order the sources were listed.
    /// - Throws: Whatever the store throws while saving. Export failures are recorded, never raised.
    @discardableResult
    public func capture(
        screenName: String? = nil,
        tags: [String] = [],
        attributes: [String: String] = [:]
    ) async throws -> RecordID {
        let context = RecordContext(session: id, screenName: screenName, attributes: attributes)

        var artifacts: [Artifact] = []
        await withTaskGroup(of: Artifact?.self) { group in
            for source in sources {
                group.addTask { await source.measure(context) }
            }
            for await artifact in group {
                if let artifact { artifacts.append(artifact) }
            }
        }

        let record = Record(
            id: .generate(),
            session: id,
            recordedAt: Date(),
            metadata: RecordMetadata(
                screenName: screenName,
                appVersion: appVersion,
                tags: tags,
                attributes: attributes
            ),
            artifacts: artifacts
        )

        try await store.save(record)
        // Export is best effort: a failure here must not lose the capture that is already saved.
        _ = await deliver(record)
        return record.id
    }
}
