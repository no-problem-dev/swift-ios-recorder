import Foundation

/// The filter every store understands, stated without reference to how records are kept.
///
/// `text` searches metadata only — screen name, tags, attributes — never artifact bytes, so a string that appears
/// solely inside a log or a state dump is not findable. An in-memory store can satisfy its whole query duty with
/// ``matches(_:)``.
public struct RecordQuery: Sendable, Equatable {
    public var session: SessionID?
    public var screenName: String?
    public var kinds: Set<ArtifactKind>
    public var timeRange: ClosedRange<Date>?
    public var text: String?
    public var limit: Int

    public init(
        session: SessionID? = nil,
        screenName: String? = nil,
        kinds: Set<ArtifactKind> = [],
        timeRange: ClosedRange<Date>? = nil,
        text: String? = nil,
        limit: Int = 100
    ) {
        self.session = session
        self.screenName = screenName
        self.kinds = kinds
        self.timeRange = timeRange
        self.text = text
        self.limit = limit
    }

    /// Whether one summary passes every condition that was set.
    ///
    /// `limit` is not applied here — a store that filters with this still has to trim the result itself.
    public func matches(_ summary: RecordSummary) -> Bool {
        if let session, summary.session != session { return false }
        if let screenName, summary.metadata.screenName != screenName { return false }
        if !kinds.isEmpty, kinds.isDisjoint(with: Set(summary.artifactKinds)) { return false }
        if let timeRange, !timeRange.contains(summary.recordedAt) { return false }
        if let text, !text.isEmpty {
            let haystack = searchableText(of: summary).lowercased()
            if !haystack.contains(text.lowercased()) { return false }
        }
        return true
    }

    private func searchableText(of summary: RecordSummary) -> String {
        var parts: [String] = []
        if let name = summary.metadata.screenName { parts.append(name) }
        parts.append(contentsOf: summary.metadata.tags)
        for (key, value) in summary.metadata.attributes { parts.append(key); parts.append(value) }
        return parts.joined(separator: " ")
    }
}
