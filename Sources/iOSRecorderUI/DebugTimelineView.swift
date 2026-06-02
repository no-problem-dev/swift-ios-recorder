import SwiftUI
import iOSRecorder

/// デバッグイベントのライブ・タイムライン。`DebugLog`(@Observable) を購読し、
/// 生成中もリアルタイムに流れる。カテゴリ（AI / UI / 通信 …）で絞り込める。
struct DebugTimelineView: View {
    let log: DebugLog
    @State private var selectedCategory: String?

    private var shown: [DebugEvent] {
        let events = selectedCategory.map { log.events(in: $0) } ?? log.events
        return events.reversed()   // 新しい順
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                categoryFilter
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
            .padding()
        }
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
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(active ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill), in: Capsule())
                .foregroundStyle(active ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}

private struct EventRow: View {
    let event: DebugEvent
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(event.category)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(categoryColor(event.category).opacity(0.18), in: Capsule())
                .foregroundStyle(categoryColor(event.category))
            VStack(alignment: .leading, spacing: 2) {
                Text(event.summary).font(.footnote).foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(event.name) · \(event.at.formatted(date: .omitted, time: .standard))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

func categoryColor(_ category: String) -> Color {
    switch category {
    case "agent": return .purple
    case "a2ui": return .blue
    case "network": return .teal
    case "metric": return .orange
    default: return .secondary
    }
}

/// デバッグイベント 1 件の詳細。全フィールド + attributes + payload を表示。
struct DebugEventDetailView: View {
    let event: DebugEvent

    var body: some View {
        List {
            Section {
                LabeledContent("カテゴリ", value: event.category)
                LabeledContent("イベント", value: event.name)
                LabeledContent("時刻", value: event.at.formatted(date: .abbreviated, time: .standard))
            }
            Section("サマリ") {
                Text(event.summary).font(.callout).textSelection(.enabled)
            }
            if !event.attributes.isEmpty {
                Section("属性") {
                    ForEach(event.attributes.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key).font(.caption).foregroundStyle(.secondary)
                            Text(value).font(.footnote.monospaced()).textSelection(.enabled)
                        }
                    }
                }
            }
            if let payload = event.payload, !payload.isEmpty {
                Section(event.attributes["payloadType"].map { "データ（\($0)）" } ?? "データ") {
                    if let structured = StructuredValueView.parse(payload) {
                        StructuredValueView(value: structured)
                    } else {
                        Text(String(decoding: payload, as: UTF8.self))
                            .font(.footnote.monospaced()).textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle(event.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
