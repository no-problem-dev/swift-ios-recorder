import Foundation
import ObjectiveC

/// 全 URLSession 通信のライブモニタ。`start()` で傍受を開始し、ログは `store` に積まれる。
/// キャプチャ（Record）とは無関係の独立サブシステム。
@MainActor
public final class NetworkMonitor {
    public let store: NetworkLogStore
    private let ignoredHosts: [String]
    nonisolated(unsafe) private static var didSwizzle = false

    public init(ignoredHosts: [String] = [], capacity: Int = 500) {
        self.store = NetworkLogStore(capacity: capacity)
        self.ignoredHosts = ignoredHosts
    }

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
    /// swizzle 後はこのメソッドが getter になり、内部で元の getter を呼ぶ。
    @objc func iosrecorder_protocolClasses() -> [AnyClass]? {
        var classes = self.iosrecorder_protocolClasses() ?? []
        let target = ObjectIdentifier(RecordingURLProtocol.self)
        if !classes.contains(where: { ObjectIdentifier($0) == target }) {
            classes.insert(RecordingURLProtocol.self, at: 0)
        }
        return classes
    }
}
