import Foundation

/// A row the app registers in the debug panel: an action to run, a toggle to flip, or a value to read.
/// This is how feature flags and environment switches get a place in the debug UI.
public struct DebugItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    let kind: Kind

    enum Kind: Sendable {
        case action(systemImage: String, run: @MainActor @Sendable () async -> Void)
        case toggle(get: @MainActor @Sendable () -> Bool, set: @MainActor @Sendable (Bool) -> Void)
        case info(value: @MainActor @Sendable () -> String)
    }

    public static func action(
        id: String,
        title: String,
        systemImage: String = "bolt.fill",
        run: @escaping @MainActor @Sendable () async -> Void
    ) -> DebugItem {
        DebugItem(id: id, title: title, kind: .action(systemImage: systemImage, run: run))
    }

    public static func toggle(
        id: String,
        title: String,
        get: @escaping @MainActor @Sendable () -> Bool,
        set: @escaping @MainActor @Sendable (Bool) -> Void
    ) -> DebugItem {
        DebugItem(id: id, title: title, kind: .toggle(get: get, set: set))
    }

    public static func info(
        id: String,
        title: String,
        value: @escaping @MainActor @Sendable () -> String
    ) -> DebugItem {
        DebugItem(id: id, title: title, kind: .info(value: value))
    }
}
