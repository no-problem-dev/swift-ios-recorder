import Foundation

/// 計器の中核。トリガを受けて Source を回し、Record を組み立て、Store に保持し、
/// 任意で Exporter に出す。1 デバッグセッションに 1 つ。
public actor Session {
    public nonisolated let id: SessionID
    public nonisolated let appVersion: String?
    private let sources: [any Source]
    private let store: any RecordStore
    private var exporters: [any Exporter]
    /// キャプチャごとの配送結果。握り潰さず観測できるようにする固定長ログ。
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

    /// 出力能力を後から足す。無くても記録は保持される。
    public func attach(_ exporter: any Exporter) {
        exporters.append(exporter)
    }

    /// 既存の記録を出力ポートへ再送信する。配送結果を記録する。
    @discardableResult
    public func reexport(_ record: Record) async -> [ExportOutcome] {
        await deliver(record)
    }

    /// あるキャプチャの配送結果（exporter ごと）。
    public func outcomes(for id: RecordID) -> [ExportOutcome] {
        outcomes[id] ?? []
    }

    /// あるキャプチャの配送状態を UI 向けに畳んで返す。
    public func deliveryState(for id: RecordID) -> DeliveryState {
        guard !exporters.isEmpty else { return .notExported }
        let results = outcomes[id] ?? []
        if results.isEmpty { return .pending(reason: nil) }
        if results.allSatisfy(\.succeeded) { return .delivered }
        let reason = results.first(where: { !$0.succeeded })?.error
        return .pending(reason: reason)
    }

    /// 直近の配送結果（新しい順）。
    public func recentOutcomes(limit: Int = 50) -> [ExportOutcome] {
        outcomeOrder.reversed().flatMap { outcomes[$0] ?? [] }.prefix(limit).map { $0 }
    }

    /// 全 exporter へ送り、結果を記録して返す。
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

    /// 全 Source を並列に回して 1 つの Record を組み立て、保持する。
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
        // 出力は best-effort。失敗しても保持は守るが、結果は握り潰さず記録する。
        _ = await deliver(record)
        return record.id
    }
}
