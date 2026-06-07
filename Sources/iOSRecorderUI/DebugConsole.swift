import SwiftUI
import DesignSystem
import iOSRecorder
import iOSRecorderNetwork

/// デバッグパネルの画面構成スペック。利用側がセクションの種類・順序・配置を宣言的に決める。
/// 「何をどの順でどう配置するか」を利用側に完全に委ねるための SSOT（AWS コンソール的な構成）。
public struct DebugConsole {
    public var sections: [DebugSection]

    public init(sections: [DebugSection]) {
        self.sections = sections
    }

    public init(@DebugConsoleBuilder _ build: () -> [DebugSection]) {
        self.sections = build()
    }
}

/// 構成の 1 区画。種類（content）と表示メタ（タイトル・アイコン・レイアウト）＋プレビューを持つ。
public struct DebugSection: Identifiable {
    public enum Layout: Sendable { case card, navigationLink, inline }

    public let id: String
    let title: String?
    let icon: String?
    let layout: Layout
    let content: Content
    /// 動線カードに出す「タップ前の覗き見」。空なら見出しのみ。
    let preview: [DebugPreviewElement]

    enum Content {
        case connection
        case metrics(MetricsStore)
        case timeline(DebugLog, category: String?)
        case network(NetworkLogStore)
        case captures
        case items([DebugItem])
        case statGrid(columns: Int, stats: [DebugStat])
        case custom(AnyView)
        /// 手元データの掃除・再送（ライブ件数付きの操作セット）。
        case maintenance(DebugLog?, NetworkLogStore?, (any OutboxDraining)?)
        /// 任意画面への動線カード（デザインカタログ等）。
        case screen(AnyView, tint: Color)
    }

    init(id: String, title: String?, icon: String?, layout: Layout, content: Content, preview: [DebugPreviewElement] = []) {
        self.id = id
        self.title = title
        self.icon = icon
        self.layout = layout
        self.content = content
        self.preview = preview
    }
}

// MARK: - プレビュー語彙（タップ前に出す覗き見プリミティブ）

/// 動線カードの状態ピル。問題スセント（警告・エラー）を一目で見せる。
public enum PreviewStatus: Sendable {
    case ok
    case warning(Int)
    case error(Int)
    case neutral(String)
}

/// インライン数値タイル 1 つ（ラベル＋整形済み値）。
public struct PreviewStat: Sendable {
    public let label: String
    public let value: String
    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// プレビューに並べる要素。パッケージがデザインシステムで一貫描画する。
/// 値はクロージャで、カード body 評価時に @Observable ストアを読めばライブ更新される。
public enum DebugPreviewElement {
    /// 状態ピル（見出しへホイスト）。エラー/警告ならアイコンも色付く。
    case status(@MainActor () -> PreviewStatus)
    /// 最新 1 件の一行サマリ（nil なら「まだなし」）。
    case latest(@MainActor () -> String?)
    /// インライン数値の並び（メトリクスの合計など、タップ不要で見える値）。
    case stats(@MainActor () -> [PreviewStat])
    /// 直近の活動トレンド（極小バー）。全て 0 なら描画しない。
    case sparkline(@MainActor () -> [Double])
    /// カテゴリ/タグの覗き見チップ。
    case chips(@MainActor () -> [String])
}

/// StatGrid に並ぶライブ数値タイル 1 枚。
public struct DebugStat: Identifiable {
    public let id: String
    let title: String
    let icon: String?
    let tint: Color?
    let value: @MainActor () -> String
    let caption: (@MainActor () -> String)?

    public init(
        _ title: String,
        icon: String? = nil,
        tint: Color? = nil,
        caption: (@MainActor () -> String)? = nil,
        value: @escaping @MainActor () -> String
    ) {
        self.id = title
        self.title = title
        self.icon = icon
        self.tint = tint
        self.caption = caption
        self.value = value
    }
}

// MARK: - セクションファクトリ（宣言的に並べる）

public extension DebugSection {
    /// Mac 受信デーモンへの接続状態。
    static func connection(id: String = "connection") -> DebugSection {
        DebugSection(id: id, title: nil, icon: nil, layout: .card, content: .connection)
    }

    /// メトリクス・ダッシュボードへの導線。既定で合計値をカード上にインライン表示する。
    static func metrics(_ store: MetricsStore, id: String = "metrics", title: String = "メトリクス", icon: String = "chart.bar.xaxis", preview: [DebugPreviewElement]? = nil) -> DebugSection {
        DebugSection(id: id, title: title, icon: icon, layout: .navigationLink, content: .metrics(store),
                     preview: preview ?? DebugPreview.metrics(store))
    }

