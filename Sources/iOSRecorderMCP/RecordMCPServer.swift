import Foundation
import iOSRecorder

/// What to look for in a debug event search. Every field set narrows the result further; `category`
/// and `name` match exactly, and an unset field does not filter at all.
public struct DebugEventQuery: Sendable {
    public var captureID: RecordID?
    public var category: String?
    public var name: String?
    /// Substring match, case-insensitive, against the name, the summary and the attributes joined
    /// together — not against the event payload, which search never reads.
    public var text: String?
    public var since: Date?
    public var limit: Int = 50

    public init() {}
}

/// An event that matched, paired with the capture it was found in — which is the handle needed to
/// fetch its payload afterwards.
public struct DebugEventHit: Sendable {
    public let captureID: RecordID
    public let event: DebugEvent
}

/// Matches plus how much ground the search actually covered, so that "nothing found" can be told
/// apart from "stopped looking" by whoever reads the result.
public struct DebugEventSearchResult: Sendable {
    public let hits: [DebugEventHit]
    public let scannedCaptures: Int
    /// Whether captures were left unread because the scan limit was reached. When `true`, absence
    /// of a hit proves nothing — narrow the search or name a capture.
    public let scanTruncated: Bool
}

/// Turns a `RecordStore` into the operations the MCP tools expose, with no JSON-RPC in sight.
public actor RecordMCPServer {
    private let store: any RecordStore
    /// Ceiling on captures opened by a search that does not name one. Searches read whole captures
    /// off disk, so this bounds the cost of a broad query.
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

    /// Searches debug events across captures, newest capture first.
    ///
    /// Naming a capture in the query reads only that one; otherwise captures holding a debug
    /// timeline are read until either `limit` matches accumulate or the scan ceiling is hit, which
    /// the result flags. Captures that fail to load are skipped without comment.
    ///
    /// - Throws: The store's error only when the query names a capture that cannot be read.
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

    /// One event with its payload attached — the second half of the search-then-read pair, since
    /// search deliberately omits payloads. `nil` means the capture holds no event with that id.
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
