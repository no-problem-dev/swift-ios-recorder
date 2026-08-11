import Testing
import CoreGraphics
import Foundation
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

/// The artifact's `width`/`height` are what an AI agent computes its coordinates against. They have
/// to describe the JPEG that was actually stored — which is measured in pixels and downscaled to a
/// pixel ceiling — not the window that was rendered, which is measured in points.
@Suite struct ScreenshotArtifactTests {
    @Test func attributesReportTheStoredPixelSizeNotTheWindowPoints() throws {
        // iPhone 16 Pro: a 402x874 pt window renders 1206x2622 px and stores at 471x1024.
        var encodedAt: CGSize?
        let artifact = try #require(ScreenshotSizing.artifact(
            renderedPixelSize: CGSize(width: 1206, height: 2622),
            maxDimension: 1024,
            encode: { target in
                encodedAt = target
                return Data([0xFF, 0xD8])
            }
        ))

        #expect(encodedAt == CGSize(width: 471, height: 1024))
        #expect(artifact.attributes["width"] == "471")
        #expect(artifact.attributes["height"] == "1024")
        #expect(artifact.attributes["width"] != "402", "reported the window's points, not the image's pixels")
        #expect(artifact.attributes["height"] != "874", "reported the window's points, not the image's pixels")
    }

    /// With no downscale the two are the same number, so this alone would never catch a unit error —
    /// it pins that the reported size still comes from what was encoded.
    @Test func attributesMatchTheEncodedSizeWhenNothingIsDownscaled() throws {
        var encodedAt: CGSize?
        let artifact = try #require(ScreenshotSizing.artifact(
            renderedPixelSize: CGSize(width: 800, height: 600),
            maxDimension: 1024,
            encode: { target in
                encodedAt = target
                return Data([0xFF, 0xD8])
            }
        ))

        #expect(encodedAt == CGSize(width: 800, height: 600))
        #expect(artifact.attributes["width"] == "800")
        #expect(artifact.attributes["height"] == "600")
    }

    /// No bytes means no artifact, rather than a size describing an image that was never stored.
    @Test func encodingFailureProducesNoArtifact() {
        #expect(ScreenshotSizing.artifact(
            renderedPixelSize: CGSize(width: 1206, height: 2622),
            maxDimension: 1024,
            encode: { _ in nil }
        ) == nil)
    }
}
