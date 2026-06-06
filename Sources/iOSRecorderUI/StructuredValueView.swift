import SwiftUI
import DesignSystem
import StructuredDataCore
import JSONParsing

/// 任意の構造データ（`StructuredValue`）を再帰的に折り畳み表示する汎用ビュー。
/// オブジェクト/配列は DisclosureGroup で展開でき、葉は型ごとに色分け＋選択コピー可能。
/// 利用側がどんな構造体を差し込んでも「中身を構造的に」確認できる。
struct StructuredValueView: View {
    let value: StructuredValue

    var body: some View {
        switch value {
        case .object(let object):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(object.entries.enumerated()), id: \.offset) { _, entry in
                    StructuredNodeRow(key: entry.key, value: entry.value)
                }
            }
        case .array(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    StructuredNodeRow(key: "[\(index)]", value: item)
                }
            }
        default:
            StructuredLeaf(key: nil, value: value)
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
    @State private var expanded = true
    @Environment(\.colorPalette) private var palette

    var body: some View {
        switch value {
        case .object(let object):
            DisclosureGroup(isExpanded: $expanded) {
                StructuredValueView(value: value).padding(.leading, 12)
            } label: {
                keyLabel(badge: "{ \(object.count) }")
            }
        case .array(let items):
            DisclosureGroup(isExpanded: $expanded) {
                StructuredValueView(value: value).padding(.leading, 12)
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
private struct StructuredLeaf: View {
    let key: String?
    let value: StructuredValue
    @Environment(\.colorPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if let key {
                Text(key).font(.footnote.monospaced().weight(.semibold)).foregroundStyle(palette.onSurfaceVariant)
                Text(":").foregroundStyle(palette.outline)
            }
            Text(text).font(.footnote.monospaced()).foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var text: String {
        switch value {
        case .string(let s): return "\"\(s)\""
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
