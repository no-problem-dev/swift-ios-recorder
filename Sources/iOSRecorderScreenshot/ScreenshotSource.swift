#if canImport(UIKit)
import UIKit
import iOSRecorder

/// Rasterizes the running key window with `drawHierarchy`, which — unlike `ImageRenderer` — also
/// captures native `UIViewRepresentable` content.
///
/// The recorder's own overlay window is skipped, so the floating buttons never appear in a shot.
/// A capture where no window can be found produces no artifact at all and no error: the record is
/// stored without a screenshot.
///
/// The stored form is always a downscaled JPEG. A full-resolution PNG runs past 5 MB per frame on an
/// iPhone 16 Pro and dominates memory, transfer and disk cost, and the image handed to the AI is capped
/// at the same ceiling anyway, so shrinking this early loses nothing.
public struct ScreenshotSource: Source {
    public let kind = ArtifactKind.screenshot
    private let scale: CGFloat
    private let maxDimension: CGFloat
    private let jpegQuality: CGFloat

    /// - Parameters:
    ///   - scale: Rendering scale; 0 uses the device's own scale.
    ///   - maxDimension: Longest-edge ceiling in pixels for the stored image; 0 keeps the rendered size.
    ///     The artifact's `width` and `height` report this same pixel size, so a consumer's
    ///     coordinates line up with the image it was handed.
    ///   - jpegQuality: JPEG quality (0–1).
    public init(scale: CGFloat = 0, maxDimension: CGFloat = 1024, jpegQuality: CGFloat = 0.8) {
        self.scale = scale
        self.maxDimension = maxDimension
        self.jpegQuality = jpegQuality
    }

    public func measure(_ context: RecordContext) async -> Artifact? {
        // Only drawHierarchy has to be on the main actor; the costly encode runs off it so the UI never freezes.
        let rendered = await MainActor.run { Self.render(scale: scale) }
        guard let rendered else { return nil }
        return ScreenshotSizing.artifact(renderedPixelSize: rendered.pixelSize, maxDimension: maxDimension) { target in
            Self.encode(rendered.image, to: target, quality: jpegQuality)
        }
    }

    /// Rasterizes the window and reports the result in pixels, which is the unit the stored image
    /// and everything downstream of it is measured in. The window's point size is not returned:
    /// on a 3x screen it is a third of the truth, and nothing here has a use for it.
    @MainActor
    private static func render(scale: CGFloat) -> (image: UIImage, pixelSize: CGSize)? {
        guard let window = keyWindow() else { return nil }
        let format = UIGraphicsImageRendererFormat()
        if scale > 0 { format.scale = scale }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return (image, CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale))
    }

    /// Draws the image at `target` pixels and encodes JPEG, off the main actor because
    /// `UIGraphicsImageRenderer` is thread-safe.
    private static func encode(_ image: UIImage, to target: CGSize, quality: CGFloat) -> Data? {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard target != pixelSize else { return image.jpegData(compressionQuality: quality) }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    @MainActor
    static func keyWindow() -> UIWindow? {
        // Skip the transparent overlay window so the recorder's own buttons stay out of the shot.
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
