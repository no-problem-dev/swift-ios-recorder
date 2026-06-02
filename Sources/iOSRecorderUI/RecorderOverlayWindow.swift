#if canImport(UIKit)
import SwiftUI
import UIKit
import iOSRecorder

/// ボタンの矩形だけタッチを拾い、それ以外はアプリ本体へ通すウィンドウ。
/// シート表示中（presentedViewController あり）は通常通り全面で当たり判定する。
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

/// アプリの windowScene を捕まえて、フロートボタン専用の非 key ウィンドウを 1 度だけ載せる。
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

        func install(in scene: UIWindowScene, controller: RecorderController) {
            guard window == nil else { return }
            let region = HitRegionBox()
            let window = PassthroughWindow(windowScene: scene, hitRegion: region)
            window.windowLevel = .alert + 1
            window.accessibilityIdentifier = RecorderWindowMarker.overlayIdentifier
            let host = UIHostingController(rootView: FloatingButtons(controller: controller, hitRegion: region))
            host.view.backgroundColor = .clear
            window.rootViewController = host
            window.isHidden = false   // 表示するが makeKey しない → アプリ本体が key window のまま
            self.window = window
        }
    }
}

private final class InstallerView: UIView {
    var onAttach: ((UIWindowScene) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let scene = window?.windowScene { onAttach?(scene) }
    }
}
#endif
