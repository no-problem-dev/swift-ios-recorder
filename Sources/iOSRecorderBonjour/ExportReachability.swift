import Foundation
import Network
import Observation

/// Polls, every few seconds, for a receiver that this device can actually reach — the signal a
/// debug UI shows before the user bothers to capture anything.
///
/// Each poll uses a throwaway browser rather than one long-lived one: a browser started before
/// local network permission was granted can miss the service and never recover, and this is the
/// same approach the exporter takes.
@MainActor
@Observable
public final class ExportReachability {
    /// Whether the last poll both found a receiver and opened a TCP connection to it. Stays
    /// `false` until `start()` is called, and while local network permission is denied.
    public private(set) var isReachable = false
    private let serviceType: String
    private var task: Task<Void, Never>?

    /// - Parameter serviceType: Service type to look for. Must match the type the receiver
    ///   advertises, otherwise `isReachable` stays `false` forever.
    public init(serviceType: String = "_iosrecorder._tcp") {
        self.serviceType = serviceType
    }

    /// Begins polling, or does nothing if already polling. Polling backs off to every 4 seconds
    /// once a receiver is found and tightens to every 2 seconds while none is.
    public func start() {
        guard task == nil else { return }
        let serviceType = serviceType
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let found = await Self.probe(serviceType)
                self?.isReachable = found
                try? await Task.sleep(for: .seconds(found ? 4 : 2))
            }
        }
    }

    /// Stops polling and resets `isReachable` to `false`. Call it explicitly — the polling task
    /// is not tied to this object's lifetime and keeps running if it is only released.
    public func stop() {
        task?.cancel()
        task = nil
        isReachable = false
    }

    /// One poll: discovery followed by a real TCP connection. Discovery alone is not enough —
    /// over tethering a stale advertisement is still visible after the receiver is unreachable,
    /// which would show green while every export fails.
    private static func probe(_ serviceType: String) async -> Bool {
        guard let endpoint = await browseOne(serviceType) else { return false }
        return await canConnect(to: endpoint)
    }

    /// First endpoint a throwaway browser sees, or `nil` after 1.5 seconds. The deadline is what
    /// makes a denied permission — which leaves the browser waiting rather than failing — resolve.
    private static func browseOne(_ serviceType: String) async -> NWEndpoint? {
        (try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NWEndpoint?, any Error>) in
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: NWParameters())
            let box = ResumeOnce(continuation)
            browser.browseResultsChangedHandler = { results, _ in
                if let first = results.first {
                    box.resume(returning: first.endpoint)
                    browser.cancel()
                }
            }
            browser.stateUpdateHandler = { state in
                if case .failed = state {
                    box.resume(returning: nil)
                    browser.cancel()
                }
            }
            browser.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                box.resume(returning: nil)
                browser.cancel()
            }
        }) ?? nil
    }

    /// Whether a TCP connection to the endpoint reaches `.ready` within 1.5 seconds. A connection
    /// that is merely still waiting counts as unreachable.
    private static func canConnect(to endpoint: NWEndpoint) async -> Bool {
        (try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, any Error>) in
            let connection = NWConnection(to: endpoint, using: .tcp)
            let box = ResumeOnce(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    box.resume(returning: true)
                    connection.cancel()
                case .failed, .cancelled:
                    box.resume(returning: false)
                    connection.cancel()
                default:
                    break
                }
            }
            connection.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                box.resume(returning: false)
                connection.cancel()
            }
        }) ?? false
    }
}
