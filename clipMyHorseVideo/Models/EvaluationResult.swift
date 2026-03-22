import Foundation

struct EvaluationResult: Codable, Sendable {
    let toleranceSeconds: Double
    let truePositives: [MatchedJump]
    let falsePositives: [AlgorithmOnly]
    let missedJumps: [MissedJump]

    var precision: Double {
        let total = truePositives.count + falsePositives.count
        guard total > 0 else { return 0 }
        return Double(truePositives.count) / Double(total)
    }

    var recall: Double {
        let total = truePositives.count + missedJumps.count
        guard total > 0 else { return 0 }
        return Double(truePositives.count) / Double(total)
    }

    struct SignalSnapshot: Codable, Sendable {
        let horseCenterYNormalised: Double
        let horseAspectRatioNormalised: Double
        let combinedCenterYNormalised: Double
        let compositeScore: Double
    }

    struct MatchedJump: Identifiable, Codable, Sendable {
        let id: UUID
        let labelTimeSeconds: Double
        let algorithmTimeSeconds: Double
        let offsetSeconds: Double
        let confidence: Double

        init(
            id: UUID = UUID(),
            labelTimeSeconds: Double,
            algorithmTimeSeconds: Double,
            offsetSeconds: Double,
            confidence: Double
        ) {
            self.id = id
            self.labelTimeSeconds = labelTimeSeconds
            self.algorithmTimeSeconds = algorithmTimeSeconds
            self.offsetSeconds = offsetSeconds
            self.confidence = confidence
        }
    }

    struct AlgorithmOnly: Identifiable, Codable, Sendable {
        let id: UUID
        let algorithmTimeSeconds: Double
        let confidence: Double
        let signals: SignalSnapshot?

        init(
            id: UUID = UUID(),
            algorithmTimeSeconds: Double,
            confidence: Double,
            signals: SignalSnapshot? = nil
        ) {
            self.id = id
            self.algorithmTimeSeconds = algorithmTimeSeconds
            self.confidence = confidence
            self.signals = signals
        }
    }

    struct MissedJump: Identifiable, Codable, Sendable {
        let id: UUID
        let labelTimeSeconds: Double
        let signals: SignalSnapshot?

        init(
            id: UUID = UUID(),
            labelTimeSeconds: Double,
            signals: SignalSnapshot? = nil
        ) {
            self.id = id
            self.labelTimeSeconds = labelTimeSeconds
            self.signals = signals
        }
    }
}
