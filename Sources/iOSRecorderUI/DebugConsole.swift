import SwiftUI
import DesignSystem
import iOSRecorder
import iOSRecorderNetwork

/// Declares which sections the debug panel shows, in what order, and how each one is laid out.
/// Holding that decision in one value keeps it out of the panel's views, where it would be scattered.
public struct DebugConsole {
    public var sections: [DebugSection]

    public init(sections: [DebugSection]) {
        self.sections = sections
    }

    public init(@DebugConsoleBuilder _ build: () -> [DebugSection]) {
        self.sections = build()
    }
}

/// One region of the panel: what it shows, how it is titled and laid out, and what it reveals before being tapped.
public struct DebugSection: Identifiable {
    public enum Layout: Sendable { case card, navigationLink, inline }

    public let id: String
    let title: String?
    let icon: String?
    let layout: Layout
    let content: Content
    /// Peek shown on the card before it is tapped; an empty array leaves only the header row.
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
        /// Clearing on-device data and retrying sends, each row carrying a live count.
        case maintenance(DebugLog?, NetworkLogStore?, (any OutboxDraining)?)
        /// Card that pushes to any screen the app supplies, such as a component catalog.
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

// MARK: - Preview vocabulary (what a card may reveal before it is tapped)

/// Health of a section at a glance, so a warning or an error is visible without opening the card.
public enum PreviewStatus: Sendable {
    case ok
    case warning(Int)
    case error(Int)
    case neutral(String)
}

/// A label and an already-formatted value; formatting stays with the app that owns the number.
public struct PreviewStat: Sendable {
    public let label: String
    public let value: String
    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// One thing a card may reveal, drawn by the package so every section looks the same.
/// Each case carries a closure, so reading an `@Observable` store inside it keeps the peek live.
public enum DebugPreviewElement {
    /// Health pill, hoisted into the header row; a warning or an error also tints the section icon.
    case status(@MainActor () -> PreviewStatus)
    /// One-line summary of the newest entry; `nil` draws an empty-state line instead.
    case latest(@MainActor () -> String?)
    /// Numbers worth reading without opening the card, such as metric totals.
    case stats(@MainActor () -> [PreviewStat])
    /// Recent activity as tiny bars; nothing is drawn when every value is zero.
    case sparkline(@MainActor () -> [Double])
    /// Category or tag chips; an empty array draws nothing.
    case chips(@MainActor () -> [String])
}

/// One tile in a stat grid; `value` and `caption` are closures, so every redraw re-reads the app's store.
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

// MARK: - Section factories

public extension DebugSection {
    /// Connection state of the Mac receiver; draws nothing unless the controller was given a reachability probe.
    static func connection(id: String = "connection") -> DebugSection {
        DebugSection(id: id, title: nil, icon: nil, layout: .card, content: .connection)
    }

    /// Way into the metrics dashboard, showing the series totals on the card by default.
    static func metrics(_ store: MetricsStore, id: String = "metrics", title: String = "メトリクス", icon: String = "chart.bar.xaxis", preview: [DebugPreviewElement]? = nil) -> DebugSection {
        DebugSection(id: id, title: title, icon: icon, layout: .navigationLink, content: .metrics(store),
                     preview: preview ?? DebugPreview.metrics(store))
    }

    /// Timeline of debug events, narrowed to a single `category` when one is given.
    /// Unless `preview` says otherwise it reveals health, the newest event and recent activity.
    static func timeline(_ title: String = "Debug ログ", log: DebugLog, category: String? = nil, id: String? = nil, icon: String = "waveform.path.ecg", preview: [DebugPreviewElement]? = nil) -> DebugSection {
        DebugSection(id: id ?? "timeline.\(category ?? "all")", title: title, icon: icon, layout: .navigationLink, content: .timeline(log, category: category),
                     preview: preview ?? DebugPreview.timeline(log, category: category))
    }

    /// Live network monitor, revealing the newest request and whether anything failed.
    static func network(_ store: NetworkLogStore, id: String = "network", title: String = "Network", icon: String = "network", preview: [DebugPreviewElement]? = nil) -> DebugSection {
        DebugSection(id: id, title: title, icon: icon, layout: .navigationLink, content: .network(store),
                     preview: preview ?? DebugPreview.network(store))
    }

    /// The stored captures, drawn inline rather than behind a card.
    static func captures(id: String = "captures", title: String = "記録") -> DebugSection {
        DebugSection(id: id, title: title, icon: nil, layout: .inline, content: .captures)
    }

    /// Actions, toggles and readouts supplied by the app, gathered into a single card.
    static func items(_ items: [DebugItem], id: String = "items") -> DebugSection {
        DebugSection(id: id, title: nil, icon: nil, layout: .card, content: .items(items))
    }

    /// Grid of live number tiles, for values worth reading at a glance.
    static func statGrid(_ title: String? = nil, columns: Int = 2, id: String = "stats", icon: String? = nil, @DebugStatBuilder stats: () -> [DebugStat]) -> DebugSection {
        DebugSection(id: id, title: title, icon: icon, layout: .card, content: .statGrid(columns: max(1, columns), stats: stats()))
    }

    /// Escape hatch for dropping in a view the app already has.
    static func custom<Content: View>(id: String, title: String? = nil, icon: String? = nil, layout: Layout = .card, @ViewBuilder content: () -> Content) -> DebugSection {
        DebugSection(id: id, title: title, icon: icon, layout: layout, content: .custom(AnyView(content())))
    }

    /// Clears on-device data and retries sends, with one row per store passed in, each showing a live count:
    /// clear the event log, clear the network log, delete every capture, retry or discard the spool, wipe everything.
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

    /// Card that pushes to any screen, for reaching a development tool from the debug menu.
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

    /// Way into the design system's component catalog, already titled and tinted.
    static func designSystemCatalog(id: String = "design-catalog", title: String = "デザインカタログ") -> DebugSection {
        screen(id: id, title: title, icon: "paintpalette", tint: .pink) {
            DesignSystemCatalogView()
        }
    }
}

// MARK: - Default previews, derived from data already on hand

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

    // MARK: Derivation helpers

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

// MARK: - Layout used when the app supplies no console

extension DebugConsole {
    /// Builds a layout from whichever stores the controller holds, in the panel's original order.
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
