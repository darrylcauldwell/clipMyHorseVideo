import PhotosUI
import SwiftUI

struct ClipPickerView: View {
    @Binding var clips: [Clip]
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.equestrian.sports")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Build Your Round")
                .font(.title2.bold())

            Text("Choose the clips from your showjumping round in order. You can reorder and trim them next.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 12) {
                flowStep(icon: "photo.on.rectangle.angled", label: "Pick")
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                flowStep(icon: "slider.horizontal.3", label: "Edit")
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                flowStep(icon: "square.and.arrow.up", label: "Share")
            }
            .padding(.top, 4)

            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 20,
                matching: .videos
            ) {
                Label("Choose Videos", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)

            if isLoading {
                ProgressView("Loading clips...")
            }

            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .onChange(of: selectedItems) {
            Task { await loadSelectedVideos() }
        }
    }

    private func flowStep(icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.body)
            Text(label)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    private func analyseQuality(for clips: [Clip]) async {
        for clip in clips {
            let report = await VideoQualityService.analyse(asset: clip.asset)
            clip.qualityReport = report
        }
    }

    private func loadSelectedVideos() async {
        guard !selectedItems.isEmpty else { return }
        isLoading = true
        loadError = nil

        var loadedClips: [Clip] = []

        for item in selectedItems {
            do {
                let asset = try await PhotoLibraryService.loadAsset(from: item)
                let duration = try await asset.load(.duration)
                let clip = Clip(asset: asset, duration: duration)
                loadedClips.append(clip)
            } catch {
                Log.photos.error("Failed to load clip: \(error.localizedDescription)")
            }
        }

        if loadedClips.isEmpty {
            loadError = "No clips could be loaded. Try different videos."
        } else {
            clips = loadedClips
            await ThumbnailService.generateThumbnails(for: loadedClips)
            Task { await analyseQuality(for: loadedClips) }
        }

        selectedItems = []
        isLoading = false
    }
}
