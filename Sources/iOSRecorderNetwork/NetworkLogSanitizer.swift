import Foundation

/// 機密ヘッダのマスクとボディの truncate。実通信なしで単体テストできる。
public enum NetworkLogSanitizer {
    static let sensitiveHeaders: Set<String> = [
        "authorization", "cookie", "set-cookie", "x-api-key", "api-key", "proxy-authorization"
    ]

    /// URL クエリで機密として扱うキー（Gemini の ?key= 等）。
    static let sensitiveQueryKeys: Set<String> = [
        "key", "api_key", "apikey", "access_token", "token", "auth", "password", "secret", "sig", "signature"
    ]

    public static func maskHeaders(_ headers: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in headers {
            result[key] = sensitiveHeaders.contains(key.lowercased()) ? "***" : value
        }
        return result
    }

    /// URL のクエリパラメータのうち機密キーの値を *** に置換する。
    /// 多くの API（Gemini 等）は鍵をヘッダではなく URL クエリで渡すため必須。
    public static func maskURL(_ url: String) -> String {
        guard var components = URLComponents(string: url), let items = components.queryItems else { return url }
        components.queryItems = items.map { item in
            sensitiveQueryKeys.contains(item.name.lowercased())
                ? URLQueryItem(name: item.name, value: "***")
                : item
        }
        return components.string ?? url
    }

    public static func bodyString(_ data: Data?, limit: Int = 4096) -> String? {
        guard let data, !data.isEmpty else { return nil }
        let text = String(decoding: data.prefix(limit), as: UTF8.self)
        if data.count > limit {
            return text + "\n…(truncated, \(data.count) bytes total)"
        }
        return text
    }

    /// すでに String 化されたボディを truncate する（既存の NetworkLog 用）。
    public static func truncate(_ text: String, limit: Int = 4096) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n…(truncated, \(text.count) chars total)"
    }

    /// ヘッダを大小無視で引く（HTTP ヘッダは case-insensitive）。
    public static func headerValue(_ headers: [String: String], _ name: String) -> String? {
        for (key, value) in headers where key.caseInsensitiveCompare(name) == .orderedSame { return value }
        return nil
    }

    /// Content-Type がテキスト系か。不明（nil/空）は保持側に倒す。
    public static func isTextualContentType(_ contentType: String?) -> Bool {
        guard let lower = contentType?.lowercased(), !lower.isEmpty else { return true }
        if lower.hasPrefix("text/") { return true }
        return lower.contains("json") || lower.contains("xml") || lower.contains("javascript")
            || lower.contains("html") || lower.contains("csv") || lower.contains("x-www-form-urlencoded")
    }

    /// Content-Type が非テキスト（画像/動画/バイナリ）なら body をサイズ付きプレースホルダに置換し、
    /// テキストなら従来どおり truncate する。mojibake を Record/Bonjour/MCP に流さないための根治点。
    public static func redactBody(
        _ body: String?,
        contentType: String?,
        contentLength: String?,
        limit: Int = 4096
    ) -> String? {
        guard let body else { return nil }
        if isTextualContentType(contentType) { return truncate(body, limit: limit) }
        let size = contentLength ?? "\(body.utf8.count)"
        return "<elided \(contentType ?? "binary"), \(size) bytes>"
    }
}
