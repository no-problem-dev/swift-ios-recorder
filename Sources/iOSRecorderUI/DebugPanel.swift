import SwiftUI
import DesignSystem
import iOSRecorder
import iOSRecorderNetwork
import iOSRecorderBonjour

struct DebugPanel: View {
    @Bindable var controller: RecorderController
    @Environment(\.colorPalette) private var palette

    private var console: DebugConsole {
        controller.console ?? .default(for: controller)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(console.sections) { section in
                        DebugSectionView(section: section, controller: controller)
                    }
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Recorder")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { controller.isPresentingPanel = false }
                }
            }
            .task { await controller.refresh() }
        }
        .tint(palette.primary)
    }
}

/// Draws one section according to its content; the order and the layout come from the app's console.
private struct DebugSectionView: View {
    let section: DebugSection
    @Bindable var controller: RecorderController

    var body: some View {
        switch section.content {
        case .connection:
            if let reachability = controller.reachability {
                ConnectionRow(controller: controller, reachability: reachability)
            }
        case let .metrics(store):
            SectionSummaryCard(icon: section.icon ?? "chart.bar.xaxis", tint: .orange, title: store.report?.title ?? (section.title ?? "メトリクス"), preview: section.preview) {
                MetricsDashboardView(store: store)
            }
        case let .timeline(log, category):
            SectionSummaryCard(icon: section.icon ?? "waveform.path.ecg", tint: .purple, title: section.title ?? "Debug ログ", badge: log.events(matching: category).count, preview: section.preview) {
                DebugTimelineView(log: log, lockedCategory: category)
                    .navigationTitle(section.title ?? "Debug ログ")
            }
        case let .network(store):
            SectionSummaryCard(icon: section.icon ?? "network", tint: .teal, title: section.title ?? "Network", badge: store.logs.count, preview: section.preview) {
                NetworkListView(store: store)
            }
        case .captures:
            CapturesSection(controller: controller, title: section.title ?? "記録")
        case let .items(items):
            ItemsCard(items: items)
        case let .statGrid(columns, stats):
            StatGridCard(title: section.title, columns: columns, stats: stats)
        case let .custom(view):
            CustomCard(title: section.title, view: view)
        case let .maintenance(log, network, outbox):
            MaintenanceCard(title: section.title ?? "メンテナンス", controller: controller,
                            log: log, network: network, outbox: outbox)
        case let .screen(view, tint):
            SectionSummaryCard(icon: section.icon ?? "arrow.up.right.square", tint: tint,
                               title: section.title ?? section.id, preview: section.preview) {
                view
            }
        }
    }
}

// MARK: - Maintenance (clearing on-device data, retrying sends)

