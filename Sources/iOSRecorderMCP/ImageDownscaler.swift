import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Shrinks a screenshot to fit a maximum edge and re-encodes it as JPEG, because a full-resolution
/// screenshot costs an enormous number of tokens once it is base64'd into a tool result.
enum ImageDownscaler {
    /// Re-encodes the image, applying its EXIF orientation so the result is upright.
    ///
    /// An image already smaller than `maxDimension` is not enlarged, but it is still re-encoded as
    /// lossy JPEG — a small PNG can come out bigger than it went in.
    ///
    /// - Parameters:
    ///   - maxDimension: Longest edge to allow, in pixels. Zero or less returns `nil`, which
    ///     callers use to mean "send the original untouched".
    ///   - jpegQuality: 0 to 1, trading artefacts against bytes.
    /// - Returns: The JPEG and its media type, or `nil` if the data is not a decodable image or
    ///   encoding failed — in which case nothing was shrunk and the original is all there is.
    static func downscale(_ data: Data, maxDimension: Int, jpegQuality: Double = 0.8) -> (data: Data, mimeType: String)? {
        guard maxDimension > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }

        CGImageDestinationAddImage(
            destination,
            thumbnail,
            [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (output as Data, "image/jpeg")
    }
}
