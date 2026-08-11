import Foundation
import Network
import iOSRecorder

/// Accepts length-prefixed `Record` frames over TCP from a device on the same LAN.
///
/// Nothing is advertised until `serviceName` is supplied, so a receiver created without one is
/// reachable only by explicit host and port — which is also how tests avoid the local network
/// permission prompt that advertising triggers.
public final class BonjourReceiver: @unchecked Sendable {
    private let listener: NWListener
    private let codec: any RecordCodec
    private let queue = DispatchQueue(label: "iosrecorder.receiver")
    private let lock = NSLock()
    private var readyContinuation: CheckedContinuation<Void, any Error>?
    private var didSignalReady = false
    private let stream: AsyncThrowingStream<Record, any Error>
    private let continuation: AsyncThrowingStream<Record, any Error>.Continuation

    /// Builds the TCP listener without binding it; nothing is accepted until `start()` runs.
    ///
    /// - Parameters:
    ///   - serviceName: Name to advertise the listener under. Supplying it publishes the service on
    ///     the local network so devices can discover it; `nil` publishes nothing and the device has
    ///     to be given the host and port directly.
    ///   - serviceType: Bonjour service type. Both ends default to `_iosrecorder._tcp`, so changing
    ///     it here means changing it on the exporter too.
    ///   - port: Port to bind. `.any` lets the OS pick a free one, readable from `resolvedPort`
    ///     once `start()` has returned.
    ///   - codec: Wire format for frames. Must match the exporter's codec or every frame is dropped.
    public init(
        serviceName: String? = nil,
        serviceType: String = "_iosrecorder._tcp",
        port: NWEndpoint.Port = .any,
        codec: any RecordCodec = JSONRecordCodec()
    ) throws {
        self.listener = try NWListener(using: .tcp, on: port)
        if let serviceName {
            listener.service = NWListener.Service(name: serviceName, type: serviceType)
        }
        self.codec = codec
        var cont: AsyncThrowingStream<Record, any Error>.Continuation!
        self.stream = AsyncThrowingStream { cont = $0 }
        self.continuation = cont

        listener.stateUpdateHandler = { [weak self] state in self?.handleState(state) }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    }

    /// Every frame that decodes, in arrival order.
    ///
    /// A frame that fails to decode is dropped without a trace: it does not appear here and does
    /// not end the sequence, so a codec mismatch looks exactly like a silent sender.
    ///
    /// The sequence ends when:
    /// - `stop()` is called, which finishes it normally.
    /// - The listener fails, which throws the underlying `NWError`.
    ///
    /// All callers share one sequence, so two iterations split the frames between them rather than
    /// each seeing every frame.
    public func records() -> AsyncThrowingStream<Record, any Error> { stream }

    /// Binds the listener and waits until it is ready, which is when the port becomes known.
    ///
    /// - Throws: The listener's `NWError` if it cannot bind — most often because the requested port
    ///   is already taken.
    public func start() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
            lock.lock()
            if didSignalReady { lock.unlock(); c.resume(); return }
            readyContinuation = c
            lock.unlock()
            listener.start(queue: queue)
        }
    }

    /// The bound port, or `nil` before `start()` has returned — the value a device needs when the
    /// listener was created with `.any` and no Bonjour name.
    public var resolvedPort: UInt16? { listener.port?.rawValue }

    /// Stops accepting new connections and finishes `records()` normally.
    ///
    /// Peers that are already connected are not disconnected here; their sockets stay open until
    /// the peer closes them or the process exits.
    public func stop() {
        listener.cancel()
        continuation.finish()
    }

    private func handleState(_ state: NWListener.State) {
        switch state {
        case .ready:
            signalReady(.success(()))
        case .failed(let error):
            signalReady(.failure(error))
            continuation.finish(throwing: error)
        default:
            break
        }
    }

    private func signalReady(_ result: Result<Void, any Error>) {
        lock.lock()
        let continuation = readyContinuation
        readyContinuation = nil
        didSignalReady = true
        lock.unlock()
        switch result {
        case .success: continuation?.resume()
        case .failure(let error): continuation?.resume(throwing: error)
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveFrame(on: connection)
    }

    private func receiveFrame(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] header, _, isComplete, error in
            guard let self else { return }
            if let header, header.count == 4 {
                let length = Framing.readLength(header)
                guard Framing.isAcceptableLength(length) else {
                    // An over-limit prefix means a corrupt or hostile peer. Hang up rather than
                    // allocate a buffer that big; other connections keep being served.
                    connection.cancel()
                    return
                }
                self.receivePayload(length: length, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            }
        }
    }

    private func receivePayload(length: Int, on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] payload, _, isComplete, error in
            guard let self else { return }
            if let payload, let record = try? self.codec.decode(payload) {
                self.continuation.yield(record)
            }
            if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receiveFrame(on: connection)
            }
        }
    }
}
