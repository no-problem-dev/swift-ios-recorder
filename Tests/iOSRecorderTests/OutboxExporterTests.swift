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

/// 恒久的に送れない（大きすぎる）記録が outbox の先頭詰まりを起こさないこと。
private actor SizeRejectingExporter: Exporter {
    public private(set) var exported: [Record] = []
    nonisolated let label = "SizeRejecting"
    func export(_ record: Record) async throws {
        if record.id.rawValue.hasPrefix("big") {
            throw ExporterError.payloadTooLarge(bytes: 999_999_999)
        }
        exported.append(record)
    }
    func exportedCount() -> Int { exported.count }
}

@Suite struct OutboxPayloadTooLargeTests {
    @Test func tooLargeRecordIsNotPersistedToOutbox() async throws {
        let exporter = OutboxExporter(wrapping: SizeRejectingExporter(), outbox: FakeRecordStore())
        await #expect(throws: ExporterError.self) {
            try await exporter.export(RecordFixtures.make(id: RecordID(rawValue: "big1")))
        }
        #expect(await exporter.pendingCount() == 0)   // 再送不能なものは退避しない
    }

    @Test func drainDropsTooLargeAndContinues() async throws {
        let inner = SizeRejectingExporter()
        let outbox = FakeRecordStore()
        // 過去に退避済みの「大きすぎる」記録が先頭にある状況を再現
        try await outbox.save(RecordFixtures.make(
            id: RecordID(rawValue: "big-legacy"), recordedAt: Date(timeIntervalSince1970: 1)))
        try await outbox.save(RecordFixtures.make(
            id: RecordID(rawValue: "ok1"), recordedAt: Date(timeIntervalSince1970: 2)))

        let exporter = OutboxExporter(wrapping: inner, outbox: outbox)
        let sent = await exporter.drain()

        #expect(sent == 1)                              // ok1 は送れた
        #expect(await inner.exportedCount() == 1)
        #expect(await exporter.pendingCount() == 0)     // big-legacy は破棄され詰まらない
    }
}
