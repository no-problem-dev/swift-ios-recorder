import SwiftUI

public extension View {
    /// Names a screen, so captures taken while it is showing carry that name in the list and in search.
    /// Use it inside `.recorder(_:)`: outside, the controller is missing from the environment and the
    /// name is dropped without a warning.
    func recorderScreen(_ name: String) -> some View {
        modifier(RecorderScreenModifier(name: name))
    }
}

struct RecorderScreenModifier: ViewModifier {
    let name: String
    @Environment(RecorderController.self) private var controller: RecorderController?

    func body(content: Content) -> some View {
        content.onAppear { controller?.currentScreen = name }
    }
}
