import SwiftUI

enum AppDestination {
    case picker
    case timeline
}

@Observable
@MainActor
final class NavigationState {
    static let shared = NavigationState()
    var pendingDestination: AppDestination?

    private init() {}
}
