import Testing
import Foundation
import iOSRecorder
@testable import iOSRecorderNetwork

@MainActor
@Suite struct NetworkLogStoreTests {
    private func log(_ url: String) -> NetworkLog {
        NetworkLog(method: "GET", url: url, host: "example.com", startedAt: Date(), duration: 0.1)
    }

    @Test func addsNewestFirst() {
        let store = NetworkLogStore()
        store.add(log("https://example.com/a"))
        store.add(log("https://example.com/b"))
        #expect(store.logs.first?.url == "https://example.com/b")
        #expect(store.logs.count == 2)
    }

    @Test func evictsOldestBeyondCapacity() {
        let store = NetworkLogStore(capacity: 2)
        store.add(log("https://example.com/1"))
        store.add(log("https://example.com/2"))
        store.add(log("https://example.com/3"))
        #expect(store.logs.count == 2)
        #expect(store.logs.map(\.url) == ["https://example.com/3", "https://example.com/2"])
    }

    @Test func clearEmptiesLogs() {
        let store = NetworkLogStore()
        store.add(log("https://example.com/x"))
        store.clear()
        #expect(store.logs.isEmpty)
    }
}

@Suite struct NetworkLogSanitizerTests {
    @Test func masksSensitiveHeaders() {
        let masked = NetworkLogSanitizer.maskHeaders([
            "Authorization": "Bearer secret",
            "Content-Type": "application/json"
        ])
        #expect(masked["Authorization"] == "***")
        #expect(masked["Content-Type"] == "application/json")
    }

    @Test func truncatesLargeBody() {
        let data = Data(repeating: 65, count: 5000)
        let text = NetworkLogSanitizer.bodyString(data, limit: 100)
        #expect(text?.contains("truncated") == true)
        #expect((text?.count ?? 0) < 200)
    }

    @Test func emptyBodyIsNil() {
        #expect(NetworkLogSanitizer.bodyString(nil) == nil)
        #expect(NetworkLogSanitizer.bodyString(Data()) == nil)
    }

    @Test func masksSensitiveQueryParams() {
        let url = "https://generativelanguage.googleapis.com/v1beta/models/x:generateContent?key=SECRET123&alt=sse"
        let masked = NetworkLogSanitizer.maskURL(url)
        #expect(masked.contains("key=***"))
        #expect(masked.contains("SECRET123") == false)
        #expect(masked.contains("alt=sse"))   // Ordinary parameters survive untouched
    }

    @Test func leavesURLWithoutQueryUntouched() {
        let url = "https://example.com/v1/path"
        #expect(NetworkLogSanitizer.maskURL(url) == url)
    }
}

@Suite struct NetworkLogTests {
    @Test func failureDetection() {
        let ok = NetworkLog(method: "GET", url: "u", host: "h", statusCode: 200, startedAt: Date(), duration: 0)
        let bad = NetworkLog(method: "GET", url: "u", host: "h", statusCode: 500, startedAt: Date(), duration: 0)
        let errored = NetworkLog(method: "GET", url: "u", host: "h", errorMessage: "timeout", startedAt: Date(), duration: 0)
        #expect(ok.isFailure == false)
        #expect(bad.isFailure == true)
        #expect(errored.isFailure == true)
    }

    @Test func redactsHeadersAndTruncatesBody() {
        let log = NetworkLog(
            method: "POST", url: "https://api.example.com/v1", host: "api.example.com",
            requestHeaders: ["Authorization": "Bearer secret", "Content-Type": "application/json"],
            requestBody: String(repeating: "x", count: 5000),
            statusCode: 200, startedAt: Date(), duration: 0.2
        )
        let red = log.redacted(bodyLimit: 100)
        #expect(red.requestHeaders["Authorization"] == "***")
        #expect(red.requestHeaders["Content-Type"] == "application/json")
        #expect(red.requestBody?.contains("truncated") == true)
    }

    @Test func elidesBinaryResponseBodyByContentType() {
        let log = NetworkLog(
            method: "GET", url: "https://img.example/x.jpg", host: "img.example",
            statusCode: 200,
            responseHeaders: ["Content-Type": "image/jpeg", "Content-Length": "124534"],
            responseBody: String(repeating: "A", count: 4096),
            startedAt: Date(), duration: 0.1
        )
        let red = log.redacted(bodyLimit: 4096)
        #expect(red.responseBody == "<elided image/jpeg, 124534 bytes>")
        #expect(red.responseBody?.contains("AAAA") == false)
    }

    @Test func keepsTextualResponseBody() {
        let log = NetworkLog(
            method: "POST", url: "https://api.example/v1", host: "api.example",
            statusCode: 200,
            responseHeaders: ["Content-Type": "application/json; charset=UTF-8"],
            responseBody: "{\"keepme\":true}",
            startedAt: Date(), duration: 0.1
        )
        let red = log.redacted(bodyLimit: 4096)
        #expect(red.responseBody == "{\"keepme\":true}")
    }

