import Foundation

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

/// ある瞬間に保持された観測単位。
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

/// 一覧用の軽量表現。artifact の data を含まない（トークン節約）。
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
