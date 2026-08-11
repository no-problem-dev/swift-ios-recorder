import Foundation
import Testing
import iOSRecorder
import iOSRecorderTestSupport
@testable import iOSRecorderBonjour

/// Records what an asynchronous call did, so a test can watch it from the outside without
/// awaiting it — the only way to observe a call that may never come back.
private actor Landing {
    private(set) var settled = false
    private(set) var error: (any Error)?

    func record(_ error: (any Error)?) {
        self.error = error
        settled = true
    }

    /// Waits for the call to come back, giving up after `within`. Returns whether it landed.
    func wait(within limit: Duration) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while !settled, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return settled
    }
}

@Suite struct TimeoutTests {
    /// The deadline has to win against an operation that is parked and deaf to cancellation —
    /// which is what `NWBrowser` waiting for a receiver that is not on the LAN amounts to.
    ///
    /// A task group cannot do this: it awaits every child before returning, so the parked child
    /// holds the caller past the deadline forever.
    @Test func deadlineFiresWhileOperationIsParkedForever() async {
        let landing = Landing()
        Task {
            do {
                try await withTimeout(.milliseconds(200)) {
                    try await withCheckedThrowingContinuation { (_: CheckedContinuation<Void, any Error>) in
                        // Never resumed, and no cancellation handler.
                    }
                }
                await landing.record(nil)
            } catch {
                await landing.record(error)
            }
        }

        #expect(await landing.wait(within: .seconds(4)), "withTimeout never returned after its deadline elapsed")
        let error = await landing.error
        #expect(error is ExporterError, "expected the timeout error, got \(String(describing: error))")
    }

    /// The deadline also has to cancel the operation as it leaves, or every timed-out export
    /// strands the browser and connection it opened.
    @Test func deadlineCancelsTheOperation() async {
        let cancelled = Landing()
        Task {
            _ = try? await withTimeout(.milliseconds(200)) {
                await withTaskCancellationHandler {
                    try? await Task.sleep(for: .seconds(30))
                } onCancel: {
                    Task { await cancelled.record(nil) }
                }
            }
        }

        #expect(await cancelled.wait(within: .seconds(4)), "the timed-out operation was never cancelled")
    }

    /// An operation that finishes inside the deadline returns its own value, not a timeout.
    @Test func operationResultPassesThroughWhenItBeatsTheDeadline() async throws {
        let value = try await withTimeout(.seconds(5)) { 42 }
        #expect(value == 42)
    }

    /// An operation that throws inside the deadline surfaces its own error, not a timeout.
    @Test func operationErrorPassesThroughWhenItBeatsTheDeadline() async {
        await #expect(throws: ExporterError.payloadTooLarge(bytes: 1)) {
            try await withTimeout(.seconds(5)) { throw ExporterError.payloadTooLarge(bytes: 1) }
        }
    }

    /// End to end: a receiver that never answers must fail the export on the deadline rather than
    /// park the caller. 192.0.2.1 is TEST-NET-1, reserved so that nothing ever replies.
    @Test func exportToAnUnreachableReceiverFailsOnTheDeadline() async {
        let landing = Landing()
        let exporter = BonjourExporter(host: "192.0.2.1", port: 9, timeout: .milliseconds(300))
        let record = RecordFixtures.make(id: RecordID(rawValue: "unreachable"))
        Task {
            do {
                try await exporter.export(record)
                await landing.record(nil)
            } catch {
                await landing.record(error)
            }
        }

        #expect(await landing.wait(within: .seconds(6)), "export never returned for an unreachable receiver")
        #expect(await landing.error != nil, "an export that reached nobody reported success")
    }
}
