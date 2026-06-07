import Foundation

/// デバッグ UI の「既定はコンパクト、展開はオンデマンド」ポリシー。
/// 巨大 payload・深い JSON・大量配列でも一覧性とスクロール性能を守る。
enum CompactDisplay {
    /// 長文テキストの折り畳みプレビュー文字数。
    static let textPreviewLimit = 600
    /// 文字列リーフ（JSON の値）の折り畳みプレビュー文字数。
    static let leafPreviewLimit = 200
    /// オブジェクト/配列の子を最初に見せる件数。
    static let initialChildren = 30
    /// 「さらに表示」1 回で増やす件数。
    static let childrenStep = 100

    static func preview(_ text: String, limit: Int) -> (shown: String, truncated: Bool) {
        guard text.count > limit else { return (text, false) }
        return (String(text.prefix(limit)), true)
    }

    /// 構造ツリーはトップレベルだけ開き、深い階層は折り畳んでおく。
    static func expandedByDefault(depth: Int) -> Bool {
        depth == 0
    }

    static func formatBytes(_ bytes: Int) -> String {
        switch bytes {
        case ..<1024: "\(bytes) B"
        case ..<1_048_576: "\((bytes + 512) / 1024) KB"
        default: String(format: "%.1f MB", Double(bytes) / 1_048_576)
        }
    }
}
