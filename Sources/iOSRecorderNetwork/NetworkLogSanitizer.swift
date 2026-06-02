import Foundation

/// 機密ヘッダのマスクとボディの truncate。実通信なしで単体テストできる。
public enum NetworkLogSanitizer {
    static let sensitiveHeaders: Set<String> = [
        "authorization", "cookie", "set-cookie", "x-api-key", "api-key", "proxy-authorization"
    ]

    public static func maskHeaders(_ headers: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in headers {
            result[key] = sensitiveHeaders.contains(key.lowercased()) ? "***" : value
        }
        return result
    }

    public static func bodyString(_ data: Data?, limit: Int = 4096) -> String? {
        guard let data, !data.isEmpty else { return nil }
        let text = String(decoding: data.prefix(limit), as: UTF8.self)
        if data.count > limit {
            return text + "\n…(truncated, \(data.count) bytes total)"
        }
        return text
    }
}
