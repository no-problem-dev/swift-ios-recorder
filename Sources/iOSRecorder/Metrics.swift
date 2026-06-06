import Foundation
import Observation

/// チャート 1 本の中の 1 項目（内訳の 1 要素）。`colorIndex` でパレット色を割り当てる。
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

/// 1 つのチャート（系列）。整形は利用側が `format` で注入する。
/// `format` は生値と現在の軸選択（`[軸ID: 選択肢ID]`）を受け取り、表示文字列を返す。
/// 通貨・単位・倍率といったドメインの解釈はすべてこのクロージャに閉じる（パッケージは知らない）。
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

/// ダッシュボード上の切り替え可能な表示軸の 1 選択肢。
public struct MetricAxisOption: Sendable, Identifiable, Hashable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// ダッシュボードに 1 つのコントロールとして並ぶ表示軸（通貨・倍率・粒度…利用側が任意に定義）。
/// 値の解釈は持たず「名前付きの選択肢集合」だけを表す。各系列の `format` が選択結果を読む。
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

/// 系列の集合に名前を付けた単位（合計 / ターン別 など、利用側が定義する任意の切り口）。
public struct MetricsScope: Sendable, Identifiable {
    public var id: String { label }
    public let label: String
    public let series: [MetricSeries]

    public init(label: String, series: [MetricSeries]) {
        self.label = label
        self.series = series
    }
}

/// ダッシュボード 1 画面分。利用側（ドメイン）が組み立てて差し込む。
/// `scopes` でスコープ（合計／各ターン等）を、`axes` で表示軸（通貨／倍率等）を切り替えられる。
public struct MetricsReport: Sendable {
    public let title: String
    public let scopes: [MetricsScope]
    public let axes: [MetricAxis]

    public init(title: String, scopes: [MetricsScope], axes: [MetricAxis] = []) {
        self.title = title
        self.scopes = scopes
        self.axes = axes
    }

    /// 単一スコープ（合計のみ）の簡易イニシャライザ。
    public init(title: String, series: [MetricSeries], axes: [MetricAxis] = []) {
        self.init(title: title, scopes: [MetricsScope(label: "合計", series: series)], axes: axes)
    }

    /// 各軸の既定選択（先頭の選択肢）をまとめた `[軸ID: 選択肢ID]`。
    public var defaultSelection: [String: String] {
        var selection: [String: String] = [:]
        for axis in axes {
            if let first = axis.options.first { selection[axis.id] = first.id }
        }
        return selection
    }
}

/// 表示整形のためのドメイン非依存ヘルパー。利用側が `MetricSeries.format` を組むときに使える。
public enum MetricFormat {
    /// 適応的な数値表示:
    /// - |値| < 1（小数）→ 有効数字 2 桁（0.42 / 0.0012 / 0.050）
    /// - |値| ≥ 1 → 整数部はそのまま、小数は最大 2 桁（3.56 / 160 / 80,000 / 1,234.57）
    public static func number(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude == 0 { return "0" }
        if magnitude >= 1 {
            return value.formatted(.number.precision(.fractionLength(0...2)))
        }
        return value.formatted(.number.precision(.significantDigits(2)))
    }

    /// 整数表示（トークン・件数など）。
    public static func integer(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// 通貨表示（記号＋小数桁を指定）。`symbol` と桁は利用側が定義する。
    public static func currency(symbol: String, fractionDigits: Int, _ value: Double) -> String {
        symbol + value.formatted(.number.precision(.fractionLength(0...max(0, fractionDigits))))
    }

    /// 秒表示。
    public static func seconds(_ value: Double) -> String { number(value) + "s" }
}

/// ライブに差し替えられるメトリクスの置き場（@Observable）。利用側が `report` を更新するとビューが追従する。
@MainActor
@Observable
public final class MetricsStore {
    public var report: MetricsReport?
    public init(report: MetricsReport? = nil) { self.report = report }
    public func update(_ report: MetricsReport) { self.report = report }
}
