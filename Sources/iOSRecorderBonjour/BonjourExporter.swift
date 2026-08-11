import Foundation
import Network
import iOSRecorder

/// Sends a record to a receiver on the same LAN as one length-prefixed TCP frame.
///
/// `init(serviceType:)` finds the receiver by browsing the local network, which on iOS requires
/// local network permission; `init(host:port:)` skips browsing and dials a known address, which is
/// what tests and tethered setups use.
public struct BonjourExporter: Exporter {
    private enum Target: Sendable {
        case service(type: String)
        case hostPort(host: String, port: UInt16)
    }

    /// Remembers the concrete host and port that last worked, so a flaky mDNS answer or a bad
    /// IPv6 link-local pick costs at most one record instead of every record.
    actor EndpointCache {
        private(set) var endpoint: NWEndpoint?
        func set(_ value: NWEndpoint) { endpoint = value }
        func invalidate() { endpoint = nil }
    }

    private let target: Target
    private let codec: any RecordCodec
    private let timeout: Duration
    private let cache = EndpointCache()

    public init(
        serviceType: String = "_iosrecorder._tcp",
        codec: any RecordCodec = JSONRecordCodec(),
        timeout: Duration = .seconds(5)
    ) {
        self.target = .service(type: serviceType)
        self.codec = codec
        self.timeout = timeout
    }

    public init(
        host: String,
        port: UInt16,
        codec: any RecordCodec = JSONRecordCodec(),
        timeout: Duration = .seconds(5)
    ) {
        self.target = .hostPort(host: host, port: port)
        self.codec = codec
        self.timeout = timeout
    }

    /// Encodes the record and writes it to the receiver as a single frame.
    ///
    /// Returning without throwing means the bytes were handed to TCP — not that the receiver
    /// decoded or stored them. A frame the receiver cannot decode is dropped on its side and
    /// still counts as delivered here.
    ///
    /// The `timeout` bounds the whole attempt. With no receiver running, on the wrong network, or
    /// with local network permission denied, Network reports neither success nor failure — it
    /// waits — so the deadline is the only thing that ends those attempts, and it throws.
    ///
    /// - Throws: `ExporterError.payloadTooLarge` when the encoded record exceeds the 64 MB frame
    ///   limit, thrown before any connection is attempted; `ExporterError.transportFailed` for an
    ///   unusable port and for the deadline; otherwise the underlying `NWError`.
    public func export(_ record: Record) async throws {
        let encoded = try codec.encode(record)
        guard encoded.count <= Framing.maxPayloadBytes else {
            throw ExporterError.payloadTooLarge(bytes: encoded.count)
        }
        let payload = Framing.frame(encoded)
        try await withTimeout(timeout) {
            // 1) Try the address that worked last time first: no browsing, so it is fast and steady.
            if let cached = await cache.endpoint {
                do {
                    let resolved = try await send(payload, to: cached)
                    await cache.set(resolved)
                    return
                } catch {
                    await cache.invalidate()   // Gone stale, so discover again.
                }
            }
            // 2) Discover, send, then remember the address that actually worked.
            let endpoint = try await resolveEndpoint()
            let resolved = try await send(payload, to: endpoint)
            await cache.set(resolved)
        }
    }

