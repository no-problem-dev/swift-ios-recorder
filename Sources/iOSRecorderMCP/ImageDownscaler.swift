import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// 画像を maxDimension に収まるよう縮小し JPEG で再エンコードする。
/// MCP の get_capture で AI へ返す画像のトークン量を抑えるために使う。
enum ImageDownscaler {
    /// - Returns: 縮小できた場合は (jpegData, "image/jpeg")。失敗時は nil。
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
