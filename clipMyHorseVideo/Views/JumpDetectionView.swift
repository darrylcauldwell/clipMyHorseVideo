import AVKit
import PhotosUI
import SwiftUI

struct JumpDetectionView: View {
    @Binding var clips: [Clip]
    @Environment(\.dismiss) private var dismiss
    @State private var detectionService = JumpDetectionService()
    @State private var selectedItem: PhotosPickerItem?
    @State private var sourceAsset: AVAsset?

    var body: some View {
        VStack(spacing: 16) {
            if sourceAsset == nil {
                // Step 1: Pick a long video
                VStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("Auto-Detect Jumps")
                        .font(.title3.bold())

                    Text("Select a long recording and the app will find jump moments automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .videos
                    ) {
                        Label("Choose Video", systemImage: "film")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 32)
                }
            } else if detectionService.isAnalysing {
                // Step 2: Analysing
                VStack(spacing: 12) {
                    ProgressView(value: detectionService.progress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 48)

                    Text("Analysing video... \(Int(detectionService.progress * 100))%")
                        .font(.headline)
                        .monospacedDigit()

                    Text("Looking for jump moments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !detectionService.detectedJumps.isEmpty {
                // Step 3: Review results
                List {
                    ForEach(detectionService.detectedJumps) { jump in
                        HStack {
                            Toggle(isOn: Bindable(jump).isAccepted) {
                                VStack(alignment: .leading) {
                                    Text("Jump at \(jump.startTime.formattedDuration)")
                                        .font(.headline)
                                    Text("Duration: \(jump.duration.formattedDuration) — Confidence: \(Int(jump.confidence * 100))%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                HStack(spacing: 16) {
                    let acceptedCount = detectionService.detectedJumps.filter(\.isAccepted).count
                    Button("Add \(acceptedCount) Clip\(acceptedCount == 1 ? "" : "s")") {
                        if let asset = sourceAsset {
                            let newClips = detectionService.createClips(from: asset)
                            clips.append(contentsOf: newClips)
                            Task { await ThumbnailService.generateThumbnails(for: newClips) }
                            dismiss()
                        }
                    }
                    .disabled(acceptedCount == 0)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(acceptedCount > 0 ? .blue : .secondary.opacity(0.2))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 32)
                .padding(.bottom)
            } else {
                Text("No jumps detected in this video.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Jump Detection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onChange(of: selectedItem) {
            guard let item = selectedItem else { return }
            Task {
                do {
                    let asset = try await PhotoLibraryService.loadAsset(from: item)
                    sourceAsset = asset
                    await detectionService.analyse(asset: asset)
                } catch {
                    Log.general.error("Failed to load video for jump detection: \(error.localizedDescription)")
                }
            }
        }
    }
}