    /// デバッグイベントのタイムライン。`category` を渡すとその関心だけに絞り込む。
    /// 既定で「状態・最新・活動」をプレビューする。
    static func timeline(_ title: String = "Debug ログ", log: DebugLog, category: String? = nil, id: String? = nil, icon: String = "waveform.path.ecg", preview: [DebugPreviewElement]? = nil) -> DebugSection {
        DebugSection(id: id ?? "timeline.\(category ?? "all")", title: title, icon: icon, layout: .navigationLink, content: .timeline(log, category: category),
                     preview: preview ?? DebugPreview.timeline(log, category: category))
    }

    /// 通信ライブモニタ。既定で最新リクエストと成否をプレビューする。
    static func network(_ store: NetworkLogStore, id: String = "network", title: String = "Network", icon: String = "network", preview: [DebugPreviewElement]? = nil) -> DebugSection {
        DebugSection(id: id, title: title, icon: icon, layout: .navigationLink, content: .network(store),
                     preview: preview ?? DebugPreview.network(store))
    }

    /// 記録（キャプチャ）一覧。
    static func captures(id: String = "captures", title: String = "記録") -> DebugSection {
        DebugSection(id: id, title: title, icon: nil, layout: .inline, content: .captures)
    }

    /// アプリが差し込むアクション／トグル／情報の集合。
    static func items(_ items: [DebugItem], id: String = "items") -> DebugSection {
        DebugSection(id: id, title: nil, icon: nil, layout: .card, content: .items(items))
    }

    /// ひと目で分かる数値タイルのグリッド（AWS コンソール的なウィジェット）。
    static func statGrid(_ title: String? = nil, columns: Int = 2, id: String = "stats", icon: String? = nil, @DebugStatBuilder stats: () -> [DebugStat]) -> DebugSection {
        DebugSection(id: id, title: title, icon: icon, layout: .card, content: .statGrid(columns: max(1, columns), stats: stats()))
    }

    /// 任意の利用側ビューを差し込む脱出口。
    static func custom<Content: View>(id: String, title: String? = nil, icon: String? = nil, layout: Layout = .card, @ViewBuilder content: () -> Content) -> DebugSection {
        DebugSection(id: id, title: title, icon: icon, layout: layout, content: .custom(AnyView(content())))
    }

    /// 手元データの掃除・再送。渡したストアに応じて操作が並ぶ（ライブ件数付き）:
    /// イベントログ消去 / 通信ログ消去 / 記録の全削除 / 未送信の再送・破棄 / すべて消去。
    static func maintenance(
        id: String = "maintenance",
        title: String = "メンテナンス",
        log: DebugLog? = nil,
        network: NetworkLogStore? = nil,
        outbox: (any OutboxDraining)? = nil
    ) -> DebugSection {
        DebugSection(id: id, title: title, icon: "trash", layout: .card,
                     content: .maintenance(log, network, outbox))
    }

    /// 任意画面への動線カード。デバッグメニューから開発ツール（カタログ等）へ飛ばす汎用口。
    static func screen<Destination: View>(
        id: String,
        title: String,
        icon: String = "arrow.up.right.square",
        tint: Color = .indigo,
        @ViewBuilder destination: () -> Destination
    ) -> DebugSection {
        DebugSection(id: id, title: title, icon: icon, layout: .navigationLink,
                     content: .screen(AnyView(destination()), tint: tint))
    }

    /// デザインシステムのコンポーネントカタログへの動線。
    static func designSystemCatalog(id: String = "design-catalog", title: String = "デザインカタログ") -> DebugSection {
        screen(id: id, title: title, icon: "paintpalette", tint: .pink) {
            DesignSystemCatalogView()
        }
    }
}

// MARK: - 賢い既定プレビュー（既存データから導出）

enum DebugPreview {
    static func timeline(_ log: DebugLog, category: String?) -> [DebugPreviewElement] {
        if category == nil {
            return [
                .status { status(of: log.events(matching: nil)) },
                .chips { topCategories(log.events) },
                .latest { latestLine(log.events(matching: nil)) },
            ]
        }
        return [
            .status { status(of: log.events(matching: category)) },
            .latest { latestLine(log.events(matching: category)) },
            .sparkline { rate(of: log.events(matching: category)) },
        ]
    }

    static func metrics(_ store: MetricsStore) -> [DebugPreviewElement] {
        [
            .stats {
                guard let report = store.report, let scope = report.scopes.first else { return [] }
                let selection = report.defaultSelection
                return scope.series.map { PreviewStat(label: $0.title, value: $0.format($0.total, selection)) }
            }
        ]
    }

