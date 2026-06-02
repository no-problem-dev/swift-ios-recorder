import Testing
import Foundation
@testable import iOSRecorder
import iOSRecorderTestSupport

@Suite struct RingBufferStoreTests {
    @Test func savesAndFetches() async throws {
        let store = RingBufferStore()
        let record = RecordFixtures.make()
        try await store.save(record)
        let fetched = try await store.fetch(record.id)
        #expect(fetched.id == record.id)
    }

    @Test func fetchMissingThrowsNotFound() async {
        let store = RingBufferStore()
        await #expect(throws: RecordStoreError.notFound(RecordID(rawValue: "nope"))) {
            _ = try await store.fetch(RecordID(rawValue: "nope"))
        }
    }

    @Test func evictsOldestBeyondCapacity() async throws {
        let store = RingBufferStore(capacity: 2)
        let a = RecordFixtures.make(id: RecordID(rawValue: "a"), recordedAt: Date(timeIntervalSince1970: 1))
        let b = RecordFixtures.make(id: RecordID(rawValue: "b"), recordedAt: Date(timeIntervalSince1970: 2))
        let c = RecordFixtures.make(id: RecordID(rawValue: "c"), recordedAt: Date(timeIntervalSince1970: 3))
        try await store.save(a)
        try await store.save(b)
        try await store.save(c)

        let all = try await store.query(RecordQuery())
        #expect(all.count == 2)
        await #expect(throws: RecordStoreError.self) {
            _ = try await store.fetch(a.id)
        }
    }

    @Test func removeAllEmptiesTheStore() async throws {
        let store = RingBufferStore()
        try await store.save(RecordFixtures.make(id: RecordID(rawValue: "a")))
        try await store.save(RecordFixtures.make(id: RecordID(rawValue: "b")))
        try await store.removeAll()
        let all = try await store.query(RecordQuery())
        #expect(all.isEmpty)
    }

    @Test func queryReturnsNewestFirstAndRespectsLimit() async throws {
        let store = RingBufferStore()
        for second in 1...5 {
            try await store.save(RecordFixtures.make(
                id: RecordID(rawValue: "r\(second)"),
                recordedAt: Date(timeIntervalSince1970: TimeInterval(second))
            ))
        }
        let limited = try await store.query(RecordQuery(limit: 3))
        #expect(limited.count == 3)
        #expect(limited.first?.id == RecordID(rawValue: "r5"))
        #expect(limited.last?.id == RecordID(rawValue: "r3"))
    }
}
