enum TransitionStyle: String, CaseIterable, Identifiable {
    case none = "Cut"
    case crossfade = "Crossfade"

    var id: String { rawValue }

    var overlapDuration: Double {
        switch self {
        case .none: 0
        case .crossfade: 0.5
        }
    }

    var iconName: String {
        switch self {
        case .none: "scissors"
        case .crossfade: "wand.and.rays"
        }
    }

    var description: String {
        switch self {
        case .none: "Hard cut between clips"
        case .crossfade: "0.5s crossfade dissolve"
        }
    }
}
