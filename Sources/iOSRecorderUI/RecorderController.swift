import Foundation
import Observation
import iOSRecorder
import iOSRecorderNetwork
import iOSRecorderBonjour

/// 計器 UI の状態を持つコントローラ。UIKit 非依存なので隔離テストできる。
@MainActor
@Observable
public final class RecorderController {
    public let session: Session
    private let store: any RecordStore
    public let items: [DebugItem]
    /// 通信ライブモニタ（任意・独立サブシステム）。あればパネルに Network が出る。
    public let network: NetworkLogStore?
    /// Mac 受信デーモンの到達性（任意）。あればパネルに接続状態が出る。
    public let reachability: ExportReachability?
    public private(set) var summaries: [RecordSummary] = []
    public var isPresentingPanel = false
    public var captureScreenName = ""
    /// 現在表示中の画面名。`.recorderScreen(_:)` が設定し、撮影時に自動付与される。
    public var currentScreen: String?

    public init(
        session: Session,
        store: any RecordStore,
        network: NetworkLogStore? = nil,
        reachability: ExportReachability? = nil,
        items: [DebugItem] = []
    ) {
        self.session = session
        self.store = store
        self.network = network
        self.reachability = reachability
        self.items = items
    }

    /// 現在の画面を計測して保持し、一覧を更新する。
    public func capture(screenName: String? = nil) async {
        _ = try? await session.capture(screenName: screenName ?? currentScreen)
        await refresh()
    }

    /// パネルで入力された画面名を使って撮影する。
    public func captureWithEnteredName() async {
        let trimmed = captureScreenName.trimmingCharacters(in: .whitespacesAndNewlines)
        await capture(screenName: trimmed.isEmpty ? nil : trimmed)
        captureScreenName = ""
    }

    public func refresh() async {
        summaries = (try? await store.query(RecordQuery(limit: 100))) ?? []
    }

    public func record(for id: RecordID) async -> Record? {
        try? await store.fetch(id)
    }

    public func reexport(_ record: Record) async {
        await session.reexport(record)
    }

    public func removeAll() async {
        try? await store.removeAll()
        await refresh()
    }
}
