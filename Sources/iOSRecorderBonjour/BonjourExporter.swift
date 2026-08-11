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
    /// A deadline is configured but cannot cut a stalled attempt short: the call returns only once
    /// Network reports success or failure. With no receiver running, or with local network
    /// permission denied, the browser waits instead of failing and this call does not come back —
    /// so callers that must stay responsive should not await it on a path a person is watching.
    ///
    /// - Throws: `ExporterError.payloadTooLarge` when the encoded record exceeds the 64 MB frame
    ///   limit, thrown before any connection is attempted; `ExporterError.transportFailed` for an
    ///   unusable port; otherwise the underlying `NWError`.
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

    /// Sends the frame and reports the concrete address it reached, which is what gets cached —
    /// a Bonjour endpoint resolves to a different host each time, so caching it would be useless.
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

private func withTimeout<T: Sendable>(_ duration: Duration, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
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
