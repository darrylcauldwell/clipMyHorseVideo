import SwiftUI

struct ContentView: View {
    @State private var clips: [Clip] = []

    var body: some View {
        NavigationStack {
            Group {
                if clips.isEmpty {
                    ClipPickerView(clips: $clips)
                } else {
                    TimelineView(clips: $clips)
                }
            }
            .animation(.default, value: clips.isEmpty)
        }
    }
}
