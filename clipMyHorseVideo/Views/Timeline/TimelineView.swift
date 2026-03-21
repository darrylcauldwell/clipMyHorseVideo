import PhotosUI
import SwiftUI

struct TimelineView: View {
    @Binding var clips: [Clip]
    @Binding var textOverlays: [TextOverlay]
    @State private var selectedClipForTrim: Clip?
    @State private var showExportSettings = false
    @State private var showPreview = false
    @State private var showTextEditor = false
    @State private var additionalItems: [PhotosPickerItem] = []

    // Undo delete state
    @State private var deletedClip: Clip?
    @State private var deletedIndex: Int?
    @State private var showUndoToast = false
    @State private var undoTask: Task<Void, Never>?

    // Haptic triggers
    @State private var reorderTrigger = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            List {
                // Mini timeline strip
                if clips.count > 1 {
                    Section {
                        MiniTimelineStrip(clips: clips)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                Section {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                        VStack(spacing: 0) {
                            TimelineClipRow(clip: clip, index: index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedClipForTrim = clip
                                }

                            // Transition indicator between clips
                            if index < clips.count - 1 {
                                TransitionIndicator(clip: clip)
                            }
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
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: clips.count)
            .sensoryFeedback(.selection, trigger: reorderTrigger)
            .navigationTitle("Timeline")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showPreview = true
                    } label: {
                        Image(systemName: "play.circle")
                    }
                    .disabled(clips.isEmpty)

                    Button {
                        let overlay = TextOverlay()
                        textOverlays.append(overlay)
                        showTextEditor = true
                    } label: {
                        Image(systemName: "textformat")
                    }

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
            .sheet(isPresented: $showTextEditor) {
                if let overlay = textOverlays.last {
                    NavigationStack {
                        TextOverlayEditorView(overlay: overlay)
                    }
                }
            }
            .sheet(isPresented: $showExportSettings) {
                NavigationStack {
                    ExportSettingsView(clips: clips, textOverlays: textOverlays) {
                        clips = []
                        textOverlays = []
                    }
                }
            }
            .fullScreenCover(isPresented: $showPreview) {
                PreviewPlayerView(clips: clips)
            }
            .onChange(of: additionalItems) {
                Task { await loadAdditionalVideos() }
            }

            // Undo toast
            if showUndoToast {
                undoToast
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Undo Toast

    private var undoToast: some View {
        HStack {
            Text("Clip removed")
                .font(.subheadline)
            Spacer()
            Button("Undo") {
                restoreDeletedClip()
            }
            .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Add Clips

    private var addClipsButton: some View {
        PhotosPicker(
            selection: $additionalItems,
            maxSelectionCount: 20,
            matching: .videos
        ) {
            Image(systemName: "plus")
        }
    }

    // MARK: - Actions

    private func deleteClips(at offsets: IndexSet) {
        guard let index = offsets.first else { return }

        // Commit any previous pending deletion
        deletedClip = nil

        let clip = clips[index]
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            clips.remove(atOffsets: offsets)
            deletedClip = clip
            deletedIndex = index
            showUndoToast = true
        }

        // Auto-dismiss after 5 seconds
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation {
                showUndoToast = false
                deletedClip = nil
                deletedIndex = nil
            }
        }
    }

    private func restoreDeletedClip() {
        undoTask?.cancel()
        guard let clip = deletedClip, let index = deletedIndex else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            clips.insert(clip, at: min(index, clips.count))
            showUndoToast = false
            deletedClip = nil
            deletedIndex = nil
        }
    }

    private func moveClips(from source: IndexSet, to destination: Int) {
        clips.move(fromOffsets: source, toOffset: destination)
        reorderTrigger += 1
    }

    private func loadAdditionalVideos() async {
        guard !additionalItems.isEmpty else { return }

        var newClips: [Clip] = []

        for item in additionalItems {
            do {
                let asset = try await PhotoLibraryService.loadAsset(from: item)
                let duration = try await asset.load(.duration)
                let clip = Clip(asset: asset, duration: duration)
                newClips.append(clip)
            } catch {
                Log.photos.error("Failed to load additional clip: \(error.localizedDescription)")
            }
        }

        clips.append(contentsOf: newClips)
        await ThumbnailService.generateThumbnails(for: newClips)

        additionalItems = []
    }
}

// MARK: - Transition Indicator

private struct TransitionIndicator: View {
    @Bindable var clip: Clip

    var body: some View {
        Button {
            let allCases = TransitionStyle.allCases
            if let currentIndex = allCases.firstIndex(of: clip.transitionAfter) {
                let nextIndex = allCases.index(after: currentIndex)
                clip.transitionAfter = nextIndex < allCases.endIndex ? allCases[nextIndex] : allCases[allCases.startIndex]
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: clip.transitionAfter.iconName)
                    .font(.caption2)
                Text(clip.transitionAfter.rawValue)
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

// MARK: - Mini Timeline Strip

private struct MiniTimelineStrip: View {
    let clips: [Clip]

    private var totalDuration: Double {
        clips.reduce(0) { $0 + $1.speedAdjustedDuration.seconds }
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                    let fraction = totalDuration > 0 ? clip.speedAdjustedDuration.seconds / totalDuration : 1.0 / Double(clips.count)
                    let width = max(30, fraction * (geometry.size.width - CGFloat(clips.count - 1) * 2))

                    ZStack {
                        if let thumbnail = clip.thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: width, height: 40)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(.quaternary)
                        }

                        Text("\(index + 1)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                    .frame(width: width, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .frame(height: 40)
    }
}
