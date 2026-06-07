import Foundation

/// 機密ヘッダ/クエリ/ボディのマスクとボディの truncate。実通信なしで単体テストできる。
///
/// 方針: 「キー名が秘密情報を示唆するなら値を隠す」。完全一致リストではなく部分一致で
/// 判定し、`client_secret` / `oauth_signature` / `X-Auth-Token` のような複合キーも捕捉する。
/// デバッグ計器なので false positive（無害な値を隠す）は許容し、漏れの方を防ぐ。
public enum NetworkLogSanitizer {
    /// キー名にこれらが含まれたら機密とみなす（lowercase 比較）。
    static let sensitiveKeyFragments = [
        "password", "secret", "token", "auth", "credential", "signature",
        "apikey", "api-key", "api_key", "cookie"
    ]

    /// ヘッダ名・クエリキー・JSON キーが機密を示唆するか。
    static func isSensitiveKey(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower == "key" || lower == "sig" || lower.hasSuffix("key") { return true }
        return sensitiveKeyFragments.contains { lower.contains($0) }
    }

    public static func maskHeaders(_ headers: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in headers {
            result[key] = isSensitiveKey(key) ? "***" : value
        }
        return result
    }

    /// URL のクエリパラメータのうち機密キーの値を *** に置換する。
    /// 多くの API（Gemini 等）は鍵をヘッダではなく URL クエリで渡すため必須。
    public static func maskURL(_ url: String) -> String {
        guard var components = URLComponents(string: url), let items = components.queryItems else { return url }
        components.queryItems = items.map { item in
            isSensitiveKey(item.name) ? URLQueryItem(name: item.name, value: "***") : item
        }
        return components.string ?? url
    }

    /// テキストボディ中の JSON 文字列値のうち、キーが機密を示唆するものを *** に置換する。
    /// POST body の `{"api_key": "..."}` や応答の `{"session_token": "..."}` を隠す。
    public static func maskJSONStringValues(_ text: String) -> String {
        var result = text
        for match in Self.jsonStringPair.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let keyRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: result),
                  isSensitiveKey(String(text[keyRange])) else { continue }
            result.replaceSubrange(valueRange, with: "***")
        }
        return result
    }

    /// `"key" : "value"` のペア。group 1 = key、group 2 = value（エスケープ対応）。
    private static let jsonStringPair = try! NSRegularExpression(
        pattern: #""((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)""#
    )

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

    /// Content-Type がテキスト系か。不明（nil/空）は保持側に倒す（実体は redactBody で sniff）。
    public static func isTextualContentType(_ contentType: String?) -> Bool {
        guard let lower = contentType?.lowercased(), !lower.isEmpty else { return true }
        if lower.hasPrefix("text/") { return true }
        return lower.contains("json") || lower.contains("xml") || lower.contains("javascript")
            || lower.contains("html") || lower.contains("csv") || lower.contains("x-www-form-urlencoded")
    }

    /// バイナリを誤って UTF-8 テキスト化した痕跡（置換文字 U+FFFD）があるか。
    static func looksBinary(_ text: String) -> Bool {
        text.prefix(2048).contains("\u{FFFD}")
    }

    /// Content-Type が非テキスト（画像/動画/バイナリ）なら body をサイズ付きプレースホルダに置換し、
    /// テキストなら機密 JSON 値をマスクして truncate する。Content-Type 不明でもバイナリの痕跡が
    /// あれば省略する。mojibake と機密を Record/Bonjour/MCP に流さないための根治点。
    public static func redactBody(
        _ body: String?,
        contentType: String?,
        contentLength: String?,
        limit: Int = 4096
    ) -> String? {
        guard let body else { return nil }
        let size = contentLength ?? "\(body.utf8.count)"
        if !isTextualContentType(contentType) {
            return "<elided \(contentType ?? "binary"), \(size) bytes>"
        }
        if (contentType ?? "").isEmpty, looksBinary(body) {
            return "<elided binary, \(size) bytes>"
        }
        return truncate(maskJSONStringValues(body), limit: limit)
    }
}
