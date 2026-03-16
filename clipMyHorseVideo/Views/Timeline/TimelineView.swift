import PhotosUI
import SwiftUI

struct TimelineView: View {
    @Binding var clips: [Clip]
    @State private var selectedClipForTrim: Clip?
    @State private var showExportSettings = false
    @State private var additionalItems: [PhotosPickerItem] = []

    var body: some View {
        List {
            Section {
                ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                    TimelineClipRow(clip: clip, index: index)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedClipForTrim = clip
                        }
                }
                .onDelete(perform: deleteClips)
                .onMove(perform: moveClips)
            } header: {
                Text("\(clips.count) clip\(clips.count == 1 ? "" : "s")")
            } footer: {
                Text("Tap a clip to trim. Drag to reorder. Swipe to delete.")
                    .font(.caption)
            }
        }
        .navigationTitle("Timeline")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                addClipsButton
                Button("Export") {
                    showExportSettings = true
                }
                .disabled(clips.isEmpty)
            }
        }
        .sheet(item: $selectedClipForTrim) { clip in
            NavigationStack {
                TrimEditorView(clip: clip)
            }
        }
        .sheet(isPresented: $showExportSettings) {
            NavigationStack {
                ExportSettingsView(clips: clips) {
                    clips = []
                }
            }
        }
        .onChange(of: additionalItems) {
            Task { await loadAdditionalVideos() }
        }
    }

    private var addClipsButton: some View {
        PhotosPicker(
            selection: $additionalItems,
            maxSelectionCount: 20,
            matching: .videos
        ) {
            Image(systemName: "plus")
        }
    }

    private func deleteClips(at offsets: IndexSet) {
        clips.remove(atOffsets: offsets)
    }

    private func moveClips(from source: IndexSet, to destination: Int) {
        clips.move(fromOffsets: source, toOffset: destination)
    }

    private func loadAdditionalVideos() async {
        guard !additionalItems.isEmpty else { return }

        for item in additionalItems {
            do {
                let asset = try await PhotoLibraryService.loadAsset(from: item)
                let duration = try await asset.load(.duration)
                let clip = Clip(asset: asset, duration: duration)
                clip.thumbnail = await ThumbnailService.generateThumbnail(for: asset)
                clips.append(clip)
            } catch {
                Log.photos.error("Failed to load additional clip: \(error.localizedDescription)")
            }
        }

        additionalItems = []
    }
}
