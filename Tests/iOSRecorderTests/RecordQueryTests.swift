import Testing
import Foundation
@testable import iOSRecorder
import iOSRecorderTestSupport

@Suite struct RecordQueryTests {
    @Test func emptyQueryMatchesEverything() {
        let summary = RecordSummary(record: RecordFixtures.make())
        #expect(RecordQuery().matches(summary))
    }

    @Test func filtersByScreenName() {
        let summary = RecordSummary(record: RecordFixtures.make(screenName: "Login"))
        #expect(RecordQuery(screenName: "Login").matches(summary))
        #expect(!RecordQuery(screenName: "Home").matches(summary))
    }

    @Test func filtersBySession() {
        let summary = RecordSummary(record: RecordFixtures.make(session: SessionID(rawValue: "s1")))
        #expect(RecordQuery(session: SessionID(rawValue: "s1")).matches(summary))
        #expect(!RecordQuery(session: SessionID(rawValue: "s2")).matches(summary))
    }

    @Test func filtersByKinds() {
        let summary = RecordSummary(record: RecordFixtures.make(
            artifacts: [.screenshot(pngData: Data()), .log(text: "x")]
        ))
        #expect(RecordQuery(kinds: [.screenshot]).matches(summary))
        #expect(RecordQuery(kinds: [.log]).matches(summary))
        #expect(!RecordQuery(kinds: [.state]).matches(summary))
    }

    @Test func filtersByTimeRange() {
        let summary = RecordSummary(record: RecordFixtures.make(
            recordedAt: Date(timeIntervalSince1970: 100)
        ))
        let inside = Date(timeIntervalSince1970: 50)...Date(timeIntervalSince1970: 150)
        let outside = Date(timeIntervalSince1970: 200)...Date(timeIntervalSince1970: 300)
        #expect(RecordQuery(timeRange: inside).matches(summary))
        #expect(!RecordQuery(timeRange: outside).matches(summary))
    }

    @Test func filtersByTextCaseInsensitively() {
        let summary = RecordSummary(record: RecordFixtures.make(
            screenName: "Checkout",
            tags: ["payment"]
        ))
        #expect(RecordQuery(text: "pay").matches(summary))
        #expect(RecordQuery(text: "CHECK").matches(summary))
        #expect(!RecordQuery(text: "zzz").matches(summary))
    }
}
