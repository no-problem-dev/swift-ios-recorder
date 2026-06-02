import Testing
import Foundation
@testable import iOSRecorderBonjour
import iOSRecorder
import iOSRecorderTestSupport

@Suite struct BonjourRoundTripTests {
    @Test func sendsRecordOverLoopback() async throws {
        // serviceName を渡さない → Bonjour 広告なし（ローカルネットワーク権限を踏まない）
        let receiver = try BonjourReceiver(port: .any)
        try await receiver.start()
        let port = try #require(receiver.resolvedPort)

        let received = Task { () -> Record? in
            for try await record in receiver.records() { return record }
            return nil
        }

        let exporter = BonjourExporter(host: "127.0.0.1", port: port)
        let record = RecordFixtures.make(
            id: RecordID(rawValue: "wire1"),
            artifacts: [.log(text: "over the wire")]
        )
        try await exporter.export(record)

        let got = try await withThrowingTaskGroup(of: Record?.self) { group in
            group.addTask { try await received.value }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                return nil
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
        receiver.stop()

        let result = try #require(got)
        #expect(result.id == record.id)
        #expect(result.artifacts.first?.data == Data("over the wire".utf8))
    }
}
