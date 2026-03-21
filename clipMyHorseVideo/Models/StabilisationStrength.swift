import CoreGraphics

enum StabilisationStrength: String, CaseIterable, Identifiable {
    case light = "Light"
    case medium = "Medium"
    case strong = "Strong"

    var id: String { rawValue }

    /// Smoothing window in frames. Larger = smoother but more crop.
    var smoothingWindow: Int {
        switch self {
        case .light: 10
        case .medium: 20
        case .strong: 40
        }
    }

    /// Fraction of frame to crop for stabilisation headroom.
    var cropFraction: CGFloat {
        switch self {
        case .light: 0.05
        case .medium: 0.08
        case .strong: 0.12
        }
    }

    var description: String {
        switch self {
        case .light: "Minimal correction, ~5% crop"
        case .medium: "Balanced correction, ~8% crop"
        case .strong: "Maximum correction, ~12% crop"
        }
    }
}
