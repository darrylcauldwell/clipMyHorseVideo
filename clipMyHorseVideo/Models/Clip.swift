import AVFoundation
import SwiftUI

enum AudioSpeedMode: String, CaseIterable, Identifiable {
    case pitchCorrected = "Pitch Corrected"
    case muted = "Muted"

    var id: String { rawValue }
}

@Observable
@MainActor
final class Clip: Identifiable {
    let id = UUID()
    let asset: AVAsset
    let originalDuration: CMTime
    var trimStart: CMTime
    var trimEnd: CMTime
    var thumbnail: UIImage?
    var filmstripThumbnails: [UIImage] = []
    var transitionAfter: TransitionStyle = .none
    var playbackSpeed: Double = 1.0
    var audioSpeedMode: AudioSpeedMode = .pitchCorrected
    var qualityReport: VideoQualityService.QualityReport?
    var announcerInfo: AnnouncerInfo?

    static let speedPresets: [Double] = [0.25, 0.5, 1.0, 2.0, 4.0]

    var trimmedDuration: CMTime {
        CMTimeSubtract(trimEnd, trimStart)
    }

    var speedAdjustedDuration: CMTime {
        CMTimeMultiplyByFloat64(trimmedDuration, multiplier: 1.0 / playbackSpeed)
    }

    var speedLabel: String {
        playbackSpeed == 1.0 ? "" : "\(playbackSpeed.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", playbackSpeed) : String(playbackSpeed))x"
    }

    var trimmedTimeRange: CMTimeRange {
        CMTimeRange(start: trimStart, end: trimEnd)
    }

    init(asset: AVAsset, duration: CMTime) {
        self.asset = asset
        self.originalDuration = duration
        self.trimStart = .zero
        self.trimEnd = duration
    }

    /// Create a placeholder clip for screenshot mode (no real asset).
    static func placeholder(duration: CMTime) -> Clip {
        let asset = AVAsset()
        return Clip(asset: asset, duration: duration)
    }
}
