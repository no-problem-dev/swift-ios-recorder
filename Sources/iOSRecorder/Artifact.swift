import Foundation

/// Names what an artifact holds, and what ``RecordQuery/kinds`` filters on.
///
/// Deliberately open: an app can mint its own kind with `init(rawValue:)` without this package adding a constant,
/// and the new kind still travels through storage, transport, and MCP untouched.
public struct ArtifactKind: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public extension ArtifactKind {
    static let screenshot = ArtifactKind(rawValue: "screenshot")
    static let state = ArtifactKind(rawValue: "state")
    static let log = ArtifactKind(rawValue: "log")
}

extension ArtifactKind: Codable {
    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One measured payload, carrying the media type a reader needs to make sense of the bytes.
///
/// The core never looks inside `data`. That is what lets a new kind of evidence reach a consumer without any
/// change to storage, the wire format, or the MCP layer.
public struct Artifact: Sendable, Codable, Equatable {
    public let kind: ArtifactKind
    public let mediaType: String
    public let data: Data
    public let attributes: [String: String]

    public init(kind: ArtifactKind, mediaType: String, data: Data, attributes: [String: String] = [:]) {
        self.kind = kind
        self.mediaType = mediaType
        self.data = data
        self.attributes = attributes
    }
}

public extension Artifact {
    static func screenshot(pngData: Data, attributes: [String: String] = [:]) -> Artifact {
        Artifact(kind: .screenshot, mediaType: "image/png", data: pngData, attributes: attributes)
    }
    static func screenshot(jpegData: Data, attributes: [String: String] = [:]) -> Artifact {
        Artifact(kind: .screenshot, mediaType: "image/jpeg", data: jpegData, attributes: attributes)
    }
    static func state(json: Data, attributes: [String: String] = [:]) -> Artifact {
        Artifact(kind: .state, mediaType: "application/json", data: json, attributes: attributes)
    }
    static func log(text: String, attributes: [String: String] = [:]) -> Artifact {
        Artifact(kind: .log, mediaType: "text/plain", data: Data(text.utf8), attributes: attributes)
    }
}
