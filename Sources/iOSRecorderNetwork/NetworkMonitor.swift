import Foundation
import ObjectiveC

/// Watches every `URLSession` request the app makes and files them in `store`.
///
/// Runs on its own, independent of capturing: traffic accumulates whether or not a record is ever
/// taken. Interception begins at `start()` and does not end — there is no counterpart that unhooks
/// it, so treat it as a debug-build-only switch that stays on for the life of the process.
@MainActor
public final class NetworkMonitor {
    public let store: NetworkLogStore
    private let ignoredHosts: [String]
    nonisolated(unsafe) private static var didSwizzle = false

    /// - Parameters:
    ///   - ignoredHosts: Hosts to leave alone, matched as substrings — `"example.com"` also skips
    ///     `api.example.com`. Use it for the app's own telemetry endpoint, which would otherwise
    ///     log itself.
    ///   - capacity: How many exchanges the buffer keeps before dropping the oldest.
    public init(ignoredHosts: [String] = [], capacity: Int = 500) {
        self.store = NetworkLogStore(capacity: capacity)
        self.ignoredHosts = ignoredHosts
    }

    /// Hooks the interceptor into both the shared session and any session built later from a
    /// configuration.
    ///
    /// The interceptor keeps only a weak reference to `store`, so this monitor has to be held for
    /// as long as traffic should be logged; release it and requests keep being intercepted while
    /// nothing is recorded. Starting a second monitor points the interceptor at the newer store.
    public func start() {
        RecordingURLProtocol.ignoredHosts = ignoredHosts
        RecordingURLProtocol.store = store
        URLProtocol.registerClass(RecordingURLProtocol.self)
        Self.swizzleProtocolClassesIfNeeded()
    }

    private static func swizzleProtocolClassesIfNeeded() {
        guard !didSwizzle else { return }
        didSwizzle = true
        guard
            let original = class_getInstanceMethod(
                URLSessionConfiguration.self,
                #selector(getter: URLSessionConfiguration.protocolClasses)
            ),
            let swizzled = class_getInstanceMethod(
                URLSessionConfiguration.self,
                #selector(URLSessionConfiguration.iosrecorder_protocolClasses)
            )
        else { return }
        method_exchangeImplementations(original, swizzled)
    }
}

extension URLSessionConfiguration {
    /// Stands in for the `protocolClasses` getter once the implementations have been exchanged, so
    /// the recursive-looking call here actually reaches the original getter. Sessions built from a
    /// custom configuration set their own protocol list and would otherwise skip the interceptor.
    @objc func iosrecorder_protocolClasses() -> [AnyClass]? {
        var classes = self.iosrecorder_protocolClasses() ?? []
        let target = ObjectIdentifier(RecordingURLProtocol.self)
        if !classes.contains(where: { ObjectIdentifier($0) == target }) {
            classes.insert(RecordingURLProtocol.self, at: 0)
        }
        return classes
    }
}
