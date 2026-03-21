import SwiftUI

struct ContentView: View {
    @State private var clips: [Clip] = []
    @State private var textOverlays: [TextOverlay] = []

    var body: some View {
        NavigationStack {
            Group {
                if let screen = ScreenshotMode.requestedScreen {
                    screenshotView(for: screen)
                } else if clips.isEmpty {
                    ClipPickerView(clips: $clips)
                } else {
                    TimelineView(clips: $clips, textOverlays: $textOverlays)
                }
            }
            .animation(.default, value: clips.isEmpty)
            .onAppear {
                if ScreenshotMode.isScreenshotMode && clips.isEmpty {
                    clips = ScreenshotMode.demoClips()
                }
                handlePendingNavigation()
            }
            .onChange(of: NavigationState.shared.pendingDestination) {
                handlePendingNavigation()
            }
        }
    }

    @ViewBuilder
    private func screenshotView(for screen: String) -> some View {
        switch screen {
        case "picker":
            ClipPickerView(clips: .constant([]))
        case "timeline":
            TimelineView(clips: $clips, textOverlays: $textOverlays)
        case "trim":
            if let clip = clips.first {
                TrimEditorView(clip: clip)
            }
        case "export-settings":
            ExportSettingsView(clips: clips) {}
        default:
            ClipPickerView(clips: .constant([]))
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
