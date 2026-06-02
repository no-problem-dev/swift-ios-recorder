import Foundation
import Observation

/// デバッグイベントのライブな順序付きバッファ。`NetworkLogStore` と同じく @Observable なので
/// SwiftUI でそのままストリーミング表示でき、`DebugLogSource` が capture 時に snapshot する。
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

    /// 指定カテゴリのイベントだけを古い順に返す。
    public func events(in category: String) -> [DebugEvent] {
        events.filter { $0.category == category }
    }

    /// 登場したカテゴリの一覧（出現順）。
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

/// ドメインのイベント源を購読し、DebugEvent として `DebugLog` に流し込む生産者。
/// network/agent/a2ui/任意構造体 はすべてこのプロトコルの実装として揃える。
public protocol DebugProbe: Sendable {
    var category: String { get }
    /// 購読を開始し、以降ドメインイベントを `log` に emit し続ける。
    @MainActor func attach(to log: DebugLog)
}
