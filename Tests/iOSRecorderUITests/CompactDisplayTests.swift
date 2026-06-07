import Testing
import Foundation
@testable import iOSRecorderUI

@Suite struct CompactDisplayTests {
    @Test func shortTextIsNotTruncated() {
        let result = CompactDisplay.preview("hello", limit: 100)
        #expect(result.shown == "hello")
        #expect(result.truncated == false)
    }

    @Test func longTextIsTruncatedAtLimit() {
        let long = String(repeating: "x", count: 1000)
        let result = CompactDisplay.preview(long, limit: 300)
        #expect(result.truncated == true)
        #expect(result.shown.count == 300)
    }

    @Test func onlyTopLevelExpandsByDefault() {
        #expect(CompactDisplay.expandedByDefault(depth: 0) == true)
        #expect(CompactDisplay.expandedByDefault(depth: 1) == false)
        #expect(CompactDisplay.expandedByDefault(depth: 5) == false)
    }

    @Test func formatsBytesHumanReadable() {
        #expect(CompactDisplay.formatBytes(812) == "812 B")
        #expect(CompactDisplay.formatBytes(53_103) == "52 KB")
        #expect(CompactDisplay.formatBytes(3_275_649) == "3.1 MB")
    }
}
