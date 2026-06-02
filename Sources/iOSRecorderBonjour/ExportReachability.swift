import Foundation
import Network
import Observation

/// 同一 LAN に Mac の受信機（_iosrecorder._tcp）が居るかを定期的に探索する。
/// 永続ブラウザは権限付与前などに取りこぼして復帰しないことがあるため、
/// 送信側 Exporter と同じ「都度使い捨てブラウザで探索」を周期実行する。
@MainActor
@Observable
public final class ExportReachability {
    public private(set) var isReachable = false
    private let serviceType: String
    private var task: Task<Void, Never>?

    public init(serviceType: String = "_iosrecorder._tcp") {
        self.serviceType = serviceType
    }

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

    public func stop() {
        task?.cancel()
        task = nil
        isReachable = false
    }

    /// 使い捨てブラウザで 1 回だけ探索し、サービスが見つかれば true。
    private static func probe(_ serviceType: String) async -> Bool {
        (try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, any Error>) in
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: NWParameters())
            let box = ResumeOnce(continuation)
            browser.browseResultsChangedHandler = { results, _ in
                if !results.isEmpty {
                    box.resume(returning: true)
                    browser.cancel()
                }
            }
            browser.stateUpdateHandler = { state in
                if case .failed = state {
                    box.resume(returning: false)
                    browser.cancel()
                }
            }
            browser.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                box.resume(returning: false)
                browser.cancel()
            }
        }) ?? false
    }
}
