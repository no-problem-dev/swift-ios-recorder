import SwiftUI
import Charts
import iOSRecorder

/// 任意のメトリクス（利用側が差し込む `MetricsReport`）を、通貨切替・倍率・色分けで
/// リッチに可視化する汎用ダッシュボード。ドメイン非依存（ロジックはパッケージ責務）。
public struct MetricsDashboardView: View {
    let store: MetricsStore
    @State private var currencyIndex = 0
    @State private var multiplier = 1
    @State private var scopeIndex = 0

    public init(store: MetricsStore) { self.store = store }

    public var body: some View {
        Group {
            if let report = store.report, !report.scopes.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        controls(report)
                        ForEach(scope(report).series) { series in
                            SeriesCard(series: series, currency: currency(report), multiplier: multiplier)
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("まだメトリクスがありません", systemImage: "chart.bar.xaxis")
            }
        }
        .navigationTitle(store.report?.title ?? "メトリクス")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func currency(_ report: MetricsReport) -> CurrencyOption {
        let options = report.currencies.isEmpty ? [.usd] : report.currencies
        return options[min(currencyIndex, options.count - 1)]
    }

    private func scope(_ report: MetricsReport) -> MetricsScope {
        report.scopes[min(scopeIndex, report.scopes.count - 1)]
    }

    @ViewBuilder private func controls(_ report: MetricsReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if report.currencies.count > 1 {
                Picker("通貨", selection: $currencyIndex) {
                    ForEach(Array(report.currencies.enumerated()), id: \.offset) { index, option in
                        Text("\(option.symbol) \(option.code)").tag(index)
                    }
                }
                .pickerStyle(.segmented)
            }
            HStack(spacing: 8) {
                Text("倍率").font(.caption).foregroundStyle(.secondary)
                ForEach(report.multipliers, id: \.self) { m in
                    Button {
                        multiplier = m
                    } label: {
                        Text("×\(m)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(multiplier == m ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(multiplier == m ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            if report.scopes.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(report.scopes.enumerated()), id: \.offset) { index, s in
                            Button { scopeIndex = index } label: {
                                Text(s.label)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(scopeIndex == index ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill), in: Capsule())
                                    .foregroundStyle(scopeIndex == index ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

/// パレット（color index → 色）。
func metricColor(_ index: Int) -> Color {
    let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo, .mint, .cyan]
    return palette[((index % palette.count) + palette.count) % palette.count]
}

/// メトリクス値の表示整形（単位・通貨・倍率を反映）。
func formatMetric(_ value: Double, unit: MetricUnit, currency: CurrencyOption, multiplier: Int) -> String {
    let m = Double(multiplier)
    switch unit {
    case .currencyUSD:
        return currency.symbol + adaptiveNumber(value * currency.rateFromUSD * m)
    case .tokens, .count:
        return (value * m).formatted(.number.precision(.fractionLength(0)))
    case .seconds:
        return adaptiveNumber(value * m) + "s"
    case .custom(let suffix):
        return adaptiveNumber(value * m) + suffix
    }
}

/// 適応的な数値表示:
/// - |値| < 1（小数）→ 有効数字 2 桁（0.42 / 0.0012 / 0.050）
/// - |値| ≥ 1 → 整数部はそのまま、小数は最大 2 桁（3.56 / 160 / 80,000 / 1,234.57）
func adaptiveNumber(_ value: Double) -> String {
    let magnitude = abs(value)
    if magnitude == 0 { return "0" }
    if magnitude >= 1 {
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }
    return value.formatted(.number.precision(.significantDigits(2)))
}

private struct SeriesCard: View {
    let series: MetricSeries
    let currency: CurrencyOption
    let multiplier: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(series.title).font(.headline)
                Spacer()
                Text(formatMetric(series.total, unit: series.unit, currency: currency, multiplier: multiplier))
                    .font(.headline.monospacedDigit()).foregroundStyle(.primary)
            }

            // 1 本の横棒に、各項目の割合を色で積み上げて表現（normalized stacking）。
            Chart(series.items) { item in
                BarMark(
                    x: .value("割合", item.value),
                    y: .value("系列", series.title),
                    stacking: .normalized
                )
                .foregroundStyle(metricColor(item.colorIndex))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // 色分けの内訳リスト（実数値＋割合）
            ForEach(series.items) { item in
                HStack(spacing: 8) {
                    Circle().fill(metricColor(item.colorIndex)).frame(width: 8, height: 8)
                    Text(item.label).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if series.total > 0 {
                        Text("\((item.value / series.total).formatted(.percent.precision(.fractionLength(0))))")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                    Text(formatMetric(item.value, unit: series.unit, currency: currency, multiplier: multiplier))
                        .font(.caption.monospacedDigit()).foregroundStyle(.primary)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
