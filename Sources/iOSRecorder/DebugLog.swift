import Foundation
import Observation

/// The live, ordered buffer every debug event flows into, observable so SwiftUI streams it with no extra plumbing.
///
/// Bound to the main actor, so a background task has to hop before emitting. Once `capacity` is reached the
/// oldest events are dropped, and a capture only ever sees what is left.
@MainActor
@Observable
public final class DebugLog {
    public private(set) var events: [DebugEvent] = []
    private let capacity: Int

    public init(capacity: Int = 1000) {
        self.capacity = max(1, capacity)
    }

    public func emit(_ event: DebugEvent) {
        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
    }

    /// Events from one category, in the order they arrived.
    public func events(in category: String) -> [DebugEvent] {
        events.filter { $0.category == category }
    }

    /// Categories present in the buffer right now, in order of first appearance — a category vanishes once its
    /// last event is evicted.
    public var categories: [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for event in events where seen.insert(event.category).inserted {
            ordered.append(event.category)
        }
        return ordered
    }

    public func clear() { events.removeAll() }
}

/// Subscribes to one source of domain events and feeds them into a log as normalized entries.
///
/// Network traffic, agent steps, generated surfaces, and anything bespoke all arrive the same way, which is what
/// keeps the timeline a single list instead of one view per subsystem.
public protocol DebugProbe: Sendable {
    var category: String { get }
    /// Starts the subscription and keeps emitting into `log` for as long as the source produces events.
    ///
    /// There is no counterpart that stops it, so attach a probe once and let it live as long as the log does.
    @MainActor func attach(to log: DebugLog)
}
