import SwiftUI
import DesignSystem
import StructuredDataCore
import JSONParsing

/// 任意の構造データ（`StructuredValue`）を再帰的に折り畳み表示する汎用ビュー。
/// 既定はコンパクト: トップレベルだけ展開し、深い階層は折り畳み、大量の子はバッチで開示、
/// 長い文字列リーフはプレビュー + 全文展開。巨大 payload でも一覧性と性能を守る。
struct StructuredValueView: View {
    let value: StructuredValue
    var depth: Int = 0
    @State private var shownChildren = CompactDisplay.initialChildren
    @Environment(\.colorPalette) private var palette

    var body: some View {
        switch value {
        case .object(let object):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(object.entries.prefix(shownChildren).enumerated()), id: \.offset) { _, entry in
                    StructuredNodeRow(key: entry.key, value: entry.value, depth: depth)
                }
                revealButton(total: object.count)
            }
        case .array(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.prefix(shownChildren).enumerated()), id: \.offset) { index, item in
                    StructuredNodeRow(key: "[\(index)]", value: item, depth: depth)
                }
                revealButton(total: items.count)
            }
        default:
            StructuredLeaf(key: nil, value: value)
        }
    }

    @ViewBuilder
    private func revealButton(total: Int) -> some View {
        if total > shownChildren {
            Button {
                shownChildren += CompactDisplay.childrenStep
            } label: {
                Label("他 \(total - shownChildren) 件を表示", systemImage: "ellipsis.circle")
                    .typography(.labelMedium)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.primary)
            .padding(.top, 2)
        }
    }

    /// JSON データをパースして表示。JSON でなければ nil（呼び出し側がテキスト表示にフォールバック）。
    static func parse(_ data: Data) -> StructuredValue? {
        try? JSONParser().parse(data)
    }
}

/// オブジェクト/配列なら折り畳み、葉なら 1 行で表示するノード。
private struct StructuredNodeRow: View {
    let key: String
    let value: StructuredValue
    let depth: Int
    @State private var expanded: Bool
    @Environment(\.colorPalette) private var palette

    init(key: String, value: StructuredValue, depth: Int) {
        self.key = key
        self.value = value
        self.depth = depth
        _expanded = State(initialValue: CompactDisplay.expandedByDefault(depth: depth))
    }

    var body: some View {
        switch value {
        case .object(let object):
            DisclosureGroup(isExpanded: $expanded) {
                StructuredValueView(value: value, depth: depth + 1).padding(.leading, 12)
            } label: {
                keyLabel(badge: "{ \(object.count) }")
            }
        case .array(let items):
            DisclosureGroup(isExpanded: $expanded) {
                StructuredValueView(value: value, depth: depth + 1).padding(.leading, 12)
            } label: {
                keyLabel(badge: "[ \(items.count) ]")
            }
        default:
            StructuredLeaf(key: key, value: value)
        }
    }

    private func keyLabel(badge: String) -> some View {
        HStack(spacing: 6) {
            Text(key).font(.footnote.monospaced().weight(.semibold)).foregroundStyle(palette.onSurface)
            Text(badge).font(.caption2.monospaced()).foregroundStyle(palette.onSurfaceVariant)
        }
    }
}

/// 葉（string/number/bool/null）の 1 行表示。型ごとに色分け（JSON シンタックスハイライト）。
/// 長い文字列はプレビューに畳み、タップで全文展開。
private struct StructuredLeaf: View {
    let key: String?
    let value: StructuredValue
    @State private var expanded = false
    @Environment(\.colorPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if let key {
                Text(key).font(.footnote.monospaced().weight(.semibold)).foregroundStyle(palette.onSurfaceVariant)
                Text(":").foregroundStyle(palette.outline)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(shownText).font(.footnote.monospaced()).foregroundStyle(color)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if truncatable {
                    Button(expanded ? "折りたたむ" : "全文（\(fullText.count) 文字）") {
                        withAnimation(.snappy) { expanded.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(palette.primary)
                }
            }
        }
    }

    private var fullText: String {
        if case .string(let s) = value { return s }
        return ""
    }

    private var truncatable: Bool {
        CompactDisplay.preview(fullText, limit: CompactDisplay.leafPreviewLimit).truncated
    }

    private var shownText: String {
        switch value {
        case .string(let s):
            let preview = CompactDisplay.preview(s, limit: CompactDisplay.leafPreviewLimit)
            return expanded || !preview.truncated ? "\"\(s)\"" : "\"\(preview.shown)…\""
        case .number(let n): return n.description
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        default: return ""
        }
    }

    private var color: Color {
        switch value {
        case .string: return .green
        case .number: return .blue
        case .bool: return .purple
        case .null: return palette.outline
        default: return palette.onSurface
        }
    }
}
