import Foundation
import Observation

/// One slice of a chart, with `colorIndex` choosing its color from the palette.
///
/// Identity is the label, so two slices sharing a label inside one series collide in the view.
public struct MetricItem: Sendable, Identifiable, Hashable {
    public var id: String { label }
    public let label: String
    public let value: Double
    public let colorIndex: Int

    public init(label: String, value: Double, colorIndex: Int = 0) {
        self.label = label
        self.value = value
        self.colorIndex = colorIndex
    }
}

/// One chart, whose values stay raw numbers until `format` renders them.
///
/// `format` receives a value and the current axis selection (keyed by axis id) and returns the display string,
/// so currency, units, and multipliers live entirely in the app. Identity is the title.
public struct MetricSeries: Sendable, Identifiable {
    public var id: String { title }
    public let title: String
    public let items: [MetricItem]
    public let format: @Sendable (_ value: Double, _ selection: [String: String]) -> String

    public init(
        title: String,
        items: [MetricItem],
        format: @escaping @Sendable (_ value: Double, _ selection: [String: String]) -> String
    ) {
        self.title = title
        self.items = items
        self.format = format
    }

    public var total: Double { items.reduce(0) { $0 + $1.value } }
}

/// One choice on an axis; its `id` is what reaches every series' `format` closure once selected.
public struct MetricAxisOption: Sendable, Identifiable, Hashable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// One control on the dashboard — currency, multiplier, granularity, whatever the app decides to offer.
///
/// It carries no meaning of its own, only a named set of options; what a selection does is entirely up to each
/// series' `format`.
public struct MetricAxis: Sendable, Identifiable {
    public enum Style: Sendable { case segmented, pills }

    public let id: String
    public let label: String
    public let options: [MetricAxisOption]
    public let style: Style

    public init(id: String, label: String, options: [MetricAxisOption], style: Style = .pills) {
        self.id = id
        self.label = label
        self.options = options
        self.style = style
    }
}

/// A named group of series the dashboard can switch between, such as a total against one group per turn.
///
/// Identity is the label, so two scopes cannot share one.
public struct MetricsScope: Sendable, Identifiable {
    public var id: String { label }
    public let label: String
    public let series: [MetricSeries]

    public init(label: String, series: [MetricSeries]) {
        self.label = label
        self.series = series
    }
}

/// One dashboard screen, assembled by the app and handed to the view.
///
/// The scope switcher only appears when there is more than one scope, and the whole control strip disappears
/// when there are no axes either.
public struct MetricsReport: Sendable {
    public let title: String
    public let scopes: [MetricsScope]
    public let axes: [MetricAxis]

    public init(title: String, scopes: [MetricsScope], axes: [MetricAxis] = []) {
        self.title = title
        self.scopes = scopes
        self.axes = axes
    }

    /// Builds a report around a single scope, which the dashboard renders with no scope switcher.
    public init(title: String, series: [MetricSeries], axes: [MetricAxis] = []) {
        self.init(title: title, scopes: [MetricsScope(label: "Total", series: series)], axes: axes)
    }

    /// The first option of every axis, keyed by axis id — what the dashboard starts on before anyone taps.
    public var defaultSelection: [String: String] {
        var selection: [String: String] = [:]
        for axis in axes {
            if let first = axis.options.first { selection[axis.id] = first.id }
        }
        return selection
    }
}

/// Ready-made number formatting for building a series' `format` closure, with no assumptions about the domain.
public enum MetricFormat {
    /// Picks the precision from the magnitude, so a rate and a token count can share one axis:
    /// - |value| < 1 → two significant digits (0.42 / 0.0012 / 0.050)
    /// - |value| ≥ 1 → integer part in full, at most two fraction digits (3.56 / 160 / 80,000 / 1,234.57)
    public static func number(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude == 0 { return "0" }
        if magnitude >= 1 {
            return value.formatted(.number.precision(.fractionLength(0...2)))
        }
        return value.formatted(.number.precision(.significantDigits(2)))
    }

    /// Rounds away the fraction entirely, for counts and token totals.
    public static func integer(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// Prefixes whichever symbol the app passes; no locale currency rules are applied, so placement stays fixed.
    public static func currency(symbol: String, fractionDigits: Int, _ value: Double) -> String {
        symbol + value.formatted(.number.precision(.fractionLength(0...max(0, fractionDigits))))
    }

    /// Adaptive precision with an `s` suffix; sub-second values keep two significant digits.
    public static func seconds(_ value: Double) -> String { number(value) + "s" }
}

/// Holds the report the dashboard renders; assigning a new one updates the view in place.
///
/// Bound to the main actor, so a background task computing metrics has to hop before publishing them.
@MainActor
@Observable
public final class MetricsStore {
    public var report: MetricsReport?
    public init(report: MetricsReport? = nil) { self.report = report }
    public func update(_ report: MetricsReport) { self.report = report }
}
