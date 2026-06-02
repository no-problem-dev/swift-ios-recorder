import Foundation

/// 1 件の HTTP 通信ログ。メモリ上のライブバッファに積まれる。
public struct NetworkLog: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let method: String
    public let url: String
    public let host: String
    public let requestHeaders: [String: String]
    public let requestBody: String?
    public let statusCode: Int?
    public let responseHeaders: [String: String]
    public let responseBody: String?
    public let errorMessage: String?
    public let startedAt: Date
    public let duration: TimeInterval

    public init(
        id: UUID = UUID(),
        method: String,
        url: String,
        host: String,
        requestHeaders: [String: String] = [:],
        requestBody: String? = nil,
        statusCode: Int? = nil,
        responseHeaders: [String: String] = [:],
        responseBody: String? = nil,
        errorMessage: String? = nil,
        startedAt: Date,
        duration: TimeInterval
    ) {
        self.id = id
        self.method = method
        self.url = url
        self.host = host
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.errorMessage = errorMessage
        self.startedAt = startedAt
        self.duration = duration
    }

    public var isFailure: Bool {
        if errorMessage != nil { return true }
        if let statusCode { return statusCode >= 400 }
        return false
    }

    /// URL のパス部分（一覧表示用）。
    public var path: String {
        URLComponents(string: url)?.path ?? url
    }

    /// 機密ヘッダをマスクし、ボディを truncate した安全な複製。
    /// Record/Bonjour/MCP へ外に出す前に必ず通す。
    public func redacted(bodyLimit: Int = 4096) -> NetworkLog {
        NetworkLog(
            id: id,
            method: method,
            url: NetworkLogSanitizer.maskURL(url),
            host: host,
            requestHeaders: NetworkLogSanitizer.maskHeaders(requestHeaders),
            requestBody: requestBody.map { NetworkLogSanitizer.truncate($0, limit: bodyLimit) },
            statusCode: statusCode,
            responseHeaders: NetworkLogSanitizer.maskHeaders(responseHeaders),
            responseBody: responseBody.map { NetworkLogSanitizer.truncate($0, limit: bodyLimit) },
            errorMessage: errorMessage,
            startedAt: startedAt,
            duration: duration
        )
    }
}
