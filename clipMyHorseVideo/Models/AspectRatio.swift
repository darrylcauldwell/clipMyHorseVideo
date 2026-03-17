import CoreGraphics

enum AspectRatio: String, CaseIterable, Identifiable {
    case original = "Original"
    case landscape16x9 = "16:9"
    case portrait9x16 = "9:16"
    case square1x1 = "1:1"
    case tall4x5 = "4:5"

    var id: String { rawValue }

    var ratio: CGFloat? {
        switch self {
        case .original: nil
        case .landscape16x9: 16.0 / 9.0
        case .portrait9x16: 9.0 / 16.0
        case .square1x1: 1.0
        case .tall4x5: 4.0 / 5.0
        }
    }

    var description: String {
        switch self {
        case .original: "Source aspect ratio"
        case .landscape16x9: "YouTube, landscape video"
        case .portrait9x16: "Instagram Reels, TikTok"
        case .square1x1: "Instagram feed"
        case .tall4x5: "Instagram feed (tall)"
        }
    }

    /// Rough multiplier for file size estimation relative to 16:9 source.
    var estimatedPixelMultiplier: Double {
        guard let ratio else { return 1.0 }
        let baseline: CGFloat = 16.0 / 9.0
        return ratio < baseline
            ? Double(ratio / baseline)
            : Double(baseline / ratio)
    }

    func targetSize(from sourceSize: CGSize) -> CGSize {
        guard let ratio else { return sourceSize }
        let sourceRatio = sourceSize.width / sourceSize.height
        var width: CGFloat
        var height: CGFloat
        if sourceRatio > ratio {
            height = sourceSize.height
            width = round(height * ratio)
        } else {
            width = sourceSize.width
            height = round(width / ratio)
        }
        // Ensure even dimensions for video encoding
        width = CGFloat(Int(width) & ~1)
        height = CGFloat(Int(height) & ~1)
        return CGSize(width: width, height: height)
    }

    func cropTransform(from sourceSize: CGSize, to targetSize: CGSize) -> CGAffineTransform {
        let tx = (targetSize.width - sourceSize.width) / 2
        let ty = (targetSize.height - sourceSize.height) / 2
        return CGAffineTransform(translationX: tx, y: ty)
    }
}
