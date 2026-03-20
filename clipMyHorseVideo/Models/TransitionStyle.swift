enum TransitionStyle: String, CaseIterable, Identifiable {
    case none = "Cut"
    case crossfade = "Crossfade"
    case wipe = "Wipe"
    case slide = "Slide"
    case fadeToBlack = "Fade to Black"

    var id: String { rawValue }

    var overlapDuration: Double {
        switch self {
        case .none: 0
        case .crossfade: 0.5
        case .wipe: 0.5
        case .slide: 0.4
        case .fadeToBlack: 0.8
        }
    }

    var iconName: String {
        switch self {
        case .none: "scissors"
        case .crossfade: "wand.and.rays"
        case .wipe: "rectangle.righthalf.inset.filled.arrow.right"
        case .slide: "arrow.right.square"
        case .fadeToBlack: "circle.lefthalf.filled"
        }
    }

    var description: String {
        switch self {
        case .none: "Hard cut between clips"
        case .crossfade: "0.5s crossfade dissolve"
        case .wipe: "Horizontal sweep reveal"
        case .slide: "Push clip off-screen"
        case .fadeToBlack: "Fade out then fade in"
        }
    }
}
