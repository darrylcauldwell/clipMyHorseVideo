import SwiftUI

@Observable
@MainActor
final class TextOverlay: Identifiable {
    let id = UUID()
    var text: String = ""
    var position: OverlayPosition = .bottom
    var fontSize: CGFloat = 32
    var colour: Color = .white
    var backgroundOpacity: Double = 0.5
    var showShadow: Bool = true

    enum OverlayPosition: String, CaseIterable, Identifiable {
        case top = "Top"
        case centre = "Centre"
        case bottom = "Bottom"

        var id: String { rawValue }

        /// Vertical fraction (0 = top, 1 = bottom) for CALayer positioning.
        var yFraction: CGFloat {
            switch self {
            case .top: 0.85
            case .centre: 0.5
            case .bottom: 0.15
            }
        }
    }

    enum Preset: String, CaseIterable, Identifiable {
        case riderAndHorse = "Rider & Horse"
        case competition = "Competition"
        case custom = "Custom"

        var id: String { rawValue }

        var placeholder: String {
            switch self {
            case .riderAndHorse: "Jane Smith on Donavon"
            case .competition: "Spring Show — 1.10m Open"
            case .custom: "Your text here"
            }
        }
    }
}
