import Foundation

/// 計器の中核。トリガを受けて Source を回し、Record を組み立て、Store に保持し、
/// 任意で Exporter に出す。1 デバッグセッションに 1 つ。
public actor Session {
    public nonisolated let id: SessionID
    public nonisolated let appVersion: String?
    private let sources: [any Source]
    private let store: any RecordStore
    private var exporters: [any Exporter]

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

    /// 既存の記録を出力ポートへ再送信する（best-effort）。
    public func reexport(_ record: Record) async {
        for exporter in exporters {
            try? await exporter.export(record)
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
        // 出力は best-effort。失敗しても保持は守る。
        for exporter in exporters {
            try? await exporter.export(record)
        }
        return record.id
    }
}
