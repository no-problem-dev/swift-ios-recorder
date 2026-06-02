import Foundation
import Observation

/// メトリクスの単位。表示整形と相互作用（通貨換算・倍率）を駆動する。
public enum MetricUnit: Sendable, Codable, Hashable {
    case tokens          // 個数（トークン）
    case currencyUSD     // 金額。基準 USD で保持し、表示時に通貨換算する
    case count
    case seconds
    case custom(String)
}

/// チャート 1 本の中の 1 項目（内訳の 1 要素）。`colorIndex` でパレット色を割り当てる。
public struct MetricItem: Sendable, Codable, Identifiable, Hashable {
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

/// 1 つのチャート（系列）。同じ単位の項目の集合。
public struct MetricSeries: Sendable, Codable, Identifiable, Hashable {
    public var id: String { title }
    public let title: String
    public let unit: MetricUnit
    public let items: [MetricItem]

    public init(title: String, unit: MetricUnit, items: [MetricItem]) {
        self.title = title
        self.unit = unit
        self.items = items
    }

    public var total: Double { items.reduce(0) { $0 + $1.value } }
}

/// 表示通貨の選択肢。基準は USD（rateFromUSD = 1）。
public struct CurrencyOption: Sendable, Codable, Hashable, Identifiable {
    public var id: String { code }
    public let code: String
    public let symbol: String
    public let rateFromUSD: Double
    public let fractionDigits: Int

    public init(code: String, symbol: String, rateFromUSD: Double, fractionDigits: Int) {
        self.code = code
        self.symbol = symbol
        self.rateFromUSD = rateFromUSD
        self.fractionDigits = fractionDigits
    }

    public static let usd = CurrencyOption(code: "USD", symbol: "$", rateFromUSD: 1, fractionDigits: 4)
    public static func jpy(rate: Double) -> CurrencyOption {
        CurrencyOption(code: "JPY", symbol: "¥", rateFromUSD: rate, fractionDigits: 1)
    }
}

/// 系列の集合に名前を付けた単位（合計 / ターン別 など、利用側が定義する任意の切り口）。
public struct MetricsScope: Sendable, Codable, Hashable, Identifiable {
    public var id: String { label }
    public let label: String
    public let series: [MetricSeries]

    public init(label: String, series: [MetricSeries]) {
        self.label = label
        self.series = series
    }
}

/// ダッシュボード 1 画面分。利用側（ドメイン）が組み立てて差し込む。
/// `scopes` を複数渡すと、ダッシュボードでスコープ（合計／各ターン等）を切り替えられる。
public struct MetricsReport: Sendable, Codable, Hashable {
    public let title: String
    public let scopes: [MetricsScope]
    public let currencies: [CurrencyOption]
    public let multipliers: [Int]

    public init(
        title: String,
        scopes: [MetricsScope],
        currencies: [CurrencyOption] = [.usd],
        multipliers: [Int] = [1, 10, 100, 1000]
    ) {
        self.title = title
        self.scopes = scopes
        self.currencies = currencies
        self.multipliers = multipliers
    }

    /// 単一スコープ（合計のみ）の簡易イニシャライザ。
    public init(
        title: String,
        series: [MetricSeries],
        currencies: [CurrencyOption] = [.usd],
        multipliers: [Int] = [1, 10, 100, 1000]
    ) {
        self.init(title: title, scopes: [MetricsScope(label: "合計", series: series)],
                  currencies: currencies, multipliers: multipliers)
    }
}

/// ライブに差し替えられるメトリクスの置き場（@Observable）。利用側が `report` を更新するとビューが追従する。
@MainActor
@Observable
public final class MetricsStore {
    public var report: MetricsReport?
    public init(report: MetricsReport? = nil) { self.report = report }
    public func update(_ report: MetricsReport) { self.report = report }
}
