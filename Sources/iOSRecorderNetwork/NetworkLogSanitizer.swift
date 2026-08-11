import Foundation

/// Masks secrets in headers, query strings and bodies, and cuts bodies down to size. Pure string
/// work, so it is testable without any real traffic.
///
/// The rule is that a key name suggesting a secret hides its value. Matching is by substring rather
/// than an exact list, which is what catches compound names like `client_secret`, `oauth_signature`
/// and `X-Auth-Token`. This is debug instrumentation: hiding a harmless value costs nothing, and
/// leaking one costs a rotated key, so it errs toward hiding.
public enum NetworkLogSanitizer {
    /// A key containing any of these is treated as a secret. Compared in lowercase.
    static let sensitiveKeyFragments = [
        "password", "secret", "token", "auth", "credential", "signature",
        "apikey", "api-key", "api_key", "cookie"
    ]

    /// Whether a header name, query key or JSON key suggests a secret. Also catches the bare
    /// `key` and `sig` names and anything ending in `key`, which the fragment list would miss.
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

    /// Replaces the value of any sensitive query parameter with `***`, leaving the rest of the URL
    /// intact. Plenty of APIs — Gemini among them — take the key as `?key=` rather than a header,
    /// so masking headers alone would still ship the key.
    public static func maskURL(_ url: String) -> String {
        guard var components = URLComponents(string: url), let items = components.queryItems else { return url }
        components.queryItems = items.map { item in
            isSensitiveKey(item.name) ? URLQueryItem(name: item.name, value: "***") : item
        }
        return components.string ?? url
    }

    /// Replaces JSON string values whose key suggests a secret, so a request body of
    /// `{"api_key": "..."}` or a response of `{"session_token": "..."}` leaves nothing usable.
    ///
    /// Works on the raw text rather than parsed JSON, so it also covers bodies that are truncated
    /// or not valid JSON at all. Only string values are reachable this way — a secret stored as a
    /// number or nested inside an array of strings survives.
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

    /// Matches a `"key" : "value"` pair, tolerating backslash escapes inside either. Group 1 is
    /// the key, group 2 the value.
    private static let jsonStringPair = try! NSRegularExpression(
        pattern: #""((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)""#
    )

    /// Decodes raw body bytes as UTF-8, keeping at most `limit` *bytes* — unlike
    /// `truncate(_:limit:)`, which counts characters. Empty and absent bodies both answer `nil`.
    ///
    /// The cut lands on a byte boundary, so a multi-byte character straddling it decodes to U+FFFD,
    /// and binary bodies come back as mostly U+FFFD. `looksBinary(_:)` keys off exactly that.
    public static func bodyString(_ data: Data?, limit: Int = 4096) -> String? {
        guard let data, !data.isEmpty else { return nil }
        let text = String(decoding: data.prefix(limit), as: UTF8.self)
        if data.count > limit {
            return text + "\n…(truncated, \(data.count) bytes total)"
        }
        return text
    }

    /// Cuts an already-decoded body down to `limit` characters, appending a note with the original
    /// length so a reader can tell a short body from a shortened one.
    public static func truncate(_ text: String, limit: Int = 4096) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "\n…(truncated, \(text.count) chars total)"
    }

    /// Looks a header up case-insensitively, since a server may answer `content-type` where the
    /// caller asks for `Content-Type` and a plain dictionary lookup would miss it.
    public static func headerValue(_ headers: [String: String], _ name: String) -> String? {
        for (key, value) in headers where key.caseInsensitiveCompare(name) == .orderedSame { return value }
        return nil
    }

    /// Whether a Content-Type names a text format. A missing or empty type answers `true` so that
    /// bodies are kept by default; `redactBody(_:contentType:contentLength:limit:)` then sniffs the
    /// content itself to catch binary that arrived without a type.
    public static func isTextualContentType(_ contentType: String?) -> Bool {
        guard let lower = contentType?.lowercased(), !lower.isEmpty else { return true }
        if lower.hasPrefix("text/") { return true }
        return lower.contains("json") || lower.contains("xml") || lower.contains("javascript")
            || lower.contains("html") || lower.contains("csv") || lower.contains("x-www-form-urlencoded")
    }

    /// Whether the text bears the mark of binary decoded as UTF-8: a U+FFFD replacement character
    /// in the first 2 KB. Only the head is examined, so binary that starts with an ASCII header
    /// longer than that reads as text.
    static func looksBinary(_ text: String) -> Bool {
        text.prefix(2048).contains("\u{FFFD}")
    }

    /// Turns a captured body into something safe and small enough to carry: a non-text body becomes
    /// `<elided image/jpeg, 124534 bytes>`, a text body keeps its shape with JSON secrets masked and
    /// the tail cut off.
    ///
    /// Bodies with no declared type are elided too if they look like decoded binary, which is what
    /// stops a megabyte of mojibake from being copied into a capture and then into an AI's context.
    ///
    /// - Parameters:
    ///   - body: Already-decoded body text, or `nil`, which passes through unchanged.
    ///   - contentType: Declared type. Absent or empty means sniff the body instead.
    ///   - contentLength: Declared size, reported verbatim in the placeholder. Falls back to the
    ///     body's own UTF-8 length, which under-reports a body that was already truncated.
    ///   - limit: Characters of text body to keep.
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
