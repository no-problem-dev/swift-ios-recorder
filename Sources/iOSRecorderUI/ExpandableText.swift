import SwiftUI
import DesignSystem

/// 長文を既定で折り畳み、タップで全文を見せるテキスト。payload・生ログの表示に使う。
struct ExpandableText: View {
    let text: String
    var previewLimit: Int = CompactDisplay.textPreviewLimit
    @State private var expanded = false
    @Environment(\.colorPalette) private var palette

    var body: some View {
        let preview = CompactDisplay.preview(text, limit: previewLimit)
        VStack(alignment: .leading, spacing: 6) {
            Text(expanded ? text : preview.shown + (preview.truncated ? "…" : ""))
                .font(.footnote.monospaced())
                .foregroundStyle(palette.onSurface)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if preview.truncated {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    Label(
                        expanded ? "折りたたむ" : "全文を表示（\(text.count) 文字）",
                        systemImage: expanded ? "chevron.up" : "chevron.down"
                    )
                    .typography(.labelMedium)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.primary)
            }
        }
    }
}
