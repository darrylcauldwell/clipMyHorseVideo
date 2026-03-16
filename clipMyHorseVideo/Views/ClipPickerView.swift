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

            Image(systemName: "film.stack")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Select Video Clips")
                .font(.title2.bold())

            Text("Pick up to 20 clips from your photo library to merge into a single video.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 20,
                matching: .videos
            ) {
                Label("Choose Videos", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
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
                clip.thumbnail = await ThumbnailService.generateThumbnail(for: asset)
                loadedClips.append(clip)
            } catch {
                Log.photos.error("Failed to load clip: \(error.localizedDescription)")
            }
        }

        if loadedClips.isEmpty {
            loadError = "No clips could be loaded. Try different videos."
        } else {
            clips = loadedClips
        }

        selectedItems = []
        isLoading = false
    }
}
