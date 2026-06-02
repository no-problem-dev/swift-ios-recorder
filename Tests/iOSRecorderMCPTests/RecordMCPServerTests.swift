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
