import SwiftUI
import DesignSystem
import StructuredDataCore
import JSONParsing

/// Renders any `StructuredValue` as a recursively collapsible tree.
/// It opens compact — only the top level expanded, deeper levels folded, long child lists revealed a
/// batch at a time, long string leaves shown as a preview with a full-text toggle — so even a huge
/// payload stays readable and keeps scrolling.
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

    /// Parses data for display as a tree.
    /// - Returns: `nil` when the data is not JSON, which is the caller's cue to fall back to plain text.
    static func parse(_ data: Data) -> StructuredValue? {
        try? JSONParser().parse(data)
    }
}

/// A disclosure group for an object or an array, a single line for anything else.
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

/// One line for a string, number, bool or null, colored by type the way JSON highlighting does.
/// A long string is folded to a preview with a tap to see all of it.
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
