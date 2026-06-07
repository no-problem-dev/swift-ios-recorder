import Foundation

/// 未送分を再送・観測・破棄できる能力。UI から pending を見せたり drain したりするためのポート。
public protocol OutboxDraining: Sendable {
    @discardableResult
    func drain() async -> Int
    func pendingCount() async -> Int
    /// 未送分を送らずにすべて破棄する。破棄した件数を返す。
    @discardableResult
    func discardAll() async -> Int
}

/// 別の Exporter を包み、送信失敗分を永続ストアに退避して後で再送する合成 Exporter。
/// テザリングの不安定さ・受信機停止・アプリ再起動をまたいで「取りこぼしゼロ」を保証する。
/// core のポート（Exporter / RecordStore）だけで構成されるので core に置ける。
public actor OutboxExporter: Exporter, OutboxDraining {
    private let inner: any Exporter
    private let outbox: any RecordStore
    private let scanLimit: Int
    public nonisolated let label: String

    /// - Parameters:
    ///   - inner: 実際に送る Exporter（例: BonjourExporter）。
    ///   - outbox: 未送分の退避先（例: iOS 上の FileRecordStore）。
    ///   - scanLimit: drain / pendingCount が一度に走査する上限件数。
    public init(wrapping inner: any Exporter, outbox: any RecordStore, scanLimit: Int = 10_000) {
        self.inner = inner
        self.outbox = outbox
        self.scanLimit = max(1, scanLimit)
        self.label = inner.label
    }

    public func export(_ record: Record) async throws {
        do {
            try await inner.export(record)
            try? await outbox.delete(record.id)   // 成功したら退避分も掃除
        } catch ExporterError.payloadTooLarge(let bytes) {
            // 再試行しても永遠に送れないものは退避しない（outbox の先頭詰まり防止）。
            throw ExporterError.payloadTooLarge(bytes: bytes)
        } catch {
            try? await outbox.save(record)         // 失敗は退避し、再送に委ねる
            throw error
        }
    }

    /// 退避済みを古い順に再送する。到達回復時・起動時に呼ぶ。送れた件数を返す。
    /// 一時的な失敗なら以降は次の機会に回す（順序と無駄打ちの抑制）。
    /// 恒久的に送れないもの（payloadTooLarge）は破棄して次へ進む。
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

    /// 未送（退避中）の件数。
    public func pendingCount() async -> Int {
        ((try? await outbox.query(RecordQuery(limit: scanLimit))) ?? []).count
    }

    /// 未送分を送らずにすべて破棄する。古い送信失敗分が要らなくなった時の掃除用。
    @discardableResult
    public func discardAll() async -> Int {
        let count = await pendingCount()
        try? await outbox.removeAll()
        return count
    }
}
