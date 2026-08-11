import Testing
import CoreGraphics
@testable import iOSRecorderScreenshot

@Suite struct ScreenshotSizingTests {
    @Test func keepsSmallImagesUntouched() {
        let size = ScreenshotSizing.fitted(CGSize(width: 800, height: 600), maxDimension: 1024)
        #expect(size == CGSize(width: 800, height: 600))
    }

    @Test func scalesLongestSideToMaxPreservingAspect() {
        // matches an iPhone 16 Pro at 3x: 1206 x 2622
        let size = ScreenshotSizing.fitted(CGSize(width: 1206, height: 2622), maxDimension: 1024)
        #expect(size.height == 1024)
        #expect(abs(size.width - 1206 * (1024 / 2622)) < 1)
    }

    @Test func zeroMaxDimensionMeansUnlimited() {
        let original = CGSize(width: 5000, height: 3000)
        #expect(ScreenshotSizing.fitted(original, maxDimension: 0) == original)
    }
}