    private func resolveEndpoint() async throws -> NWEndpoint {
        switch target {
        case .hostPort(let host, let port):
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                throw ExporterError.transportFailed("invalid port \(port)")
            }
            return .hostPort(host: .init(host), port: nwPort)
        case .service(let type):
            return try await browseFirst(serviceType: type)
        }
    }

    /// Waits for the first receiver to advertise itself.
    ///
    /// Browsing sits in `.waiting` rather than failing when there is no receiver on the LAN, the
    /// network is the wrong one, or local network permission was denied — so the only thing that
    /// ends this wait is the caller's deadline. Cancellation therefore has to reach the browser:
    /// without it every timed-out export strands one `NWBrowser`.
    private func browseFirst(serviceType: String) async throws -> NWEndpoint {
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: NWParameters())
        let queue = DispatchQueue(label: "iosrecorder.browser")
        let cancelled = CancelOnce { browser.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<NWEndpoint, any Error>) in
                let box = ResumeOnce(c)
                cancelled.onCancel { box.resume(throwing: CancellationError()) }
                browser.browseResultsChangedHandler = { results, _ in
                    if let first = results.first {
                        box.resume(returning: first.endpoint)
                        browser.cancel()
                    }
                }
                browser.stateUpdateHandler = { state in
                    switch state {
                    case .failed(let error):
                        box.resume(throwing: error)
                        browser.cancel()
                    case .cancelled:
                        box.resume(throwing: CancellationError())
                    default:
                        break
                    }
                }
                browser.start(queue: queue)
            }
        } onCancel: {
            cancelled.cancel()
        }
    }

    /// Sends the frame and reports the concrete address it reached, which is what gets cached —
    /// a Bonjour endpoint resolves to a different host each time, so caching it would be useless.
    ///
    /// A receiver that is not answering leaves the connection in `.waiting`, which is neither
    /// ready nor failed, so this ends on the caller's deadline. Cancellation has to reach the
    /// connection for the same reason it has to reach the browser.
    private func send(_ payload: Data, to endpoint: NWEndpoint) async throws -> NWEndpoint {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let queue = DispatchQueue(label: "iosrecorder.exporter")
        let cancelled = CancelOnce { connection.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<NWEndpoint, any Error>) in
                let box = ResumeOnce(c)
                cancelled.onCancel { box.resume(throwing: CancellationError()) }
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        let resolved = connection.currentPath?.remoteEndpoint ?? endpoint
                        connection.send(content: payload, completion: .contentProcessed { error in
                            if let error { box.resume(throwing: error) } else { box.resume(returning: resolved) }
                            connection.cancel()
                        })
                    case .failed(let error):
                        box.resume(throwing: error)
                        connection.cancel()
                    case .cancelled:
                        box.resume(throwing: CancellationError())
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
            }
        } onCancel: {
            cancelled.cancel()
        }
    }
}

/// Tears down a Network object once, from whichever side gets there first.
///
/// Cancellation can arrive before the continuation exists — the task may already be cancelled when
/// the handler is installed — so the teardown is recorded and replayed to whoever registers next.
/// Without that, a cancellation that lands in the gap is lost and the caller waits forever.
private final class CancelOnce: @unchecked Sendable {
    private let lock = NSLock()
    private let teardown: @Sendable () -> Void
    private var resume: (@Sendable () -> Void)?
    private var cancelled = false

    init(_ teardown: @escaping @Sendable () -> Void) {
        self.teardown = teardown
    }

    func onCancel(_ resume: @escaping @Sendable () -> Void) {
        lock.lock()
        if cancelled {
            lock.unlock()
            resume()
            return
        }
        self.resume = resume
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        guard !cancelled else { return lock.unlock() }
        cancelled = true
        let resume = self.resume
        self.resume = nil
        lock.unlock()
        teardown()
        resume?()
    }
}

/// Runs `operation`, giving up on it after `duration`.
///
/// The race is deliberately unstructured. A task group awaits every child before it returns, so an
/// operation parked in a continuation that ignores cancellation holds the caller past the deadline
/// forever — the deadline fires and nobody hears it. Here whichever finishes first resumes the
/// caller directly, and the loser is cancelled on the way out; an operation deaf to that
/// cancellation is abandoned rather than waited on.
///
/// - Throws: `ExporterError.transportFailed("timeout")` when the deadline wins, `CancellationError`
///   when the calling task is cancelled, otherwise whatever `operation` threw.
func withTimeout<T: Sendable>(_ duration: Duration, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    let race = FirstToFinish<T>()
    let work = Task {
        do { race.settle(.success(try await operation())) } catch { race.settle(.failure(error)) }
    }
    let deadline = Task {
        try? await Task.sleep(for: duration)
        race.settle(.failure(ExporterError.transportFailed("timeout")))
    }
    defer {
        work.cancel()
        deadline.cancel()
    }
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { race.attach($0) }
    } onCancel: {
        race.settle(.failure(CancellationError()))
    }
}

/// Hands the first of several racing results to one continuation, and only ever once.
///
/// A result that arrives before anyone is waiting is held until `attach` supplies the continuation,
/// so a race that is already decided cannot strand the caller.
private final class FirstToFinish<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?
    private var result: Result<T, any Error>?
    private var delivered = false

    func attach(_ continuation: CheckedContinuation<T, any Error>) {
        lock.lock()
        if let result, !delivered {
            delivered = true
            lock.unlock()
            continuation.resume(with: result)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func settle(_ result: Result<T, any Error>) {
        lock.lock()
        guard !delivered else { return lock.unlock() }
        if let continuation {
            delivered = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
            return
        }
        if self.result == nil { self.result = result }
        lock.unlock()
    }
}
