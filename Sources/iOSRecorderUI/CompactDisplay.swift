import Foundation

/// The limits behind the debug UI's "folded until asked" rule for large values.
/// They are what keeps a huge payload, a deep JSON tree or a very long array readable and scrolling.
enum CompactDisplay {
    /// Characters of a long text block shown before the rest is folded away.
    static let textPreviewLimit = 600
    /// Characters of a string value inside a JSON tree shown before the rest is folded away.
    static let leafPreviewLimit = 200
    /// Children rendered when an object or array first appears; the rest wait behind a reveal button.
    static let initialChildren = 30
    /// Children added by each tap of the reveal button.
    static let childrenStep = 100

    static func preview(_ text: String, limit: Int) -> (shown: String, truncated: Bool) {
        guard text.count > limit else { return (text, false) }
        return (String(text.prefix(limit)), true)
    }

    /// Only the top level of a structured tree opens on its own; anything deeper starts folded.
    static func expandedByDefault(depth: Int) -> Bool {
        depth == 0
    }

    static func formatBytes(_ bytes: Int) -> String {
        switch bytes {
        case ..<1024: "\(bytes) B"
        case ..<1_048_576: "\((bytes + 512) / 1024) KB"
        default: String(format: "%.1f MB", Double(bytes) / 1_048_576)
        }
    }
}
