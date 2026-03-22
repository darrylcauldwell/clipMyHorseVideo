import AVFoundation
import SwiftUI

@Observable
@MainActor
final class DetectedJump: Identifiable {
    let id = UUID()
    let momentTime: CMTime
    let videoDuration: CMTime
    var startTime: CMTime
    var endTime: CMTime
    var confidence: Double
    var isAccepted: Bool = true

    var duration: CMTime {
        CMTimeSubtract(endTime, startTime)
    }

    var timeRange: CMTimeRange {
        CMTimeRange(start: startTime, end: endTime)
    }

    init(momentTime: CMTime, videoDuration: CMTime, padding: Double, confidence: Double) {
        self.momentTime = momentTime
        self.videoDuration = videoDuration
        self.confidence = confidence
        let pad = CMTime(seconds: padding, preferredTimescale: 600)
        self.startTime = max(.zero, CMTimeSubtract(momentTime, pad))
        self.endTime = min(videoDuration, CMTimeAdd(momentTime, pad))
    }

    func updatePadding(_ padding: Double) {
        let pad = CMTime(seconds: padding, preferredTimescale: 600)
        startTime = max(.zero, CMTimeSubtract(momentTime, pad))
        endTime = min(videoDuration, CMTimeAdd(momentTime, pad))
    }
}
