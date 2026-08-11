import Foundation

/// Everything about a capture except its payload: which screen, which app version, and the caller's own labels.
///
/// This is the only text ``RecordQuery`` searches. Nothing inside an artifact is ever matched, so a value that
/// must be findable later belongs in `tags` or `attributes`.
public struct RecordMetadata: Sendable, Codable, Equatable {
    public var screenName: String?
    public var appVersion: String?
    public var tags: [String]
    public var attributes: [String: String]

    public init(
        screenName: String? = nil,
        appVersion: String? = nil,
        tags: [String] = [],
        attributes: [String: String] = [:]
    ) {
        self.screenName = screenName
        self.appVersion = appVersion
        self.tags = tags
        self.attributes = attributes
    }
}

/// One capture: every artifact the sources produced at a single moment, with the metadata to find it again.
///
/// Holds the raw artifact bytes, and a screenshot is megabytes, so lists work from ``RecordSummary`` and only
/// fetch the whole record when the payload is actually needed.
public struct Record: Sendable, Identifiable, Codable, Equatable {
    public let id: RecordID
    public let session: SessionID
    public let recordedAt: Date
    public let metadata: RecordMetadata
    public let artifacts: [Artifact]

    public init(
        id: RecordID,
        session: SessionID,
        recordedAt: Date,
        metadata: RecordMetadata,
        artifacts: [Artifact]
    ) {
        self.id = id
        self.session = session
        self.recordedAt = recordedAt
        self.metadata = metadata
        self.artifacts = artifacts
    }
}

/// A capture with the artifact bytes dropped, keeping only which kinds were taken.
///
/// This is what ``RecordStore/query(_:)`` returns and what ``RecordQuery`` filters on, so listing thousands of
/// captures costs no image memory and no tokens on the way to an agent.
public struct RecordSummary: Sendable, Identifiable, Codable, Equatable {
    public let id: RecordID
    public let session: SessionID
    public let recordedAt: Date
    public let metadata: RecordMetadata
    public let artifactKinds: [ArtifactKind]

    public init(
        id: RecordID,
        session: SessionID,
        recordedAt: Date,
        metadata: RecordMetadata,
        artifactKinds: [ArtifactKind]
    ) {
        self.id = id
        self.session = session
        self.recordedAt = recordedAt
        self.metadata = metadata
        self.artifactKinds = artifactKinds
    }

    public init(record: Record) {
        self.init(
            id: record.id,
            session: record.session,
            recordedAt: record.recordedAt,
            metadata: record.metadata,
            artifactKinds: record.artifacts.map(\.kind)
        )
    }
}
