import SwiftUI

struct ContentView: View {
    @State private var clips: [Clip] = []
    @State private var textOverlays: [TextOverlay] = []

    var body: some View {
        NavigationStack {
            Group {
                if clips.isEmpty {
                    ClipPickerView(clips: $clips)
                } else {
                    TimelineView(clips: $clips, textOverlays: $textOverlays)
                }
            }
            .animation(.default, value: clips.isEmpty)
            .onAppear {
                handlePendingNavigation()
            }
            .onChange(of: NavigationState.shared.pendingDestination) {
                handlePendingNavigation()
            }
        }
    }

    private func handlePendingNavigation() {
        guard let destination = NavigationState.shared.pendingDestination else { return }
        NavigationState.shared.pendingDestination = nil

        switch destination {
        case .picker:
            clips = []
        case .timeline:
            break
        }
    }
}