private struct MaintenanceCard: View {
    let title: String
    @Bindable var controller: RecorderController
    let log: DebugLog?
    let network: NetworkLogStore?
    let outbox: (any OutboxDraining)?
    @Environment(\.colorPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title)
            Card {
                VStack(spacing: 0) {
                    if let log {
                        row("イベントログを消去", icon: "waveform.path.ecg", count: log.events.count) {
                            log.clear()
                        }
                        divider
                    }
                    if let network {
                        row("通信ログを消去", icon: "network", count: network.logs.count) {
                            network.clear()
                        }
                        divider
                    }
                    row("端末内の記録を全削除", icon: "photo.stack", count: controller.summaries.count, destructive: true) {
                        await controller.removeAll()
                    }
                    if let outbox {
                        divider
                        row("未送信を再送", icon: "paperplane", count: controller.pendingCount) {
                            await outbox.drain()
                            await controller.refresh()
                        }
                        divider
                        row("未送信を破棄", icon: "xmark.bin", count: controller.pendingCount, destructive: true) {
                            await outbox.discardAll()
                            await controller.refresh()
                        }
                    }
                    divider
                    row("すべて消去", icon: "trash", destructive: true) {
                        log?.clear()
                        network?.clear()
                        await outbox?.discardAll()
                        await controller.removeAll()
                    }
                }
            }
        }
    }

    private var divider: some View {
        Divider().overlay(palette.outlineVariant)
    }

    /// One operation row, carrying a live count and disabling itself when there is nothing to act on.
    private func row(
        _ title: String,
        icon: String,
        count: Int? = nil,
        destructive: Bool = false,
        run: @escaping @MainActor () async -> Void
    ) -> some View {
        Button {
            Task { @MainActor in await run() }
        } label: {
            HStack {
                Label(title, systemImage: icon).typography(.bodyMedium)
                Spacer()
                if let count {
                    Text("\(count)").typography(.labelMedium).monospacedDigit()
                        .foregroundStyle(palette.onSurfaceVariant)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(destructive ? palette.error : palette.primary)
        .disabled(count == 0)
        .opacity(count == 0 ? 0.4 : 1)
        .padding(.vertical, 10)
    }
}

// MARK: - Mac connection state

private struct ConnectionRow: View {
    @Bindable var controller: RecorderController
    let reachability: ExportReachability
    @Environment(\.colorPalette) private var palette

    var body: some View {
        Card {
            HStack(spacing: 10) {
                Circle()
                    .fill(reachability.isReachable ? palette.success : palette.outline)
                    .frame(width: 9, height: 9)
                Text(reachability.isReachable ? "Mac 接続中" : "Mac 未接続")
                    .typography(.titleSmall)
                    .foregroundStyle(palette.onSurface)
                Spacer()
                if controller.pendingCount > 0 {
                    Label("\(controller.pendingCount) 件未送", systemImage: "arrow.up.circle.dotted")
                        .typography(.labelMedium)
                        .foregroundStyle(palette.warning)
                } else {
                    Text(reachability.isReachable ? "送信できます" : "ios-recorder serve を起動してください")
                        .typography(.labelMedium)
                        .foregroundStyle(palette.onSurfaceVariant)
                }
            }
        }
    }
}

// MARK: - Summary card (shared entry point for metrics / timeline / network)
// Draws a header (icon, title, count, status pill) plus a peek at the content before anyone taps it.

private struct SectionSummaryCard<Destination: View>: View {
    @Environment(\.colorPalette) private var palette
    let icon: String
    let tint: Color
    let title: String
    var badge: Int? = nil
    var preview: [DebugPreviewElement] = []
    @ViewBuilder let destination: () -> Destination

    private var status: PreviewStatus? {
        for case let .status(make) in preview { return make() }
        return nil
    }

    private var bodyElements: [DebugPreviewElement] {
        preview.filter { if case .status = $0 { return false } else { return true } }
    }

    private var isEmpty: Bool {
        if let badge { return badge == 0 }
        if case .neutral = status { return true }
        return false
    }

    private var accent: Color {
        switch status {
        case .warning: return palette.warning
        case .error: return palette.error
        default: return tint
        }
    }

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        IconBadge(systemName: icon, foregroundColor: accent, backgroundColor: accent.opacity(0.14))
                        Text(title).typography(.titleSmall).foregroundStyle(palette.onSurface)
                        Spacer()
                        if let badge {
                            Text("\(badge)").typography(.labelMedium).monospacedDigit().foregroundStyle(palette.onSurfaceVariant)
                        }
                        if let status { StatusPill(status: status) }
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(palette.outline)
                    }
                    if !bodyElements.isEmpty {
                        SectionPreviewView(elements: bodyElements)
                    }
                }
            }
            .opacity(isEmpty ? 0.55 : 1)
        }
        .buttonStyle(.plain)
    }
}

/// Stays quiet for ok and turns colored with a count for warning and error, so trouble is visible first.
private struct StatusPill: View {
    let status: PreviewStatus
    @Environment(\.colorPalette) private var palette

    var body: some View {
        switch status {
        case .ok:
            Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(palette.success)
        case let .warning(count):
            pill("\(count)", systemImage: "exclamationmark.triangle.fill", color: palette.warning)
        case let .error(count):
            pill("\(count)", systemImage: "xmark.octagon.fill", color: palette.error)
        case let .neutral(text):
            Text(text).typography(.labelSmall).foregroundStyle(palette.onSurfaceVariant)
        }
    }

    private func pill(_ text: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).font(.caption2)
            Text(text).typography(.labelSmall).monospacedDigit()
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.16), in: Capsule())
        .foregroundStyle(color)
    }
}

