import AVKit
import SwiftUI

struct JumpLabellingView: View {
    let clips: [Clip]
    @Environment(\.dismiss) private var dismiss
    @State private var service = JumpEvaluationService()
    @State private var player: AVPlayer?
    @State private var currentTime: Double = 0
    @State private var duration: Double = 1
    @State private var isScrubbing = false
    @State private var timeObserver: Any?

    var body: some View {
        VStack(spacing: 16) {
            // Video player
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .frame(height: 220)
                    .overlay { ProgressView() }
                    .padding(.horizontal)
            }

            // Scrub slider
            VStack(spacing: 4) {
                Slider(
                    value: $currentTime,
                    in: 0...max(duration, 0.1)
                ) { editing in
                    isScrubbing = editing
                    if editing {
                        player?.pause()
                    } else {
                        let time = CMTime(seconds: currentTime, preferredTimescale: 600)
                        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                    }
                }
                .padding(.horizontal)

                HStack {
                    Text(formatTime(currentTime))
                    Spacer()
                    Text(formatTime(duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            }

            // Mark jump button
            Button {
                service.addLabel(timeSeconds: currentTime)
            } label: {
                Label("Mark Jump Here", systemImage: "flag.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .padding(.horizontal, 24)

            // Labels list
            if let session = service.session, !session.labels.isEmpty {
                List {
                    ForEach(session.labels) { label in
                        Button {
                            seekTo(label.timeSeconds)
                        } label: {
                            HStack {
                                Image(systemName: "flag.fill")
                                    .foregroundStyle(.orange)
                                Text(formatTime(label.timeSeconds))
                                    .monospacedDigit()
                                if !label.note.isEmpty {
                                    Text(label.note)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                service.deleteLabel(id: label.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Labels Yet",
                    systemImage: "flag.slash",
                    description: Text("Scrub to a jump moment and tap \"Mark Jump Here\"")
                )
            }
        }
        .navigationTitle("Label Jumps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let session = service.session {
                    Text("\(session.labels.count) label\(session.labels.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            await setupPlayer()
        }
        .onDisappear {
            if let observer = timeObserver {
                player?.removeTimeObserver(observer)
            }
            player?.pause()
        }
    }

    private func setupPlayer() async {
        guard let firstClip = clips.first,
              let urlAsset = firstClip.asset as? AVURLAsset else { return }

        let url = urlAsset.url
        service.loadOrCreateSession(for: url)

        let asset = AVURLAsset(url: url)
        if let dur = try? await asset.load(.duration) {
            duration = dur.seconds
        }

        let avPlayer = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player = avPlayer

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !isScrubbing else { return }
            currentTime = time.seconds
        }
    }

    private func seekTo(_ seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = seconds
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frac = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, frac)
    }
}
