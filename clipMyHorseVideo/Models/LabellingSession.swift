import Foundation

struct LabellingSession: Identifiable, Codable, Sendable {
    let id: UUID
    let videoFileName: String
    var labels: [ManualJumpLabel]
    var evaluation: EvaluationResult?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        videoFileName: String,
        labels: [ManualJumpLabel] = [],
        evaluation: EvaluationResult? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.videoFileName = videoFileName
        self.labels = labels
        self.evaluation = evaluation
        self.createdAt = createdAt
    }
}
