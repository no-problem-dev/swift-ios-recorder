import SwiftUI
import Combine

extension Notification.Name {
    static let recorderShake = Notification.Name("iOSRecorder.shake")
}

public extension View {
    /// Runs an action when the device is shaken; where UIKit is unavailable the view is returned untouched
    /// and the action never fires.
    func onShake(perform action: @escaping () -> Void) -> some View {
        #if canImport(UIKit)
        onReceive(NotificationCenter.default.publisher(for: .recorderShake)) { _ in action() }
        #else
        self
        #endif
    }
}
