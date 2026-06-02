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

    /// 一度通った具体アドレス(host:port)を覚えておく箱。mDNS のハイハイや
    /// IPv6 link-local 誤選択でコケた時の取りこぼしを減らす（テザリング耐性）。
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

    public func export(_ record: Record) async throws {
        let payload = Framing.frame(try codec.encode(record))
        try await withTimeout(timeout) {
            // 1) 直近に通った具体アドレスを最優先で試す（ブラウズ不要 → 速くて安定）。
            if let cached = await cache.endpoint {
                do {
                    let resolved = try await send(payload, to: cached)
                    await cache.set(resolved)
                    return
                } catch {
                    await cache.invalidate()   // 陳腐化 → 発見し直す
                }
            }
            // 2) Bonjour で発見 → 送信 → 通った具体アドレスをキャッシュ。
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

    /// 送信し、実際に到達した具体アドレス(host:port)を返す（次回キャッシュ用）。
    private func send(_ payload: Data, to endpoint: NWEndpoint) async throws -> NWEndpoint {
        let connection = NWConnection(to: endpoint, using: .tcp)
        let queue = DispatchQueue(label: "iosrecorder.exporter")
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<NWEndpoint, any Error>) in
            let box = ResumeOnce(c)
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
