import Foundation
import Observation

/// 通信ログのライブバッファ。新しい順に積み、上限を超えたら古いものを捨てる。
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
