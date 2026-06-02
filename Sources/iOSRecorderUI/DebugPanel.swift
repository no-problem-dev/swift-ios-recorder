import SwiftUI
import iOSRecorder
import iOSRecorderNetwork
import iOSRecorderBonjour

struct DebugPanel: View {
    @Bindable var controller: RecorderController

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let reachability = controller.reachability { connectionRow(reachability) }
                    if let metrics = controller.metrics { metricsCard(metrics) }
                    if let debugLog = controller.debugLog { debugLogCard(debugLog) }
                    if let network = controller.network { networkCard(network) }
                    if !controller.items.isEmpty { debugItemsCard }
                    capturesSection
                }
                .padding()
            }
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
    }

    // MARK: - Mac 接続状態

    private func connectionRow(_ reachability: ExportReachability) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(reachability.isReachable ? .green : .secondary)
                .frame(width: 9, height: 9)
            Text(reachability.isReachable ? "Mac 接続中" : "Mac 未接続")
                .font(.subheadline.weight(.medium))
            Spacer()
            if controller.pendingCount > 0 {
                Label("\(controller.pendingCount) 件未送", systemImage: "arrow.up.circle.dotted")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            } else {
                Text(reachability.isReachable ? "送信できます" : "ios-recorder serve を起動してください")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - メトリクス・ダッシュボード

    private func metricsCard(_ metrics: MetricsStore) -> some View {
        NavigationLink {
            MetricsDashboardView(store: metrics)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .frame(width: 38, height: 38)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                Text(metrics.report?.title ?? "メトリクス").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Debug タイムライン（ライブ）

    private func debugLogCard(_ debugLog: DebugLog) -> some View {
        NavigationLink {
            DebugTimelineView(log: debugLog)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.title3)
                    .foregroundStyle(.purple)
                    .frame(width: 38, height: 38)
                    .background(.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                Text("Debug ログ").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Spacer()
                Text("\(debugLog.events.count)").font(.caption.bold()).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    // MARK: - ネットワーク（独立ライブモニタ）

    private func networkCard(_ network: NetworkLogStore) -> some View {
        NavigationLink {
            NetworkListView(store: network)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.title3)
                    .foregroundStyle(.teal)
                    .frame(width: 38, height: 38)
                    .background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                Text("Network").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Spacer()
                Text("\(network.logs.count)").font(.caption.bold()).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    // MARK: - デバッグ項目（プラグイン）

    private var debugItemsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(controller.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider() }
                itemRow(item).padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func itemRow(_ item: DebugItem) -> some View {
        switch item.kind {
        case let .action(systemImage, run):
            Button {
                Task { @MainActor in await run() }
            } label: {
                Label(item.title, systemImage: systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case let .toggle(get, set):
            Toggle(isOn: Binding(get: { get() }, set: { set($0) })) {
                Text(item.title)
            }
        case let .info(value):
            HStack {
                Text(item.title)
                Spacer()
                Text(value()).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 記録一覧

    private var capturesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("記録")
                    .font(.headline)
                Text("\(controller.summaries.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if !controller.summaries.isEmpty {
                    Button(role: .destructive) {
                        Task { @MainActor in await controller.removeAll() }
                    } label: {
                        Label("全削除", systemImage: "trash").labelStyle(.titleAndIcon).font(.caption)
                    }
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

/// 記録 1 件のカード表現（純正 List 行ではなく独自カード）。
struct CaptureRow: View {
    let summary: RecordSummary
    var delivery: DeliveryState = .notExported

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "photo.fill")
                .font(.title3)
                .foregroundStyle(.indigo)
                .frame(width: 38, height: 38)
                .background(.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(summary.metadata.screenName ?? "（無題）")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    DeliveryBadge(state: delivery)
                }
                Text(summary.recordedAt.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 4) {
                    ForEach(summary.artifactKinds, id: \.rawValue) { kind in
                        KindChip(kind: kind)
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// 子を行内に並べ、幅を超えたら折り返す簡易フローレイアウト（チップの表示崩れ対策）。
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

/// 配送状態のアイコン。delivered=緑チェック、pending=橙、未送出=非表示。
struct DeliveryBadge: View {
    let state: DeliveryState

    var body: some View {
        switch state {
        case .delivered:
            Image(systemName: "checkmark.icloud.fill")
                .font(.caption).foregroundStyle(.green)
        case .pending:
            Image(systemName: "arrow.up.circle.dotted")
                .font(.caption).foregroundStyle(.orange)
        case .notExported:
            EmptyView()
        }
    }
}

struct KindChip: View {
    let kind: ArtifactKind

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
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
