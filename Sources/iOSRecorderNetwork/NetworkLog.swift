import Foundation

/// One intercepted HTTP exchange, as buffered live in memory.
///
/// The buffer dies with the process; nothing here reaches disk or the wire until a capture folds it
/// in, and only ever through `redacted()`. A buffered value is not safe to hand out as-is: the
/// interceptor masks header values as it captures, but the URL query and both bodies still hold
/// whatever the app sent.
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

    /// Path alone, for list rows too narrow for the whole URL. Falls back to the full URL string
    /// when it cannot be parsed, so this is never empty.
    public var path: String {
        URLComponents(string: url)?.path ?? url
    }

    /// A copy safe to leave the device: secrets masked in headers, query and JSON bodies, text
    /// bodies truncated, and non-text bodies replaced by a placeholder that keeps only their size.
    ///
    /// - Important: Every path out — capture, transfer, MCP — must go through this. It is the only
    ///   step that masks an API key sitting in the query string or in a JSON body.
    ///
    /// - Parameter bodyLimit: Characters of text body to keep. Anything past it is dropped and
    ///   noted in the text itself; binary bodies are elided regardless of this.
    public func redacted(bodyLimit: Int = 4096) -> NetworkLog {
        NetworkLog(
            id: id,
            method: method,
            url: NetworkLogSanitizer.maskURL(url),
            host: host,
            requestHeaders: NetworkLogSanitizer.maskHeaders(requestHeaders),
            requestBody: NetworkLogSanitizer.redactBody(
                requestBody,
                contentType: NetworkLogSanitizer.headerValue(requestHeaders, "Content-Type"),
                contentLength: NetworkLogSanitizer.headerValue(requestHeaders, "Content-Length"),
                limit: bodyLimit
            ),
            statusCode: statusCode,
            responseHeaders: NetworkLogSanitizer.maskHeaders(responseHeaders),
            responseBody: NetworkLogSanitizer.redactBody(
                responseBody,
                contentType: NetworkLogSanitizer.headerValue(responseHeaders, "Content-Type"),
                contentLength: NetworkLogSanitizer.headerValue(responseHeaders, "Content-Length"),
                limit: bodyLimit
            ),
            errorMessage: errorMessage,
            startedAt: startedAt,
            duration: duration
        )
    }
}
