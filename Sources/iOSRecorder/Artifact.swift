import Foundation

/// 中身の種別。typed だが開いている（新種は定数を足さずとも生成できる）。
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

/// 計測された 1 つの中身。data はコアにとって不透明 — 新種が増えても
/// 通信・保存・MCP は無改修で流せる。
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
    static func state(json: Data, attributes: [String: String] = [:]) -> Artifact {
        Artifact(kind: .state, mediaType: "application/json", data: json, attributes: attributes)
    }
    static func log(text: String, attributes: [String: String] = [:]) -> Artifact {
        Artifact(kind: .log, mediaType: "text/plain", data: Data(text.utf8), attributes: attributes)
    }
}
