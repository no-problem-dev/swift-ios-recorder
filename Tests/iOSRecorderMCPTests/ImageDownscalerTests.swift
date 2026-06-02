import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import iOSRecorderMCP

@Suite struct ImageDownscalerTests {
    /// 2000x2000 の PNG を生成する。
    private func makePNG(side: Int) -> Data {
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = context.makeImage()!
        let output = NSMutableData()
        let dest = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        _ = CGImageDestinationFinalize(dest)
        return output as Data
    }

    private func pixelSize(_ data: Data) -> Int {
        let src = CGImageSourceCreateWithData(data as CFData, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
        let w = props[kCGImagePropertyPixelWidth] as! Int
        let h = props[kCGImagePropertyPixelHeight] as! Int
        return max(w, h)
    }

    @Test func downscalesLargeImageAndShrinksBytes() {
        let original = makePNG(side: 2000)
        let result = ImageDownscaler.downscale(original, maxDimension: 256)
        let unwrapped = try! #require(result)
        #expect(unwrapped.mimeType == "image/jpeg")
        #expect(pixelSize(unwrapped.data) <= 256)
        #expect(unwrapped.data.count < original.count)
    }

    @Test func maxDimensionZeroReturnsNil() {
        let original = makePNG(side: 100)
        #expect(ImageDownscaler.downscale(original, maxDimension: 0) == nil)
    }
}
