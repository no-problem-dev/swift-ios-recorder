import SwiftUI
import Combine

extension Notification.Name {
    static let recorderShake = Notification.Name("iOSRecorder.shake")
}

public extension View {
    /// シェイク検知でアクションを発火（iOS のみ。他プラットフォームでは no-op）。
    func onShake(perform action: @escaping () -> Void) -> some View {
        #if canImport(UIKit)
        onReceive(NotificationCenter.default.publisher(for: .recorderShake)) { _ in action() }
        #else
        self
        #endif
    }
}
