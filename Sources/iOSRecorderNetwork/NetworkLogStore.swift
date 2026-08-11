import Foundation
import Observation

/// Live buffer of intercepted traffic, newest first, dropping the oldest past `capacity`.
///
/// Memory only: nothing survives a relaunch, and a request older than the last `capacity` ones is
/// gone even if a capture happens a second later.
@MainActor
@Observable
public final class NetworkLogStore {
    public private(set) var logs: [NetworkLog] = []
    private let capacity: Int

    public init(capacity: Int = 500) {
        self.capacity = max(1, capacity)
    }

    public func add(_ log: NetworkLog) {
        logs.insert(log, at: 0)
        if logs.count > capacity {
            logs.removeLast(logs.count - capacity)
        }
    }

    public func clear() {
        logs.removeAll()
    }
}
