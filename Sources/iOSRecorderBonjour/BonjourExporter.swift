import Foundation
import Network
import iOSRecorder

/// 記録を framed にして TCP で送る Exporter。
/// `init(serviceType:)` は Bonjour で Mac を発見、`init(host:port:)` は直結。
public struct BonjourExporter: Exporter {
    private enum Target: Sendable {
        case service(type: String)
        case hostPort(host: String, port: UInt16)
    }

    private let target: Target
    private let codec: any RecordCodec
    private let timeout: Duration

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

    public func export(_ record: Record) async throws {
        let payload = Framing.frame(try codec.encode(record))
        try await withTimeout(timeout) {
            let endpoint = try await resolveEndpoint()
            try await send(payload, to: endpoint)
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

    private func browseFirst(serviceType: String) async throws -> NWEndpoint {
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: NWParameters())
        let queue = DispatchQueue(label: "iosrecorder.browser")
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<NWEndpoint, any Error>) in
            let box = ResumeOnce(c)
            browser.browseResultsChangedHandler = { results, _ in
                if let first = results.first {
                    box.resume(returning: first.endpoint)
                    browser.cancel()
                }
            }
            browser.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    box.resume(throwing: error)
                    browser.cancel()
                }
            }
            browser.start(queue: queue)
        }
    }

    private func send(_ payload: Data, to endpoint: NWEndpoint) async throws {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let queue = DispatchQueue(label: "iosrecorder.exporter")
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
            let box = ResumeOnce(c)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: payload, completion: .contentProcessed { error in
                        if let error { box.resume(throwing: error) } else { box.resume(returning: ()) }
                        connection.cancel()
                    })
                case .failed(let error):
                    box.resume(throwing: error)
                    connection.cancel()
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }
}

func withTimeout<T: Sendable>(_ duration: Duration, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw ExporterError.transportFailed("timeout")
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