/// Stacks the preview elements; a `.status` element draws nothing here because the card hoists it into the header.
private struct SectionPreviewView: View {
    let elements: [DebugPreviewElement]
    @Environment(\.colorPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                render(element)
            }
        }
    }

    @ViewBuilder
    private func render(_ element: DebugPreviewElement) -> some View {
        switch element {
        case let .latest(make):
            LatestLine(text: make())
        case let .stats(make):
            PreviewStatsRow(stats: make())
        case let .sparkline(make):
            Sparkline(values: make())
        case let .chips(make):
            PreviewChips(labels: make())
        case .status:
            EmptyView()
        }
    }
}

private struct LatestLine: View {
    let text: String?
    @Environment(\.colorPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("最新").typography(.labelSmall).foregroundStyle(palette.onSurfaceVariant)
            Text(text ?? "まだイベントなし")
                .typography(.bodySmall)
                .foregroundStyle(text == nil ? palette.outline : palette.onSurface)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}

private struct PreviewStatsRow: View {
    let stats: [PreviewStat]
    @Environment(\.colorPalette) private var palette

    var body: some View {
        if stats.isEmpty {
            Text("データなし").typography(.bodySmall).foregroundStyle(palette.outline)
        } else {
            HStack(alignment: .top, spacing: 20) {
                ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.label).typography(.labelSmall).foregroundStyle(palette.onSurfaceVariant)
                        Text(stat.value).typography(.titleSmall).monospacedDigit().foregroundStyle(palette.onSurface)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct Sparkline: View {
    let values: [Double]
    @Environment(\.colorPalette) private var palette

    var body: some View {
        let maxValue = values.max() ?? 0
        if maxValue <= 0 {
            EmptyView()
        } else {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(value > 0 ? palette.primary : palette.surfaceVariant)
                        .frame(height: max(2, CGFloat(value / maxValue) * 18))
                }
            }
            .frame(height: 18)
        }
    }
}

private struct PreviewChips: View {
    let labels: [String]
    @Environment(\.colorPalette) private var palette

    var body: some View {
        if labels.isEmpty {
            EmptyView()
        } else {
            FlowLayout(spacing: 4) {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .typography(.labelSmall)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(palette.surfaceVariant, in: Capsule())
                        .foregroundStyle(palette.onSurfaceVariant)
                }
            }
        }
    }
}

// MARK: - Stat grid

private struct StatGridCard: View {
    let title: String?
    let columns: Int
    let stats: [DebugStat]
    @Environment(\.colorPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { SectionHeader(title) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                ForEach(stats) { stat in
                    StatTile(stat: stat)
                }
            }
        }
    }
}

private struct StatTile: View {
    let stat: DebugStat
    @Environment(\.colorPalette) private var palette

    var body: some View {
        Card(elevation: .level1) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let icon = stat.icon {
                        Image(systemName: icon).font(.caption).foregroundStyle(stat.tint ?? palette.primary)
                    }
                    Text(stat.title).typography(.labelMedium).foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
                }
                StatDisplay(value: stat.value(), size: .small, valueColor: stat.tint ?? palette.onSurface)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let caption = stat.caption {
                    Text(caption()).typography(.labelSmall).foregroundStyle(palette.onSurfaceVariant).lineLimit(1)
                }
            }
        }
    }
}

// MARK: - App-supplied view

private struct CustomCard: View {
    let title: String?
    let view: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { SectionHeader(title) }
            Card { view }
        }
    }
}

// MARK: - Debug items (action / toggle / info supplied by the app)

private struct ItemsCard: View {
    let items: [DebugItem]
    @Environment(\.colorPalette) private var palette

    var body: some View {
        Card {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(palette.outlineVariant) }
                    itemRow(item).padding(.vertical, 10)
                }
            }
        }
        .tint(palette.primary)
    }

    @ViewBuilder
    private func itemRow(_ item: DebugItem) -> some View {
        switch item.kind {
        case let .action(systemImage, run):
            Button {
                Task { @MainActor in await run() }
            } label: {
                Label(item.title, systemImage: systemImage)
                    .typography(.bodyMedium)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(palette.primary)
        case let .toggle(get, set):
            Toggle(isOn: Binding(get: { get() }, set: { set($0) })) {
                Text(item.title).typography(.bodyMedium).foregroundStyle(palette.onSurface)
            }
        case let .info(value):
            HStack {
                Text(item.title).typography(.bodyMedium).foregroundStyle(palette.onSurface)
                Spacer()
                Text(value()).typography(.bodyMedium).foregroundStyle(palette.onSurfaceVariant)
            }
        }
    }
}

