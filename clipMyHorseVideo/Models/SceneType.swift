import SwiftUI

enum SceneType: String, CaseIterable, Identifiable {
    case indoorArena = "Indoor Arena"
    case outdoorCourse = "Outdoor Course"
    case warmUp = "Warm-Up"
    case stables = "Stables"
    case unknown = "Unknown"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .indoorArena: "building.2"
        case .outdoorCourse: "leaf"
        case .warmUp: "figure.walk"
        case .stables: "house"
        case .unknown: "questionmark.circle"
        }
    }

    var colour: Color {
        switch self {
        case .indoorArena: .blue
        case .outdoorCourse: .green
        case .warmUp: .orange
        case .stables: .brown
        case .unknown: .gray
        }
    }

    /// Vision classification labels that map to this scene type.
    var visionLabels: Set<String> {
        switch self {
        case .indoorArena: ["arena", "gymnasium", "sport", "indoor", "court"]
        case .outdoorCourse: ["field", "grass", "outdoor", "meadow", "pasture", "park"]
        case .warmUp: ["exercise", "training"]
        case .stables: ["barn", "stable", "shed", "farmhouse"]
        case .unknown: []
        }
    }

    /// Match a set of Vision classification identifiers to a scene type.
    static func classify(from identifiers: [String: Float]) -> SceneType {
        var scores: [SceneType: Float] = [:]
        for sceneType in allCases where sceneType != .unknown {
            let matchScore = identifiers.reduce(Float(0)) { total, pair in
                sceneType.visionLabels.contains(where: { pair.key.localizedCaseInsensitiveContains($0) })
                    ? total + pair.value
                    : total
            }
            scores[sceneType] = matchScore
        }
        return scores.max(by: { $0.value < $1.value })?.key ?? .unknown
    }
}
