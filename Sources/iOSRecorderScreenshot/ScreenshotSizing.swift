import CoreGraphics

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
}
