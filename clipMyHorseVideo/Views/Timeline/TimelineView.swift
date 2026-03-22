import PhotosUI
import SwiftUI

struct TimelineView: View {
    @Binding var clips: [Clip]
    @Binding var textOverlays: [TextOverlay]
    @State private var selectedClipForTrim: Clip?
    @State private var showExportSettings = false
    @State private var showPreview = false
    @State private var showTextEditor = false
    @State private var showJumpDetection = false
    @State private var showDetectionDiagnostic = false
    @State private var showSignalDiagnostic = false
    @State private var showJumpLabelling = false
    @State private var showJumpEvaluation = false
    @State private var clipForTranscription: Clip?
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
                Section {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                        VStack(spacing: 0) {
                            TimelineClipRow(clip: clip, index: index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedClipForTrim = clip
                                }
                                .contextMenu {
                                    Button {
                                        Task { await transcribeClip(clip) }
                                    } label: {
                                        Label("Scan Audio", systemImage: "waveform.and.mic")
                                    }
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
                    Text("Tap to trim. Long press to reorder. Swipe to delete.")
                        .font(.caption)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: clips.count)
            .sensoryFeedback(.selection, trigger: reorderTrigger)
            .navigationTitle("Timeline")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showPreview = true
                    } label: {
                        Image(systemName: "play.circle")
                    }
                    .disabled(clips.isEmpty)

                    Menu {
                        addClipsButton

                        Button {
                            showJumpDetection = true
                        } label: {
                            Label("Auto-Detect Jumps", systemImage: "wand.and.stars")
                        }

                        Button {
                            showDetectionDiagnostic = true
                        } label: {
                            Label("Detection Diagnostic", systemImage: "magnifyingglass.circle")
                        }

                        Button {
                            showSignalDiagnostic = true
                        } label: {
                            Label("Signal Diagnostic", systemImage: "chart.line.uptrend.xyaxis")
                        }

                        Button {
                            showJumpLabelling = true
                        } label: {
                            Label("Label Jumps", systemImage: "flag")
                        }

                        Button {
                            showJumpEvaluation = true
                        } label: {
                            Label("Evaluate Detection", systemImage: "checkmark.diamond")
                        }

                        Button {
                            let overlay = TextOverlay()
                            textOverlays.append(overlay)
                            showTextEditor = true
                        } label: {
                            Label("Text Overlay", systemImage: "textformat")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }

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
            .sheet(item: $clipForTranscription) { clip in
                if let info = clip.announcerInfo {
                    NavigationStack {
                        TranscriptionResultView(info: info)
                    }
                }
            }
            .sheet(isPresented: $showTextEditor) {
                if let overlay = textOverlays.last {
                    NavigationStack {
                        TextOverlayEditorView(overlay: overlay)
                    }
                }
            }
            .sheet(isPresented: $showJumpDetection) {
                NavigationStack {
                    JumpDetectionView(clips: $clips)
                }
            }
            .sheet(isPresented: $showDetectionDiagnostic) {
                NavigationStack {
                    DetectionDiagnosticView(clips: clips)
                }
            }
            .sheet(isPresented: $showSignalDiagnostic) {
                NavigationStack {
                    JumpSignalDiagnosticView(clips: clips)
                }
            }
            .sheet(isPresented: $showJumpLabelling) {
                NavigationStack {
                    JumpLabellingView(clips: clips)
                }
            }
            .sheet(isPresented: $showJumpEvaluation) {
                NavigationStack {
                    JumpEvaluationView(clips: clips)
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
            .onDisappear {
                undoTask?.cancel()
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
            Label("Add More Clips", systemImage: "plus")
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

    private func transcribeClip(_ clip: Clip) async {
        let info = AnnouncerInfo()
        info.isTranscribing = true
        clip.announcerInfo = info

        guard let urlAsset = clip.asset as? AVURLAsset else { return }
        let url = urlAsset.url
        let timeRange = clip.trimmedTimeRange

        do {
            let transcript = try await TranscriptionService.transcribe(
                url: url,
                timeRange: timeRange
            )
            let extracted = TranscriptionService.extractAnnouncerInfo(from: transcript)
            clip.announcerInfo = extracted
            clipForTranscription = clip
        } catch {
            Log.transcription.error("Transcription failed: \(error.localizedDescription)")
            info.isTranscribing = false
        }
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
            HStack(spacing: 4) {
                Image(systemName: clip.transitionAfter.iconName)
                    .font(.caption2)
                Text(clip.transitionAfter.rawValue)
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
