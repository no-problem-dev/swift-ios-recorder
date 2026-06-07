import Foundation
import Observation
import DesignSystem
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
    /// 未送分の退避・再送（任意）。あればパネルに pending 件数が出て、到達時に自動 drain。
    public let outbox: (any OutboxDraining)?
    /// デバッグイベントのライブログ（任意）。あればパネルに Debug タイムラインが出る。
    public let debugLog: DebugLog?
    /// 利用側が差し込むメトリクス（任意）。あればパネルにメトリクス・ダッシュボードが出る。
    public let metrics: MetricsStore?
    /// パネルの画面構成（任意）。未指定なら存在するストアから既定構成を自動合成する。
    public let console: DebugConsole?
    /// 計器 UI に適用するデザインシステムのテーマ。利用側ブランドに合わせて差し替え可能。
    public let theme: ThemeProvider
    public private(set) var summaries: [RecordSummary] = []
    /// キャプチャごとの配送状態（delivered / pending）。refresh で更新。
    public private(set) var deliveryStates: [RecordID: DeliveryState] = [:]
    /// 未送（退避中）件数。
    public private(set) var pendingCount = 0
    public var isPresentingPanel = false
    /// フロートボタン群（📷 / 🐞）の表示状態。iOS では既定で隠れていて、シェイクでトグルする。
    /// シェイクの無い macOS では常時表示。
    #if canImport(UIKit)
    public var isOverlayVisible = false
    #else
    public var isOverlayVisible = true
    #endif
    public var captureScreenName = ""
    /// 現在表示中の画面名。`.recorderScreen(_:)` が設定し、撮影時に自動付与される。
    public var currentScreen: String?
    @ObservationIgnored private var autoDrainTask: Task<Void, Never>?

    public init(
        session: Session,
        store: any RecordStore,
        network: NetworkLogStore? = nil,
        reachability: ExportReachability? = nil,
        outbox: (any OutboxDraining)? = nil,
        debugLog: DebugLog? = nil,
        metrics: MetricsStore? = nil,
        items: [DebugItem] = [],
        console: DebugConsole? = nil,
        theme: ThemeProvider? = nil
    ) {
        self.session = session
        self.store = store
        self.network = network
        self.reachability = reachability
        self.outbox = outbox
        self.debugLog = debugLog
        self.metrics = metrics
        self.items = items
        self.console = console
        self.theme = theme ?? ThemeProvider()
        if outbox != nil { startAutoDrain() }
    }

    /// バックグラウンドで未送分を自動再送するループ。pending があり到達できれば送る。
    /// パネルを開かなくても、接続が回復すれば数秒で勝手に届く。
    public func startAutoDrain(interval: Duration = .seconds(5)) {
        guard outbox != nil, autoDrainTask == nil else { return }
        autoDrainTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.drainIfPossible()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stopAutoDrain() {
        autoDrainTask?.cancel()
        autoDrainTask = nil
    }

    private func drainIfPossible() async {
        guard let outbox else { return }
        let pending = await outbox.pendingCount()
        pendingCount = pending
        guard pending > 0, reachability?.isReachable ?? true else { return }
        if await outbox.drain() > 0 { await refresh() }
    }

    /// 現在の画面を計測して保持し、一覧を更新する。
    public func capture(screenName: String? = nil) async {
        _ = try? await session.capture(screenName: screenName ?? currentScreen)
        await refresh()
    }

    /// 指定キャプチャの配送状態。
    public func deliveryState(for id: RecordID) -> DeliveryState {
        deliveryStates[id] ?? .pending(reason: nil)
    }

    /// 退避中を含めて未送分を再送する。
    public func resend(_ id: RecordID) async {
        if let record = try? await store.fetch(id) {
            await session.reexport(record)
        }
        await outbox?.drain()
        await refresh()
    }

    /// パネルで入力された画面名を使って撮影する。
    public func captureWithEnteredName() async {
        let trimmed = captureScreenName.trimmingCharacters(in: .whitespacesAndNewlines)
        await capture(screenName: trimmed.isEmpty ? nil : trimmed)
        captureScreenName = ""
    }

    public func refresh() async {
        // 到達できているなら退避分を自動再送してから一覧を更新する。
        if let outbox, reachability?.isReachable ?? true {
            await outbox.drain()
        }
        summaries = (try? await store.query(RecordQuery(limit: 100))) ?? []
        var states: [RecordID: DeliveryState] = [:]
        for summary in summaries {
            states[summary.id] = await session.deliveryState(for: summary.id)
        }
        deliveryStates = states
        pendingCount = await outbox?.pendingCount() ?? 0
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
