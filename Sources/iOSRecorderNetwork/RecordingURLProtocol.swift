import Foundation

/// 全 URLSession 通信を傍受して NetworkLogStore に流す URLProtocol。
/// 自分が転送するリクエストには handledKey を付けて再帰を防ぐ。
final class RecordingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let handledKey = "iOSRecorderHandled"
    nonisolated(unsafe) static var ignoredHosts: [String] = []
    nonisolated(unsafe) static weak var store: NetworkLogStore?

    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var responseData = Data()
    private var httpResponse: HTTPURLResponse?
    private var startedAt = Date()

    override class func canInit(with request: URLRequest) -> Bool {
        if URLProtocol.property(forKey: handledKey, in: request) != nil { return false }
        guard let scheme = request.url?.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        guard let host = request.url?.host else { return false }
        return !ignoredHosts.contains { host.contains($0) }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else { return }
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutable)
        startedAt = Date()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        dataTask = session?.dataTask(with: mutable as URLRequest)
        dataTask?.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
        session?.invalidateAndCancel()
    }

    private func record(error: Error?) {
        let request = self.request
        let response = httpResponse
        let log = NetworkLog(
            method: request.httpMethod ?? "GET",
            url: request.url?.absoluteString ?? "",
            host: request.url?.host ?? "",
            requestHeaders: NetworkLogSanitizer.maskHeaders(request.allHTTPHeaderFields ?? [:]),
            requestBody: NetworkLogSanitizer.bodyString(request.httpBody),
            statusCode: response?.statusCode,
            responseHeaders: NetworkLogSanitizer.maskHeaders(Self.stringHeaders(response)),
            responseBody: NetworkLogSanitizer.bodyString(responseData),
            errorMessage: error?.localizedDescription,
            startedAt: startedAt,
            duration: Date().timeIntervalSince(startedAt)
        )
        let store = Self.store
        Task { @MainActor in store?.add(log) }
    }

    private static func stringHeaders(_ response: HTTPURLResponse?) -> [String: String] {
        guard let fields = response?.allHeaderFields else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in fields {
            result["\(key)"] = "\(value)"
        }
        return result
    }
}

extension RecordingURLProtocol: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        httpResponse = response as? HTTPURLResponse
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseData.append(data)
        client?.urlProtocol(self, didLoad: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
        record(error: error)
        session.finishTasksAndInvalidate()
    }
}
