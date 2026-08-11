import SwiftUI
import DesignSystem
import iOSRecorder

public extension View {
    /// Attaches the floating buttons, the debug panel and shake handling; keep the call inside DEBUG builds.
    /// The buttons stay hidden until a shake toggles them: 📷 takes a capture, 🐞 opens the panel.
    func recorder(_ controller: RecorderController) -> some View {
        modifier(RecorderModifier(controller: controller))
    }
}

struct RecorderModifier: ViewModifier {
    @Bindable var controller: RecorderController

    func body(content: Content) -> some View {
        placement(content)
            .onShake {
                withAnimation(.snappy) { controller.isOverlayVisible.toggle() }
            }
    }

    @ViewBuilder
    private func placement(_ content: Content) -> some View {
        #if canImport(UIKit)
        // The buttons live in a separate window: out of every screenshot, out of the app's touch path
        // The controller goes into the environment so .recorderScreen(_:) can find it
        content
            .environment(controller)
            .background(OverlayInstaller(controller: controller))
        #else
        content
            .environment(controller)
            .overlay { FloatingButtons(controller: controller).theme(controller.theme) }
        #endif
    }
}
