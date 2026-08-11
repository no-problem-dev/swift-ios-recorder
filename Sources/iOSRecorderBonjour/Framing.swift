import Foundation

/// The wire format both ends agree on: a 4-byte big-endian length, then that many payload bytes.
enum Framing {
    /// Largest payload one frame may carry. A 4-byte length can claim up to 4 GB, so without a cap
    /// a corrupt or hostile prefix would make the receiver allocate that much; real records are far
    /// smaller. Senders reject oversized records instead of connecting.
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

/// Resumes a `CheckedContinuation` at most once. Network framework state handlers fire repeatedly
/// — a ready connection that later fails calls back twice — and resuming twice traps.
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
