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
}
