import Foundation
import iOSRecorder

/// デバッグイベントの検索条件。
public struct DebugEventQuery: Sendable {
    public var captureID: RecordID?
    public var category: String?
    public var name: String?
    /// summary / name / attributes への部分一致（大文字小文字を無視）。
    public var text: String?
    public var since: Date?
    public var limit: Int = 50

    public init() {}
}

/// 検索でヒットしたイベントと、それが属する capture。
public struct DebugEventHit: Sendable {
    public let captureID: RecordID
    public let event: DebugEvent
}

/// 検索結果と走査の事実。打ち切りを黙らせない（見つからない ≠ 存在しない、を AI に伝える）。
public struct DebugEventSearchResult: Sendable {
    public let hits: [DebugEventHit]
    /// 実際に走査した capture 数。
    public let scannedCaptures: Int
    /// 走査上限で打ち切られ、未走査の capture が残っているか。
    public let scanTruncated: Bool
}

/// RecordStore を MCP ツール群に橋渡しするドメイン層。
public actor RecordMCPServer {
    private let store: any RecordStore
    /// captureID 未指定の検索で走査する capture 数の上限。
    private let maxScannedCaptures: Int

    public init(store: any RecordStore, maxScannedCaptures: Int = 50) {
        self.store = store
        self.maxScannedCaptures = max(1, maxScannedCaptures)
    }

    public func listCaptures(_ query: RecordQuery = RecordQuery()) async throws -> [RecordSummary] {
        try await store.query(query)
    }

    public func getCapture(_ id: RecordID) async throws -> Record {
        try await store.fetch(id)
    }

    public func deleteCapture(_ id: RecordID) async throws {
        try await store.delete(id)
    }

    public func clearCaptures() async throws {
        try await store.removeAll()
    }

    /// capture 横断（新しい順）でデバッグイベントを検索する。
    public func searchEvents(_ query: DebugEventQuery) async throws -> DebugEventSearchResult {
        let records: [Record]
        var scanTruncated = false
        if let captureID = query.captureID {
            records = [try await store.fetch(captureID)]
        } else {
            var recordQuery = RecordQuery()
            recordQuery.kinds = [.debugTimeline]
            if let since = query.since { recordQuery.timeRange = since ... .distantFuture }
            let summaries = try await store.query(recordQuery)
            scanTruncated = summaries.count > maxScannedCaptures
            var fetched: [Record] = []
            for summary in summaries.prefix(maxScannedCaptures) {
                if let record = try? await store.fetch(summary.id) { fetched.append(record) }
            }
            records = fetched
        }

        var hits: [DebugEventHit] = []
        for record in records {
            for event in Self.timelineEvents(in: record) where Self.matches(event, query) {
                hits.append(DebugEventHit(captureID: record.id, event: event))
                if hits.count >= query.limit {
                    return DebugEventSearchResult(hits: hits, scannedCaptures: records.count, scanTruncated: scanTruncated)
                }
            }
        }
        return DebugEventSearchResult(hits: hits, scannedCaptures: records.count, scanTruncated: scanTruncated)
    }

    /// 指定 capture 内のイベントを payload 込みで 1 件返す。
    public func getEvent(capture: RecordID, eventID: UUID) async throws -> DebugEvent? {
        Self.timelineEvents(in: try await store.fetch(capture)).first { $0.id == eventID }
    }

    static func timelineEvents(in record: Record) -> [DebugEvent] {
        guard let artifact = record.artifacts.first(where: { $0.kind == .debugTimeline }) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([DebugEvent].self, from: artifact.data)) ?? []
    }

    private static func matches(_ event: DebugEvent, _ query: DebugEventQuery) -> Bool {
        if let category = query.category, event.category != category { return false }
        if let name = query.name, event.name != name { return false }
        if let since = query.since, event.at < since { return false }
        if let text = query.text, !text.isEmpty {
            let haystack = ([event.name, event.summary]
                + event.attributes.map { "\($0.key)=\($0.value)" }).joined(separator: " ").lowercased()
            if !haystack.contains(text.lowercased()) { return false }
        }
        return true
    }
}
