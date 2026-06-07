import Testing
import Foundation
@testable import iOSRecorderMCP
import iOSRecorder
import iOSRecorderTestSupport

@Suite struct RecordMCPServerTests {
    @Test func listDelegatesToStore() async throws {
        let store = FakeRecordStore()
        try await store.save(RecordFixtures.make(id: RecordID(rawValue: "x")))
        let server = RecordMCPServer(store: store)

        let list = try await server.listCaptures()
        #expect(list.count == 1)
        #expect(list.first?.id == RecordID(rawValue: "x"))
    }

    @Test func listPassesQueryThrough() async throws {
        let store = FakeRecordStore()
        try await store.save(RecordFixtures.make(id: RecordID(rawValue: "a"), screenName: "Login"))
        try await store.save(RecordFixtures.make(id: RecordID(rawValue: "b"), screenName: "Home"))
        let server = RecordMCPServer(store: store)

        let list = try await server.listCaptures(RecordQuery(screenName: "Login"))
        #expect(list.map(\.id) == [RecordID(rawValue: "a")])
    }

    @Test func getDelegatesToStore() async throws {
        let store = FakeRecordStore()
        let record = RecordFixtures.make(id: RecordID(rawValue: "y"))
        try await store.save(record)
        let server = RecordMCPServer(store: store)

        let got = try await server.getCapture(RecordID(rawValue: "y"))
        #expect(got.id == record.id)
    }

    @Test func getMissingPropagatesNotFound() async {
        let server = RecordMCPServer(store: FakeRecordStore())
        await #expect(throws: RecordStoreError.self) {
            _ = try await server.getCapture(RecordID(rawValue: "none"))
        }
    }

    @Test func deleteRemovesCapture() async throws {
        let store = FakeRecordStore()
        try await store.save(RecordFixtures.make(id: RecordID(rawValue: "a")))
        try await store.save(RecordFixtures.make(id: RecordID(rawValue: "b")))
        let server = RecordMCPServer(store: store)

        try await server.deleteCapture(RecordID(rawValue: "a"))

        let list = try await server.listCaptures()
        #expect(list.map(\.id) == [RecordID(rawValue: "b")])
    }

    @Test func clearRemovesAll() async throws {
        let store = FakeRecordStore()
        try await store.save(RecordFixtures.make(id: RecordID(rawValue: "a")))
        let server = RecordMCPServer(store: store)

        try await server.clearCaptures()

        #expect(try await server.listCaptures().isEmpty)
    }
}

@Suite struct SearchEventsScanWindowTests {
    private func timelineRecord(_ id: String, at second: TimeInterval) -> Record {
        let event: [String: Any] = [
            "id": UUID().uuidString, "at": "2026-06-06T00:00:00Z",
            "category": "agent", "name": "step", "summary": "in \(id)",
            "attributes": [String: String]()
        ]
        let artifact = Artifact(
            kind: ArtifactKind(rawValue: "debug_timeline"), mediaType: "application/json",
            data: try! JSONSerialization.data(withJSONObject: [event]),
            attributes: ["type": "DebugEvent"]
        )
        return RecordFixtures.make(
            id: RecordID(rawValue: id),
            recordedAt: Date(timeIntervalSince1970: second),
            artifacts: [artifact]
        )
    }

    @Test func reportsTruncationWhenScanWindowCutsOff() async throws {
        let store = FakeRecordStore()
        try await store.save(timelineRecord("old", at: 1))
        try await store.save(timelineRecord("new", at: 2))
        let server = RecordMCPServer(store: store, maxScannedCaptures: 1)

        let result = try await server.searchEvents(DebugEventQuery())
        #expect(result.scannedCaptures == 1)
        #expect(result.scanTruncated == true)
    }

    @Test func reportsCompleteScanWhenWithinWindow() async throws {
        let store = FakeRecordStore()
        try await store.save(timelineRecord("only", at: 1))
        let server = RecordMCPServer(store: store)

        let result = try await server.searchEvents(DebugEventQuery())
        #expect(result.hits.count == 1)
        #expect(result.scannedCaptures == 1)
        #expect(result.scanTruncated == false)
    }
}