// MARK: - Capture list

private struct CapturesSection: View {
    @Bindable var controller: RecorderController
    let title: String
    @Environment(\.colorPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SectionHeader(title)
                Text("\(controller.summaries.count)").typography(.labelMedium).monospacedDigit().foregroundStyle(palette.onSurfaceVariant)
                Spacer()
                if !controller.summaries.isEmpty {
                    Button(role: .destructive) {
                        Task { @MainActor in await controller.removeAll() }
                    } label: {
                        Label("全削除", systemImage: "trash").labelStyle(.titleAndIcon).typography(.labelMedium)
                    }
                    .tint(palette.error)
                }
            }

            if controller.summaries.isEmpty {
                ContentUnavailableView(
                    "まだ記録がありません",
                    systemImage: "ladybug",
                    description: Text("🐞 ボタンをタップ、またはシェイクで撮影")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(controller.summaries) { summary in
                        NavigationLink {
                            CaptureDetailView(summary: summary, controller: controller)
                        } label: {
                            CaptureRow(summary: summary, delivery: controller.deliveryState(for: summary.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    @Environment(\.colorPalette) private var palette
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .typography(.titleSmall)
            .foregroundStyle(palette.onSurface)
    }
}

/// One capture as a card: screen name, how long ago, delivery badge, and a chip per artifact kind.
struct CaptureRow: View {
    let summary: RecordSummary
    var delivery: DeliveryState = .notExported
    @Environment(\.colorPalette) private var palette

    var body: some View {
        Card(elevation: .level1) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(systemName: "photo.fill", foregroundColor: .indigo, backgroundColor: Color.indigo.opacity(0.14))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(summary.metadata.screenName ?? "（無題）")
                            .typography(.titleSmall)
                            .foregroundStyle(palette.onSurface)
                        Spacer(minLength: 4)
                        DeliveryBadge(state: delivery)
                    }
                    Text(summary.recordedAt.formatted(.relative(presentation: .named)))
                        .typography(.labelMedium)
                        .foregroundStyle(palette.onSurfaceVariant)
                    FlowLayout(spacing: 4) {
                        ForEach(summary.artifactKinds, id: \.rawValue) { kind in
                            KindChip(kind: kind)
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(palette.outline)
            }
        }
    }
}

/// Places children left to right and wraps to a new row once the proposed width runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, rowHeight: CGFloat = 0, totalHeight: CGFloat = 0, usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                totalHeight += rowHeight + spacing
                usedWidth = max(usedWidth, x - spacing)
                x = 0; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        usedWidth = max(usedWidth, x - spacing)
        return CGSize(width: min(usedWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Icon for the delivery state; a capture from a session with no exporter shows nothing at all.
struct DeliveryBadge: View {
    let state: DeliveryState
    @Environment(\.colorPalette) private var palette

    var body: some View {
        switch state {
        case .delivered:
            Image(systemName: "checkmark.icloud.fill").font(.caption).foregroundStyle(palette.success)
        case .pending:
            Image(systemName: "arrow.up.circle.dotted").font(.caption).foregroundStyle(palette.warning)
        case .notExported:
            EmptyView()
        }
    }
}

struct KindChip: View {
    let kind: ArtifactKind

    var body: some View {
        Chip(label)
            .chipStyle(.filled)
            .chipSize(.small)
            .foregroundColor(color)
    }

    private var label: String {
        if kind == .screenshot { return "画面" }
        if kind == .state { return "状態" }
        if kind == .log { return "ログ" }
        switch kind.rawValue {
        case "network": return "通信"
        case "debug_timeline": return "タイムライン"
        case "metrics": return "メトリクス"
        default: return kind.rawValue
        }
    }

    private var color: Color {
        if kind == .screenshot { return .blue }
        if kind == .state { return .green }
        if kind == .log { return .gray }
        switch kind.rawValue {
        case "network": return .teal
        case "debug_timeline": return .purple
        case "metrics": return .orange
        default: return .secondary
        }
    }
}
