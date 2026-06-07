import SwiftUI
import DesignSystem
import iOSRecorder

/// デバッグイベントのライブ・タイムライン。`DebugLog`(@Observable) を購読し、
/// 生成中もリアルタイムに流れる。カテゴリ（AI / UI / 通信 …）で絞り込める。
struct DebugTimelineView: View {
    let log: DebugLog
    /// 指定するとそのカテゴリに固定し、フィルタバーを出さない（セクションで関心を分離する用途）。
    var lockedCategory: String? = nil
    @State private var selectedCategory: String?
    @Environment(\.colorPalette) private var palette

    private var shown: [DebugEvent] {
        let category = lockedCategory ?? selectedCategory
        let events = category.map { log.events(in: $0) } ?? log.events
        return events.reversed()   // 新しい順
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if lockedCategory == nil { categoryFilter }
                if shown.isEmpty {
                    ContentUnavailableView("まだイベントがありません", systemImage: "waveform.path.ecg")
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    ForEach(shown) { event in
                        NavigationLink {
                            DebugEventDetailView(event: event)
                        } label: {
                            EventRow(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle("Debug ログ")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(title: "すべて", active: selectedCategory == nil) { selectedCategory = nil }
                ForEach(log.categories, id: \.self) { category in
                    FilterChip(title: category, active: selectedCategory == category) { selectedCategory = category }
                }
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    let active: Bool
    let action: () -> Void
    @Environment(\.colorPalette) private var palette

    var body: some View {
        Button(action: action) {
            Text(title)
                .typography(.labelMedium)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(active ? palette.primaryContainer : palette.surfaceVariant, in: Capsule())
                .foregroundStyle(active ? palette.onPrimaryContainer : palette.onSurfaceVariant)
        }
        .buttonStyle(.plain)
    }
}

private struct EventRow: View {
    let event: DebugEvent
    @Environment(\.colorPalette) private var palette

    var body: some View {
        Card(elevation: .level1, padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)) {
            HStack(alignment: .top, spacing: 10) {
                Text(event.category)
                    .typography(.labelSmall)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(categoryColor(event.category).opacity(0.18), in: Capsule())
                    .foregroundStyle(categoryColor(event.category))
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.summary).typography(.bodySmall).foregroundStyle(palette.onSurface)
                        .lineLimit(2)
                    Text("\(event.name) · \(event.at.formatted(date: .omitted, time: .standard))")
                        .typography(.labelSmall).foregroundStyle(palette.outline)
                }
                Spacer(minLength: 4)
                if let payload = event.payload {
                    Label(CompactDisplay.formatBytes(payload.count), systemImage: "doc.text")
                        .font(.caption2).foregroundStyle(palette.primary)
                        .labelStyle(.titleAndIcon)
                }
                Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(palette.outline)
            }
        }
    }
}

/// カテゴリ名から安定した色を導出する。ドメイン（agent / a2ui 等）をパッケージは知らないので、
/// 文字列を決定的にハッシュしてパレットに割り当てる（同じカテゴリは毎回同じ色）。
func categoryColor(_ category: String) -> Color {
    var hash: UInt64 = 5381
    for byte in category.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
    return metricColor(Int(hash % 10))
}

/// デバッグイベント 1 件の詳細。全フィールド + attributes + payload を表示。
struct DebugEventDetailView: View {
    let event: DebugEvent
    @Environment(\.colorPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        DetailRow(label: "カテゴリ", value: event.category)
                        DetailRow(label: "イベント", value: event.name)
                        DetailRow(label: "時刻", value: event.at.formatted(date: .abbreviated, time: .standard))
                    }
                }

                labeled("サマリ") {
                    Text(event.summary).typography(.bodyMedium).foregroundStyle(palette.onSurface).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !event.attributes.isEmpty {
                    labeled("属性") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(event.attributes.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(key).typography(.labelSmall).foregroundStyle(palette.onSurfaceVariant)
                                    Text(value).font(.footnote.monospaced()).foregroundStyle(palette.onSurface)
                                        .lineLimit(4).textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                if let payload = event.payload, !payload.isEmpty {
                    labeled(payloadTitle) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let note = truncationNote {
                                Label(note, systemImage: "scissors")
                                    .typography(.labelSmall).foregroundStyle(palette.onSurfaceVariant)
                            }
                            if let structured = StructuredValueView.parse(payload) {
                                StructuredValueView(value: structured)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ExpandableText(text: String(decoding: payload, as: UTF8.self))
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(event.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var payloadTitle: String {
        let type = event.attributes["payloadType"].map { "（\($0)）" } ?? ""
        let size = event.payload.map { " · \(CompactDisplay.formatBytes($0.count))" } ?? ""
        return "データ\(type)\(size)"
    }

    /// capture 時に payload が truncate されていたら、その事実を表示する。
    private var truncationNote: String? {
        guard event.attributes["payloadTruncated"] == "true",
              let original = event.attributes["payloadOriginalBytes"].flatMap(Int.init) else { return nil }
        return "撮影時に \(CompactDisplay.formatBytes(original)) から切り詰め済み"
    }

    @ViewBuilder
    private func labeled(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title)
            Card { content() }
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    @Environment(\.colorPalette) private var palette

    var body: some View {
        HStack {
            Text(label).typography(.bodyMedium).foregroundStyle(palette.onSurfaceVariant)
            Spacer()
            Text(value).typography(.bodyMedium).foregroundStyle(palette.onSurface).textSelection(.enabled)
        }
    }
}
