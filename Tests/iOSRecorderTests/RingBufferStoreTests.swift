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

@Suite struct RingBufferStoreByteCapacityTests {
    private func record(_ id: String, bytes: Int, at second: TimeInterval) -> Record {
        RecordFixtures.make(
            id: RecordID(rawValue: id),
            recordedAt: Date(timeIntervalSince1970: second),
            artifacts: [Artifact(kind: .state, mediaType: "application/octet-stream", data: Data(count: bytes))]
        )
    }

    @Test func evictsOldestWhenBytesExceedCapacity() async throws {
        let store = RingBufferStore(capacity: 100, capacityBytes: 250)
        try await store.save(record("a", bytes: 100, at: 1))
        try await store.save(record("b", bytes: 100, at: 2))
        try await store.save(record("c", bytes: 100, at: 3))   // 300 > 250 → a を退避

        let all = try await store.query(RecordQuery())
        #expect(all.map(\.id.rawValue) == ["c", "b"])
        await #expect(throws: RecordStoreError.self) {
            _ = try await store.fetch(RecordID(rawValue: "a"))
        }
    }

    @Test func keepsNewestRecordEvenIfAloneOverBudget() async throws {
        let store = RingBufferStore(capacity: 100, capacityBytes: 50)
        try await store.save(record("big", bytes: 500, at: 1))
        let fetched = try await store.fetch(RecordID(rawValue: "big"))
        #expect(fetched.id.rawValue == "big")
    }

    @Test func resavingSameIDDoesNotDoubleCountBytes() async throws {
        let store = RingBufferStore(capacity: 100, capacityBytes: 250)
        try await store.save(record("a", bytes: 100, at: 1))
        try await store.save(record("a", bytes: 100, at: 1))   // 上書き = 100 bytes のまま
        try await store.save(record("b", bytes: 100, at: 2))   // 合計 200 ≤ 250 → 退避なし
        let all = try await store.query(RecordQuery())
        #expect(all.count == 2)
    }
}
