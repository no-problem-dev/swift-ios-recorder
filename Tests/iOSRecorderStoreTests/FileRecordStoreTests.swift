import Testing
import Foundation
@testable import iOSRecorderStore
import iOSRecorder
import iOSRecorderTestSupport

@Suite struct FileRecordStoreTests {
    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("iosrec-test-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func savesAndFetchesRoundTrip() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileRecordStore(rootURL: root)

        let record = RecordFixtures.make(artifacts: [
            .screenshot(pngData: Data([9, 9])),
            .log(text: "hey")
        ])
        try await store.save(record)
        let fetched = try await store.fetch(record.id)

        #expect(fetched.id == record.id)
        #expect(fetched.artifacts.count == 2)
        #expect(fetched.artifacts.contains { $0.kind == .screenshot && $0.data == Data([9, 9]) })
        #expect(fetched.artifacts.contains { $0.kind == .log })
    }

    @Test func writesFinderFriendlyLayout() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileRecordStore(rootURL: root)

        let record = RecordFixtures.make(
            id: RecordID(rawValue: "rec1"),
            artifacts: [.screenshot(pngData: Data([0]))]
        )
        try await store.save(record)

        let dir = root.appendingPathComponent("rec1", isDirectory: true)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("meta.json").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("0-screenshot.png").path))
    }

    @Test func removeAllDeletesEveryRecord() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileRecordStore(rootURL: root)
        try await store.save(RecordFixtures.make(id: RecordID(rawValue: "a")))
        try await store.save(RecordFixtures.make(id: RecordID(rawValue: "b")))

        try await store.removeAll()

        let all = try await store.query(RecordQuery())
        #expect(all.isEmpty)
    }

    @Test func deleteRemovesOneRecord() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileRecordStore(rootURL: root)
        try await store.save(RecordFixtures.make(id: RecordID(rawValue: "a")))
        try await store.save(RecordFixtures.make(id: RecordID(rawValue: "b")))

        try await store.delete(RecordID(rawValue: "a"))

        let all = try await store.query(RecordQuery())
        #expect(all.map(\.id) == [RecordID(rawValue: "b")])
    }

    @Test func maxRecordsPrunesOldest() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileRecordStore(rootURL: root, maxRecords: 2)
        for second in 1...4 {
            try await store.save(RecordFixtures.make(
                id: RecordID(rawValue: "r\(second)"),
                recordedAt: Date(timeIntervalSince1970: TimeInterval(second))
            ))
        }
        let all = try await store.query(RecordQuery())
        #expect(all.count == 2)
        #expect(all.map(\.id) == [RecordID(rawValue: "r4"), RecordID(rawValue: "r3")])
    }

    @Test func fetchMissingThrowsNotFound() async {
        let store = FileRecordStore(rootURL: tempRoot())
        await #expect(throws: RecordStoreError.self) {
            _ = try await store.fetch(RecordID(rawValue: "ghost"))
        }
    }

    @Test func queryFiltersAndSortsNewestFirst() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileRecordStore(rootURL: root)

        try await store.save(RecordFixtures.make(
            id: RecordID(rawValue: "old"), screenName: "A",
            recordedAt: Date(timeIntervalSince1970: 1)
        ))
        try await store.save(RecordFixtures.make(
            id: RecordID(rawValue: "new"), screenName: "A",
            recordedAt: Date(timeIntervalSince1970: 2)
        ))
        try await store.save(RecordFixtures.make(
            id: RecordID(rawValue: "other"), screenName: "B",
            recordedAt: Date(timeIntervalSince1970: 3)
        ))

        let result = try await store.query(RecordQuery(screenName: "A"))
        #expect(result.count == 2)
        #expect(result.first?.id == RecordID(rawValue: "new"))
    }
}

@Suite struct FileRecordStoreStorageInfoTests {
    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("iosrecorder-tests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func reportsCountsBytesAndTimeRange() async throws {
        let store = FileRecordStore(rootURL: makeRoot())
        try await store.save(RecordFixtures.make(
            id: RecordID(rawValue: "old"), recordedAt: Date(timeIntervalSince1970: 100),
            artifacts: [.log(text: String(repeating: "a", count: 1000))]))
        try await store.save(RecordFixtures.make(
            id: RecordID(rawValue: "new"), recordedAt: Date(timeIntervalSince1970: 200),
            artifacts: [.log(text: String(repeating: "b", count: 2000))]))

        let info = await store.storageInfo()
        #expect(info.totalRecords == 2)
        #expect(info.totalBytes >= 3000)   // Artifact bytes plus the meta.json alongside them
        #expect(info.oldestRecordedAt == Date(timeIntervalSince1970: 100))
        #expect(info.newestRecordedAt == Date(timeIntervalSince1970: 200))
    }

    @Test func emptyStoreReportsZeros() async {
        let info = await FileRecordStore(rootURL: makeRoot()).storageInfo()
        #expect(info.totalRecords == 0)
        #expect(info.totalBytes == 0)
        #expect(info.oldestRecordedAt == nil)
    }
}

@Suite struct FileRecordStoreCacheTests {
    private func makeRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("iosrecorder-tests-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func repeatedQueriesStayConsistentAcrossMutations() async throws {
        let store = FileRecordStore(rootURL: makeRoot())
        try await store.save(RecordFixtures.make(id: RecordID(rawValue: "a")))
        #expect(try await store.query(RecordQuery()).count == 1)
        #expect(try await store.query(RecordQuery()).count == 1)   // Same answer served from cache

        try await store.save(RecordFixtures.make(id: RecordID(rawValue: "b")))
        #expect(try await store.query(RecordQuery()).count == 2)   // A save invalidates it

        try await store.delete(RecordID(rawValue: "a"))
        #expect(try await store.query(RecordQuery()).map(\.id.rawValue) == ["b"])   // So does a delete

        try await store.removeAll()
        #expect(try await store.query(RecordQuery()).isEmpty)
    }
}
