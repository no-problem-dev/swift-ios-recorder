import SwiftUI
import Charts
import DesignSystem
import iOSRecorder

/// Visualizes a `MetricsReport` supplied by the app, along the axes and color indices that report declares.
/// It knows nothing about the domain: every number is turned into text by `MetricSeries.format`.
public struct MetricsDashboardView: View {
    let store: MetricsStore
    @State private var selection: [String: String] = [:]
    @State private var scopeIndex = 0
    @Environment(\.colorPalette) private var palette

    public init(store: MetricsStore) { self.store = store }

    public var body: some View {
        Group {
            if let report = store.report, !report.scopes.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        controls(report)
                        ForEach(scope(report).series) { series in
                            SeriesCard(series: series, selection: selection)
                        }
                    }
                    .padding(16)
                }
                .scrollContentBackground(.hidden)
                .background(palette.background)
                .onAppear { syncSelection(report) }
                .onChange(of: report.title) { _, _ in syncSelection(report) }
            } else {
                ContentUnavailableView("まだメトリクスがありません", systemImage: "chart.bar.xaxis")
                    .background(palette.background)
            }
        }
        .navigationTitle(store.report?.title ?? "メトリクス")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func syncSelection(_ report: MetricsReport) {
        var merged = report.defaultSelection
        for (key, value) in selection where merged[key] != nil { merged[key] = value }
        selection = merged
    }

    private func scope(_ report: MetricsReport) -> MetricsScope {
        report.scopes[min(scopeIndex, report.scopes.count - 1)]
    }

    @ViewBuilder private func controls(_ report: MetricsReport) -> some View {
        if !report.axes.isEmpty || report.scopes.count > 1 {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(report.axes) { axis in
                        axisControl(axis)
                    }
                    if report.scopes.count > 1 {
                        axisRow(label: "スコープ") {
                            ForEach(Array(report.scopes.enumerated()), id: \.offset) { index, s in
                                pill(s.label, active: scopeIndex == index) { scopeIndex = index }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func axisControl(_ axis: MetricAxis) -> some View {
        switch axis.style {
        case .segmented:
            Picker(axis.label, selection: binding(for: axis)) {
                ForEach(axis.options) { option in
                    Text(option.label).tag(option.id)
                }
            }
            .pickerStyle(.segmented)
        case .pills:
            axisRow(label: axis.label) {
                ForEach(axis.options) { option in
                    pill(option.label, active: selection[axis.id] == option.id) { selection[axis.id] = option.id }
                }
            }
        }
    }

    private func axisRow<Content: View>(label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label).typography(.labelMedium).foregroundStyle(palette.onSurfaceVariant)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { content() }
            }
        }
    }

    private func binding(for axis: MetricAxis) -> Binding<String> {
        Binding(
            get: { selection[axis.id] ?? axis.options.first?.id ?? "" },
            set: { selection[axis.id] = $0 }
        )
    }

    private func pill(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .typography(.labelMedium)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(active ? palette.primaryContainer : palette.surfaceVariant, in: Capsule())
                .foregroundStyle(active ? palette.onPrimaryContainer : palette.onSurfaceVariant)
        }
        .buttonStyle(.plain)
    }
}

/// Turns a color index into a fixed high-contrast color, chosen for telling series apart rather than
/// for matching the theme, and wrapping round for indices past the end.
func metricColor(_ index: Int) -> Color {
    let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo, .mint, .cyan]
    return palette[((index % palette.count) + palette.count) % palette.count]
}

private struct SeriesCard: View {
    let series: MetricSeries
    let selection: [String: String]
    @Environment(\.colorPalette) private var palette

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(series.title).typography(.titleSmall).foregroundStyle(palette.onSurface)
                    Spacer()
                    StatDisplay(value: series.format(series.total, selection), size: .small, alignment: .trailing)
                }

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
                .frame(height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(spacing: 8) {
                    ForEach(series.items) { item in
                        HStack(spacing: 8) {
                            Circle().fill(metricColor(item.colorIndex)).frame(width: 8, height: 8)
                            Text(item.label).typography(.bodySmall).foregroundStyle(palette.onSurfaceVariant)
                            Spacer()
                            if series.total > 0 {
                                Text("\((item.value / series.total).formatted(.percent.precision(.fractionLength(0))))")
                                    .typography(.labelSmall).monospacedDigit().foregroundStyle(palette.outline)
                            }
                            Text(series.format(item.value, selection))
                                .typography(.bodySmall).monospacedDigit().foregroundStyle(palette.onSurface)
                        }
                    }
                }
            }
        }
    }
}
