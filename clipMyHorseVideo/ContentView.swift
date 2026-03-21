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
        }
    }
}
