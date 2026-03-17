import AVFoundation
import SwiftUI

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

    var trimmedDuration: CMTime {
        CMTimeSubtract(trimEnd, trimStart)
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
}
