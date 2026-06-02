import Testing
import Foundation
@testable import iOSRecorder
import iOSRecorderTestSupport

@Suite struct OutboxExporterTests {
    @Test func persistsRecordWhenInnerFails() async throws {
        let flaky = FlakyExporter(online: false)
        let outbox = FakeRecordStore()
        let exporter = OutboxExporter(wrapping: flaky, outbox: outbox)

        await #expect(throws: (any Error).self) {
            try await exporter.export(RecordFixtures.make(id: RecordID(rawValue: "r1")))
        }
        #expect(await exporter.pendingCount() == 1)
        #expect(await flaky.exportedCount() == 0)
    }

    @Test func drainResendsPersistedRecordsWhenBackOnline() async throws {
        let flaky = FlakyExporter(online: false)
        let outbox = FakeRecordStore()
        let exporter = OutboxExporter(wrapping: flaky, outbox: outbox)

        for raw in ["r1", "r2"] {
            try? await exporter.export(RecordFixtures.make(id: RecordID(rawValue: raw)))
        }
        #expect(await exporter.pendingCount() == 2)

        await flaky.setOnline(true)
        let sent = await exporter.drain()
        #expect(sent == 2)
        #expect(await exporter.pendingCount() == 0)
        #expect(await flaky.exportedCount() == 2)
    }

    @Test func successfulExportLeavesNothingPending() async throws {
        let flaky = FlakyExporter(online: true)
        let exporter = OutboxExporter(wrapping: flaky, outbox: FakeRecordStore())
        try await exporter.export(RecordFixtures.make(id: RecordID(rawValue: "ok")))
        #expect(await exporter.pendingCount() == 0)
        #expect(await flaky.exportedCount() == 1)
    }

    @Test func labelMirrorsInnerExporter() async {
        let exporter = OutboxExporter(wrapping: FakeExporter(label: "bonjour"), outbox: FakeRecordStore())
        #expect(exporter.label == "bonjour")
    }
}
