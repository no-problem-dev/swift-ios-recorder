import Foundation

/// 4 バイトのビッグエンディアン長プレフィックス + payload。
enum Framing {
    /// 1 フレームの上限。壊れた/悪意ある長さプレフィックス（最大 4GB）で
    /// 受信側が巨大メモリ確保に突入しないための防壁。正常な記録はこれを大きく下回る。
    static let maxPayloadBytes = 64 * 1024 * 1024

    static func isAcceptableLength(_ length: Int) -> Bool {
        length > 0 && length <= maxPayloadBytes
    }

    static func frame(_ payload: Data) -> Data {
        let length = UInt32(payload.count)
        var out = Data(capacity: payload.count + 4)
        out.append(UInt8((length >> 24) & 0xFF))
        out.append(UInt8((length >> 16) & 0xFF))
        out.append(UInt8((length >> 8) & 0xFF))
        out.append(UInt8(length & 0xFF))
        out.append(payload)
        return out
    }

    static func readLength<D: DataProtocol>(_ header: D) -> Int {
        header.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
    }
}

/// CheckedContinuation を 1 度だけ resume するための小箱（Network のコールバックは複数回来る）。
final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let continuation: CheckedContinuation<T, any Error>

    init(_ continuation: CheckedContinuation<T, any Error>) {
        self.continuation = continuation
    }

    func resume(returning value: sending T) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(returning: value)
    }

    func resume(throwing error: any Error) {
        lock.lock(); defer { lock.unlock() }
        guard !done else { return }
        done = true
        continuation.resume(throwing: error)
    }
}
