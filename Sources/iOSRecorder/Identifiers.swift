import Foundation

/// Identifies one capture, and is the folder name a file-backed store writes it under.
///
/// Encodes as a bare JSON string rather than an object, so stored metadata and wire payloads stay readable by eye.
public struct RecordID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static func generate() -> RecordID { RecordID(rawValue: UUID().uuidString) }
}

/// Groups the captures taken through one ``Session``, which is how ``RecordQuery`` separates one run from the next.
///
/// A new id is generated per session by default, so relaunching the app starts a new group.
public struct SessionID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static func generate() -> SessionID { SessionID(rawValue: UUID().uuidString) }
}

// Serialize as a bare string instead of {"rawValue": …}.
extension RecordID: Codable {
    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension SessionID: Codable {
    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
