import Testing
import Foundation
import Network
@testable import iOSRecorderBonjour
import iOSRecorder
import iOSRecorderTestSupport

@Suite struct FramingLimitTests {
    @Test func acceptsLengthsUpToLimit() {
        #expect(Framing.isAcceptableLength(1))
        #expect(Framing.isAcceptableLength(Framing.maxPayloadBytes))
        #expect(Framing.isAcceptableLength(Framing.maxPayloadBytes + 1) == false)
        #expect(Framing.isAcceptableLength(0) == false)
    }

    @Test func hugeHeaderReadsAsUnacceptable() {
        // 0xFFFFFFFF = 4GB 級の悪意ある/壊れた長さプレフィックス
        let length = Framing.readLength(Data([0xFF, 0xFF, 0xFF, 0xFF]))
        #expect(Framing.isAcceptableLength(length) == false)
    }
}

@Suite struct ReceiverFrameLimitTests {
    /// 悪意あるピアが巨大な長さプレフィックスを送っても、受信機は巨大メモリ確保に
    /// 突入せず接続を切り、その後の正常な送信は受け続ける。
    @Test func rejectsOversizedFrameAndKeepsServing() async throws {
        let receiver = try BonjourReceiver(port: .any)
        try await receiver.start()
        let port = try #require(receiver.resolvedPort)

        let received = Task { () -> Record? in
            for try await record in receiver.records() { return record }
            return nil
        }

        // 1) 巨大ヘッダ（4GB 級）を生 TCP で送り込む
        try await sendRaw(Data([0xFF, 0xFF, 0xFF, 0xFF]) + Data("junk".utf8), port: port)

        // 2) 別接続での正常な記録は引き続き受信できる
        let exporter = BonjourExporter(host: "127.0.0.1", port: port)
        let record = RecordFixtures.make(id: RecordID(rawValue: "after-attack"))
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
        #expect(try #require(got).id == record.id)
    }

    private func sendRaw(_ data: Data, port: UInt16) async throws {
        let connection = NWConnection(
            to: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!),
            using: .tcp
        )
        let queue = DispatchQueue(label: "test.raw-sender")
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
            let box = ResumeOnce(c)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: data, completion: .contentProcessed { error in
                        if let error { box.resume(throwing: error) } else { box.resume(returning: ()) }
                        connection.cancel()
                    })
                case .failed(let error):
                    box.resume(throwing: error)
                    connection.cancel()
                default: break
                }
            }
            connection.start(queue: queue)
        }
    }
}

@Suite struct ExporterFrameLimitTests {
    @Test func refusesToExportOversizedRecord() async throws {
        let exporter = BonjourExporter(host: "127.0.0.1", port: 9)   // 接続前に弾かれるのでポートは無関係
        let record = RecordFixtures.make(artifacts: [
            Artifact(kind: .state, mediaType: "application/octet-stream",
                     data: Data(count: Framing.maxPayloadBytes + 1))
        ])
        await #expect(throws: ExporterError.self) {
            try await exporter.export(record)
        }
    }
}
