import AVFoundation
import SwiftUI

@Observable
@MainActor
final class DetectedJump: Identifiable {
    let id = UUID()
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

    init(startTime: CMTime, endTime: CMTime, confidence: Double) {
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
}
