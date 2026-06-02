import Testing
import Foundation
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
}
