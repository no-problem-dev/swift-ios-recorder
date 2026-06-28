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

    /// TCP リスナーを初期化する。`start()` を呼ぶまで待ち受けは始まらない。
    ///
    /// - Parameters:
    ///   - serviceName: Bonjour 広告名。指定すると同一 LAN に `_iosrecorder._tcp` でサービスを広告し、
    ///     デバイス側から自動発見できるようになる。`nil` の場合は広告なし（IP 直打ち専用）。
    ///   - serviceType: Bonjour サービスタイプ。既定値 `_iosrecorder._tcp` を変える必要は通常ない。
    ///   - port: 待ち受けポート。`.any`（既定値）を指定すると OS が空きポートを選択し、
    ///     `start()` 後に `resolvedPort` で確認できる。
    ///   - codec: フレームの符号化・復号化を担う `RecordCodec`。既定値は `JSONRecordCodec`。
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

    /// 受信した `Record` を逐次返す `AsyncThrowingStream`。
    ///
    /// ストリームは以下の条件で終了する:
    /// - `stop()` を呼び出すと正常終了（`finish()`）する。
    /// - リスナーが障害状態（`.failed`）に遷移すると、その `NWError` を投げてエラー終了する。
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
