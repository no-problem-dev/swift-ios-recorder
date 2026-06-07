import Foundation
import Network
import iOSRecorder

/// Mac 側で TCP を待ち受け、iPhone からの framed な記録を受け取る Receiver。
/// `serviceName` を指定すると Bonjour でも広告する（同一 LAN 自動発見）。
public final class BonjourReceiver: @unchecked Sendable {
    private let listener: NWListener
    private let codec: any RecordCodec
    private let queue = DispatchQueue(label: "iosrecorder.receiver")
    private let lock = NSLock()
    private var readyContinuation: CheckedContinuation<Void, any Error>?
    private var didSignalReady = false
    private let stream: AsyncThrowingStream<Record, any Error>
    private let continuation: AsyncThrowingStream<Record, any Error>.Continuation

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

    public func records() -> AsyncThrowingStream<Record, any Error> { stream }

    /// 待ち受けが始まり port が確定するまで待つ。
    public func start() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
            lock.lock()
            if didSignalReady { lock.unlock(); c.resume(); return }
            readyContinuation = c
            lock.unlock()
            listener.start(queue: queue)
        }
    }

    public var resolvedPort: UInt16? { listener.port?.rawValue }

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
                    // 上限超の長さプレフィックス = 壊れたデータか悪意あるピア。即切断。
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
