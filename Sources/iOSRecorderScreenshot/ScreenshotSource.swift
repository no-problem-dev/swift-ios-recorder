#if canImport(UIKit)
import UIKit
import iOSRecorder

/// 実行中のキーウィンドウを drawHierarchy でラスタライズする Source。
/// `ImageRenderer` と違い UIViewRepresentable のネイティブ要素も確実に写る。
public struct ScreenshotSource: Source {
    public let kind = ArtifactKind.screenshot
    private let scale: CGFloat

    /// - Parameter scale: 0 ならデバイススケール。縮小して送りたい時に指定。
    public init(scale: CGFloat = 0) {
        self.scale = scale
    }

    public func measure(_ context: RecordContext) async -> Artifact? {
        await MainActor.run {
            guard let window = Self.keyWindow() else { return nil }
            let format = UIGraphicsImageRendererFormat()
            if scale > 0 { format.scale = scale }
            let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
            let image = renderer.image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            guard let data = image.pngData() else { return nil }
            return Artifact.screenshot(pngData: data, attributes: [
                "width": "\(Int(window.bounds.width))",
                "height": "\(Int(window.bounds.height))"
            ])
        }
    }

    @MainActor
    static func keyWindow() -> UIWindow? {
        // 計器用オーバーレイウィンドウ（透明）は除外し、アプリ本体のウィンドウを撮る。
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { $0.accessibilityIdentifier != RecorderWindowMarker.overlayIdentifier }
        return windows.first(where: \.isKeyWindow)
            ?? windows.first(where: { !$0.isHidden })
            ?? windows.first
    }
}
#endif
