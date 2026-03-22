import Foundation

struct ManualJumpLabel: Identifiable, Codable, Sendable {
    let id: UUID
    let timeSeconds: Double
    var note: String
    let createdAt: Date

    init(id: UUID = UUID(), timeSeconds: Double, note: String = "", createdAt: Date = .now) {
        self.id = id
        self.timeSeconds = timeSeconds
        self.note = note
        self.createdAt = createdAt
    }
}
