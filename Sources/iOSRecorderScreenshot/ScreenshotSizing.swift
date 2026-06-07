import CoreGraphics

/// 画像のピクセルサイズを長辺上限に収める純粋計算。プラットフォーム非依存でテスト可能。
enum ScreenshotSizing {
    /// - Parameter maxDimension: 長辺の上限 px。0 以下で無制限（原寸）。
    static func fitted(_ size: CGSize, maxDimension: CGFloat) -> CGSize {
        let longest = max(size.width, size.height)
        guard maxDimension > 0, longest > maxDimension else { return size }
        let ratio = maxDimension / longest
        return CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
    }
}