    @Test func codableRoundTrip() throws {
        let log = NetworkLog(
            method: "GET", url: "https://example.com/a", host: "example.com",
            statusCode: 200, startedAt: Date(timeIntervalSince1970: 1_700_000_000), duration: 0.5
        )
        let data = try JSONEncoder().encode(log)
        let decoded = try JSONDecoder().decode(NetworkLog.self, from: data)
        #expect(decoded == log)
    }
}

@MainActor
@Suite struct NetworkSourceTests {
    private let ctx = RecordContext(session: SessionID(rawValue: "s"))

    @Test func snapshotsLogsIntoNetworkArtifact() async {
        let store = NetworkLogStore()
        store.add(NetworkLog(
            method: "GET", url: "https://api.example.com/users", host: "api.example.com",
            requestHeaders: ["Authorization": "Bearer secret"],
            statusCode: 200, startedAt: Date(), duration: 0.1
        ))
        let source = NetworkSource(store: store)
        let artifact = await source.measure(ctx)
        #expect(artifact?.kind == .network)
        #expect(artifact?.mediaType == "application/json")
        #expect(artifact?.attributes["type"] == "NetworkLog")
        #expect(artifact?.attributes["count"] == "1")
        let json = String(decoding: artifact!.data, as: UTF8.self)
        #expect(json.contains("api.example.com/users"))
        #expect(json.contains("***"))            // The capture path masked the header
        #expect(json.contains("Bearer secret") == false)
    }

    @Test func emptyBufferYieldsNoArtifact() async {
        let source = NetworkSource(store: NetworkLogStore())
        #expect(await source.measure(ctx) == nil)
    }

    @Test func capsAtMaxEntries() async {
        let store = NetworkLogStore()
        for i in 0..<10 {
            store.add(NetworkLog(method: "GET", url: "https://example.com/\(i)", host: "example.com", startedAt: Date(), duration: 0))
        }
        let source = NetworkSource(store: store, maxEntries: 3)
        let artifact = await source.measure(ctx)
        #expect(artifact?.attributes["count"] == "3")
    }
}

@Suite struct SanitizerSensitiveKeyTests {
    @Test func masksCompoundQueryKeys() {
        let url = "https://auth.example/oauth?client_secret=S1&oauth_signature=S2&access_token=S3&state=keepme"
        let masked = NetworkLogSanitizer.maskURL(url)
        #expect(masked.contains("client_secret=***"))
        #expect(masked.contains("oauth_signature=***"))
        #expect(masked.contains("access_token=***"))
        #expect(masked.contains("state=keepme"))
        #expect(masked.contains("S1") == false && masked.contains("S2") == false && masked.contains("S3") == false)
    }

    @Test func masksNonStandardAuthHeaders() {
        let masked = NetworkLogSanitizer.maskHeaders([
            "X-Auth-Token": "secret1",
            "X-Goog-Api-Key": "secret2",
            "Content-Type": "application/json",
            "Accept-Encoding": "gzip"
        ])
        #expect(masked["X-Auth-Token"] == "***")
        #expect(masked["X-Goog-Api-Key"] == "***")
        #expect(masked["Content-Type"] == "application/json")
        #expect(masked["Accept-Encoding"] == "gzip")
    }

    @Test func masksSensitiveJSONStringValuesInBody() {
        let body = #"{"apiKey":"sk-12345","password":"hunter2","prompt":"hello world","count":3}"#
        let masked = NetworkLogSanitizer.maskJSONStringValues(body)
        #expect(masked.contains("sk-12345") == false)
        #expect(masked.contains("hunter2") == false)
        #expect(masked.contains(#""apiKey":"***""#))
        #expect(masked.contains(#""prompt":"hello world""#))   // Ordinary keys survive untouched
        #expect(masked.contains(#""count":3"#))
    }

    @Test func redactBodyMasksJSONSecretsInRequestAndResponse() {
        let log = NetworkLog(
            method: "POST", url: "https://api.example/v1", host: "api.example",
            requestHeaders: ["Content-Type": "application/json"],
            requestBody: #"{"api_key":"SECRET-REQ","q":"weather"}"#,
            statusCode: 200,
            responseHeaders: ["Content-Type": "application/json"],
            responseBody: #"{"session_token":"SECRET-RES","answer":"sunny"}"#,
            startedAt: Date(), duration: 0.1
        )
        let red = log.redacted()
        #expect(red.requestBody?.contains("SECRET-REQ") == false)
        #expect(red.requestBody?.contains("weather") == true)
        #expect(red.responseBody?.contains("SECRET-RES") == false)
        #expect(red.responseBody?.contains("sunny") == true)
    }

    @Test func elidesSniffedBinaryWhenContentTypeMissing() {
        // No Content-Type, and U+FFFD scattered through it: binary that was decoded as text.
        let mojibake = "PNG\u{FFFD}\u{FFFD}\u{FFFD}data"
        let redacted = NetworkLogSanitizer.redactBody(mojibake, contentType: nil, contentLength: "12345")
        #expect(redacted?.contains("elided") == true)
        #expect(redacted?.contains("\u{FFFD}") == false)
    }

    @Test func keepsPlainTextWhenContentTypeMissing() {
        let redacted = NetworkLogSanitizer.redactBody("plain text body", contentType: nil, contentLength: nil)
        #expect(redacted == "plain text body")
    }
}
