import Foundation

/// Lets a debug UI show how many captures are still waiting to be sent, and retry or abandon them.
public protocol OutboxDraining: Sendable {
    @discardableResult
    func drain() async -> Int
    func pendingCount() async -> Int
    /// Throws away everything queued without sending it.
    /// - Returns: How many were waiting before the wipe.
    @discardableResult
    func discardAll() async -> Int
}

/// Wraps another exporter and parks whatever fails to send, so a later pass can deliver it.
///
/// This is what carries captures across a flaky tethered link, a stopped receiver, or an app relaunch — but only
/// as far as the outbox store reaches, so an in-memory outbox loses its queue when the process ends.
public actor OutboxExporter: Exporter, OutboxDraining {
    private let inner: any Exporter
    private let outbox: any RecordStore
    private let scanLimit: Int
    public nonisolated let label: String

    /// - Parameters:
    ///   - inner: The exporter that actually sends, such as the Bonjour one.
    ///   - outbox: Where unsent captures wait. Back it with disk if the queue must survive a relaunch.
    ///   - scanLimit: How many captures one drain or count pass looks at; anything beyond it is invisible to both.
    public init(wrapping inner: any Exporter, outbox: any RecordStore, scanLimit: Int = 10_000) {
        self.inner = inner
        self.outbox = outbox
        self.scanLimit = max(1, scanLimit)
        self.label = inner.label
    }

    public func export(_ record: Record) async throws {
        do {
            try await inner.export(record)
            try? await outbox.delete(record.id)   // Sent, so drop any copy an earlier failure left behind
        } catch ExporterError.payloadTooLarge(let bytes) {
            // Never queue what can never be sent; it would sit at the head and block everything behind it.
            throw ExporterError.payloadTooLarge(bytes: bytes)
        } catch {
            try? await outbox.save(record)         // Park it and let a later drain deliver it
            throw error
        }
    }

    /// Resends what is parked, oldest first — call it when the receiver comes back or the app starts.
    ///
    /// The first transient failure ends the pass, which keeps the order intact and spares a run of pointless
    /// retries; captures too large to ever send are deleted and the pass carries on.
    /// - Returns: How many captures left the outbox.
    @discardableResult
    public func drain() async -> Int {
        let summaries = ((try? await outbox.query(RecordQuery(limit: scanLimit))) ?? [])
            .sorted { $0.recordedAt < $1.recordedAt }
        var sent = 0
        for summary in summaries {
            guard let record = try? await outbox.fetch(summary.id) else { continue }
            do {
                try await inner.export(record)
                try? await outbox.delete(record.id)
                sent += 1
            } catch ExporterError.payloadTooLarge {
                try? await outbox.delete(record.id)
            } catch {
                break
            }
        }
        return sent
    }

    /// How many captures are parked, counted no further than `scanLimit` — a longer queue reports as exactly that.
    public func pendingCount() async -> Int {
        ((try? await outbox.query(RecordQuery(limit: scanLimit))) ?? []).count
    }

    /// Empties the outbox without sending, for when old failures are no longer worth delivering.
    /// - Returns: The count observed before the wipe, which `scanLimit` can cap below the true figure.
    @discardableResult
    public func discardAll() async -> Int {
        let count = await pendingCount()
        try? await outbox.removeAll()
        return count
    }
}
