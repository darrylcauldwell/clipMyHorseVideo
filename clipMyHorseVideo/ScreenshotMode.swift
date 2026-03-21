import AVFoundation
import SwiftUI
import UIKit

enum ScreenshotMode {
    static var isScreenshotMode: Bool {
        CommandLine.arguments.contains("--screenshot-mode")
    }

    static var requestedScreen: String? {
        guard let idx = CommandLine.arguments.firstIndex(of: "--screenshot-screen"),
              idx + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[idx + 1]
    }

    /// Generate demo clips with coloured placeholder thumbnails.
    @MainActor
    static func demoClips() -> [Clip] {
        let colours: [(UIColor, String)] = [
            (.systemBlue, "Warm-Up Ring"),
            (.systemGreen, "Jump 1–3"),
            (.systemOrange, "Double Combination"),
            (.systemPurple, "Water Jump"),
            (.systemRed, "Final Line"),
        ]

        return colours.enumerated().map { index, pair in
            let (colour, label) = pair
            let duration = CMTime(seconds: Double(8 + index * 2), preferredTimescale: 600)
            let clip = Clip.placeholder(duration: duration)
            clip.thumbnail = solidImage(colour: colour, size: CGSize(width: 320, height: 180), label: label)

            // Vary transitions for visual interest
            switch index {
            case 0: clip.transitionAfter = .crossfade
            case 1: clip.transitionAfter = .wipe
            case 2: clip.transitionAfter = .slide
            case 3: clip.transitionAfter = .fadeToBlack
            default: clip.transitionAfter = .none
            }

            clip.sceneType = index < 2 ? .outdoorCourse : .indoorArena
            return clip
        }
    }

    private static func solidImage(colour: UIColor, size: CGSize, label: String) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            colour.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 16),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle,
            ]
            let textRect = CGRect(x: 0, y: size.height / 2 - 10, width: size.width, height: 20)
            label.draw(in: textRect, withAttributes: attrs)
        }
    }
}
