import AVKit
import SwiftUI

struct JumpDetectionView: View {
    @Binding var clips: [Clip]
    @Environment(\.dismiss) private var dismiss
    @State private var detectionService = JumpDetectionService()
    @State private var sourceAsset: AVAsset?
    @State private var errorMessage: String?
    @State private var previewingJump: DetectedJump?
    @State private var previewPlayer: AVPlayer?

    var body: some View {
        VStack(spacing: 16) {
            if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else if detectionService.isAnalysing || sourceAsset == nil {
                VStack(spacing: 12) {
                    ProgressView(value: sourceAsset == nil ? nil : detectionService.progress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 48)

                    Text(sourceAsset == nil
                         ? "Preparing video..."
                         : "Analysing video... \(Int(detectionService.progress * 100))%")
                        .font(.headline)
                        .monospacedDigit()

                    Text("Looking for jump moments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !detectionService.detectedJumps.isEmpty {
                // Inline preview player
                if let previewingJump, let previewPlayer {
                    VideoPlayer(player: previewPlayer)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                        .onTapGesture { withAnimation { stopPreview() } }

                    Text("Jump at \(previewingJump.startTime.formattedDuration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Clip duration control
                VStack(spacing: 4) {
                    HStack {
                        Text("Clip duration")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(detectionService.paddingSeconds * 2))s")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { detectionService.paddingSeconds },
                        set: { detectionService.updatePadding($0) }
                    ), in: 2...8, step: 1)
                }
                .padding(.horizontal, 24)

                List {
                    ForEach(detectionService.detectedJumps) { jump in
                        JumpRow(
                            jump: jump,
                            isPreviewing: previewingJump?.id == jump.id
                        ) {
                            withAnimation { togglePreview(for: jump) }
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
                    .background(acceptedCount > 0 ? .accent : .secondary.opacity(0.2))
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
                Button("Cancel") {
                    stopPreview()
                    dismiss()
                }
            }
        }
        .task {
            guard let firstClip = clips.first else {
                errorMessage = "No clips loaded to analyse."
                return
            }
            sourceAsset = firstClip.asset
            await detectionService.analyse(asset: firstClip.asset)
        }
    }

    private func togglePreview(for jump: DetectedJump) {
        if previewingJump?.id == jump.id {
            stopPreview()
            return
        }

        guard let asset = sourceAsset else { return }

        stopPreview()

        let item = AVPlayerItem(asset: asset)
        item.forwardPlaybackEndTime = jump.endTime
        let player = AVPlayer(playerItem: item)

        // Observe end of playback to loop
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            player.seek(to: jump.startTime)
            player.play()
        }

        self.previewPlayer = player
        self.previewingJump = jump

        Task {
            await player.seek(to: jump.startTime)
            player.play()
        }
    }

    private func stopPreview() {
        previewPlayer?.pause()
        if let item = previewPlayer?.currentItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
        }
        previewPlayer = nil
        previewingJump = nil
    }
}

// MARK: - Jump Row

private struct JumpRow: View {
    @Bindable var jump: DetectedJump
    let isPreviewing: Bool
    let onTapPreview: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Preview button
            Button(action: onTapPreview) {
                Image(systemName: isPreviewing ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isPreviewing ? .red : .accent)
            }
            .buttonStyle(.plain)

            // Jump info — tap to preview
            VStack(alignment: .leading) {
                Text("Jump at \(jump.startTime.formattedDuration)")
                    .font(.headline)
                Text("Duration: \(jump.duration.formattedDuration) — Confidence: \(Int(jump.confidence * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTapPreview)

            Spacer()

            // Accept/reject toggle
            Toggle(isOn: $jump.isAccepted) {
                EmptyView()
            }
            .labelsHidden()
        }
    }
}
