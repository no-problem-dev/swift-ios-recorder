#if canImport(UIKit)
import SwiftUI
import UIKit
import DesignSystem
import iOSRecorder

/// Takes touches only inside the buttons' rectangle and lets every other touch fall through to the app.
/// While it presents a sheet it hit-tests across its whole area again, so the panel stays usable.
final class PassthroughWindow: UIWindow {
    let hitRegion: HitRegionBox

    init(windowScene: UIWindowScene, hitRegion: HitRegionBox) {
        self.hitRegion = hitRegion
        super.init(windowScene: windowScene)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if rootViewController?.presentedViewController != nil {
            return super.hitTest(point, with: event)
        }
        return hitRegion.frame.contains(point) ? super.hitTest(point, with: event) : nil
    }
}

/// Waits for the app's window scene, then installs the buttons' own window exactly once and keeps it
/// for the lifetime of the scene.
struct OverlayInstaller: UIViewRepresentable {
    let controller: RecorderController

    func makeUIView(context: Context) -> UIView {
        let view = InstallerView()
        view.onAttach = { scene in
            context.coordinator.install(in: scene, controller: controller)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var window: PassthroughWindow?

        @MainActor
        func install(in scene: UIWindowScene, controller: RecorderController) {
            guard window == nil else { return }
            let region = HitRegionBox()
            let window = PassthroughWindow(windowScene: scene, hitRegion: region)
            window.windowLevel = .alert + 1
            window.accessibilityIdentifier = RecorderWindowMarker.overlayIdentifier
            let host = UIHostingController(rootView: FloatingButtons(controller: controller, hitRegion: region).theme(controller.theme))
            host.view.backgroundColor = .clear
            window.rootViewController = host
            window.isHidden = false   // shown but never made key, so the app keeps the key window screenshots look for
            self.window = window
        }
    }
}

private final class InstallerView: UIView {
    var onAttach: (@MainActor (UIWindowScene) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let scene = window?.windowScene { onAttach?(scene) }
    }
}
#endif