    static func network(_ store: NetworkLogStore) -> [DebugPreviewElement] {
        [
            .status { networkStatus(store.logs) },
            .latest { networkLatest(store.logs) },
        ]
    }

    // MARK: 導出ヘルパー

    static func isError(_ event: DebugEvent) -> Bool {
        event.attributes["isError"] == "true"
            || event.name.localizedCaseInsensitiveContains("error")
            || event.name.localizedCaseInsensitiveContains("failed")
    }

    static func status(of events: [DebugEvent]) -> PreviewStatus {
        if events.isEmpty { return .neutral("空") }
        let errors = events.filter(isError).count
        return errors > 0 ? .warning(errors) : .ok
    }

    static func latestLine(_ events: [DebugEvent]) -> String? {
        guard let last = events.last else { return nil }
        let time = last.at.formatted(.relative(presentation: .named))
        return "\(last.summary) · \(time)"
    }

    static func rate(of events: [DebugEvent], window: TimeInterval = 60, buckets: Int = 14) -> [Double] {
        let now = Date()
        var bins = [Double](repeating: 0, count: buckets)
        let step = window / Double(buckets)
        for event in events {
            let dt = now.timeIntervalSince(event.at)
            guard dt >= 0, dt <= window else { continue }
            let index = min(buckets - 1, Int((window - dt) / step))
            bins[index] += 1
        }
        return bins
    }

    static func topCategories(_ events: [DebugEvent], limit: Int = 4) -> [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for event in events {
            if counts[event.category] == nil { order.append(event.category) }
            counts[event.category, default: 0] += 1
        }
        return order
            .sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
            .prefix(limit)
            .map { "\($0) \(counts[$0] ?? 0)" }
    }

    static func networkLatest(_ logs: [NetworkLog]) -> String? {
        guard let log = logs.first else { return nil }
        let status = log.errorMessage != nil ? "ERR" : (log.statusCode.map { "\($0)" } ?? "—")
        let time = log.startedAt.formatted(.relative(presentation: .named))
        return "\(log.method) \(log.path) → \(status) · \(time)"
    }

    static func networkStatus(_ logs: [NetworkLog]) -> PreviewStatus {
        if logs.isEmpty { return .neutral("空") }
        let errors = logs.filter(\.isFailure).count
        return errors > 0 ? .warning(errors) : .ok
    }
}

extension DebugLog {
    func events(matching category: String?) -> [DebugEvent] {
        category.map { events(in: $0) } ?? events
    }
}

// MARK: - 既定構成（console 未指定時の後方互換）

extension DebugConsole {
    /// controller に存在するストアから既定の構成を組む（旧 DebugPanel の並びを再現）。
    static func `default`(for controller: RecorderController) -> DebugConsole {
        var sections: [DebugSection] = []
        if controller.reachability != nil { sections.append(.connection()) }
        if let metrics = controller.metrics { sections.append(.metrics(metrics)) }
        if let log = controller.debugLog { sections.append(.timeline(log: log)) }
        if let network = controller.network { sections.append(.network(network)) }
        if !controller.items.isEmpty { sections.append(.items(controller.items)) }
        sections.append(.captures())
        return DebugConsole(sections: sections)
    }
}

// MARK: - Result builders

@resultBuilder
public enum DebugConsoleBuilder {
    public static func buildBlock(_ components: [DebugSection]...) -> [DebugSection] { components.flatMap { $0 } }
    public static func buildExpression(_ section: DebugSection) -> [DebugSection] { [section] }
    public static func buildExpression(_ sections: [DebugSection]) -> [DebugSection] { sections }
    public static func buildOptional(_ section: [DebugSection]?) -> [DebugSection] { section ?? [] }
    public static func buildEither(first: [DebugSection]) -> [DebugSection] { first }
    public static func buildEither(second: [DebugSection]) -> [DebugSection] { second }
    public static func buildArray(_ components: [[DebugSection]]) -> [DebugSection] { components.flatMap { $0 } }
}

@resultBuilder
public enum DebugStatBuilder {
    public static func buildBlock(_ components: [DebugStat]...) -> [DebugStat] { components.flatMap { $0 } }
    public static func buildExpression(_ stat: DebugStat) -> [DebugStat] { [stat] }
    public static func buildExpression(_ stats: [DebugStat]) -> [DebugStat] { stats }
    public static func buildOptional(_ stat: [DebugStat]?) -> [DebugStat] { stat ?? [] }
    public static func buildEither(first: [DebugStat]) -> [DebugStat] { first }
    public static func buildEither(second: [DebugStat]) -> [DebugStat] { second }
    public static func buildArray(_ components: [[DebugStat]]) -> [DebugStat] { components.flatMap { $0 } }
}
