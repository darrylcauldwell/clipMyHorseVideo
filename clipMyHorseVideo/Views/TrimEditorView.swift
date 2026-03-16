import AVKit
import SwiftUI

struct TrimEditorView: View {
    @Bindable var clip: Clip
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var startSeconds: Double = 0
    @State private var endSeconds: Double = 1

    private var totalSeconds: Double {
        clip.originalDuration.seconds
    }

    var body: some View {
        VStack(spacing: 16) {
            // Video preview
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .frame(height: 220)
                    .overlay {
                        ProgressView()
                    }
                    .padding(.horizontal)
            }

            // Trim controls
            VStack(spacing: 12) {
                HStack {
                    Text("Start")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(CMTime(seconds: startSeconds, preferredTimescale: 600).formattedDuration)
                        .font(.caption.monospacedDigit())
                }

                Slider(value: $startSeconds, in: 0...max(endSeconds - 0.1, 0.1))
                    .onChange(of: startSeconds) {
                        clip.trimStart = CMTime(seconds: startSeconds, preferredTimescale: 600)
                        seekPlayer(to: startSeconds)
                    }

                HStack {
                    Text("End")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(CMTime(seconds: endSeconds, preferredTimescale: 600).formattedDuration)
                        .font(.caption.monospacedDigit())
                }

                Slider(value: $endSeconds, in: max(startSeconds + 0.1, 0.1)...totalSeconds)
                    .onChange(of: endSeconds) {
                        clip.trimEnd = CMTime(seconds: endSeconds, preferredTimescale: 600)
                        seekPlayer(to: endSeconds - 0.5)
                    }
            }
            .padding(.horizontal, 24)

            // Duration info
            HStack {
                Label("Original", systemImage: "film")
                Text(clip.originalDuration.formattedDuration)
                    .monospacedDigit()
                Spacer()
                Label("Trimmed", systemImage: "scissors")
                Text(clip.trimmedDuration.formattedDuration)
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)

            Spacer()

            Button("Reset Trim") {
                startSeconds = 0
                endSeconds = totalSeconds
                clip.trimStart = .zero
                clip.trimEnd = clip.originalDuration
            }
            .foregroundStyle(.red)
            .padding(.bottom)
        }
        .navigationTitle("Trim Clip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            startSeconds = clip.trimStart.seconds
            endSeconds = clip.trimEnd.seconds
            player = AVPlayer(playerItem: AVPlayerItem(asset: clip.asset))
        }
    }

    private func seekPlayer(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
