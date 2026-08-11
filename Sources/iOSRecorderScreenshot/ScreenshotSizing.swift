import CoreGraphics
import Foundation
import iOSRecorder

/// Pure arithmetic for fitting a pixel size under a longest-edge ceiling, free of UIKit so tests run on any platform.
enum ScreenshotSizing {
    /// Scales both edges by the same ratio and rounds to whole pixels, so the result is never larger than the input.
    /// - Parameter maxDimension: Longest-edge ceiling in pixels; zero or negative keeps the original size.
    static func fitted(_ size: CGSize, maxDimension: CGFloat) -> CGSize {
        let longest = max(size.width, size.height)
        guard maxDimension > 0, longest > maxDimension else { return size }
        let ratio = maxDimension / longest
        return CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
    }

    /// Builds the stored screenshot from a rendered screen, reporting the size the bytes are in.
    ///
    /// `encode` is told which pixel size to produce and that same size becomes the artifact's
    /// `width` and `height`, so the two cannot drift apart. The window's own size never reaches
    /// here: that is measured in points, a different unit from the downscaled JPEG, and an agent
    /// that lays coordinates over the image using points misses everything it aims at.
    ///
    /// - Parameters:
    ///   - renderedPixelSize: Size of the rendered image in pixels, before any downscale.
    ///   - maxDimension: Longest-edge ceiling in pixels for the stored image.
    ///   - encode: Produces the JPEG bytes at the requested pixel size, or `nil` if it cannot.
    static func artifact(
        renderedPixelSize: CGSize,
        maxDimension: CGFloat,
        encode: (CGSize) -> Data?
    ) -> Artifact? {
        let target = fitted(renderedPixelSize, maxDimension: maxDimension)
        guard let data = encode(target) else { return nil }
        return Artifact.screenshot(jpegData: data, attributes: [
            "width": "\(Int(target.width))",
            "height": "\(Int(target.height))"
        ])
    }
}
