import Foundation
import Network
import Observation

/// 同一 LAN に Mac の受信機（_iosrecorder._tcp）が居るかを定期的に探索する。
/// 永続ブラウザは権限付与前などに取りこぼして復帰しないことがあるため、
/// 送信側 Exporter と同じ「都度使い捨てブラウザで探索」を周期実行する。
@MainActor
@Observable
public final class ExportReachability {
    /// Mac 側の受信機へ TCP 接続が届くかどうか。`start()` を呼んだ後、定期的に更新される。
    public private(set) var isReachable = false
    private let serviceType: String
    private var task: Task<Void, Never>?

    /// 探索するサービスタイプを指定して初期化する。
    /// - Parameter serviceType: Bonjour サービスタイプ（既定値 `_iosrecorder._tcp`）。
    public init(serviceType: String = "_iosrecorder._tcp") {
        self.serviceType = serviceType
    }

    /// 定期探索を開始する。すでに開始済みの場合は何もしない（冪等）。
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

    /// 定期探索を停止し、`isReachable` を `false` にリセットする。
    public func stop() {
        task?.cancel()
        task = nil
        isReachable = false
    }

    /// 使い捨てブラウザで 1 回だけ探索し、サービスが見つかれば true。
    /// サービスを発見し、さらに実際に TCP 接続できるかまで確認して true。
    /// 「発見できる」だけでなく「届く」を緑の条件にする（テザリングでの誤緑を防ぐ）。
    private static func probe(_ serviceType: String) async -> Bool {
        guard let endpoint = await browseOne(serviceType) else { return false }
        return await canConnect(to: endpoint)
    }

    /// 使い捨てブラウザで最初のエンドポイントを 1 つ返す（1.5s タイムアウト）。
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

    /// 実際に TCP を 1 回張って `.ready` に到達できたら true（1.5s タイムアウト）。
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
