import AVKit
import SwiftUI

struct PreviewPlayerView: View {
    let clips: [Clip]
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVQueuePlayer?
    @State private var isPlaying = false
    @State private var currentClipIndex = 0
    @State private var observerToken: Any?

    var body: some View {
        VStack(spacing: 0) {
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea(edges: .top)
            } else {
                Color.black
                    .overlay { ProgressView().tint(.white) }
                    .ignoresSafeArea(edges: .top)
            }

            HStack(spacing: 32) {
                Text("Clip \(currentClipIndex + 1) of \(clips.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    if isPlaying {
                        player?.pause()
                    } else {
                        player?.play()
                    }
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }

                Spacer()

                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .onAppear { setupPlayer() }
        .onDisappear { cleanup() }
    }

    private func setupPlayer() {
        let items = clips.compactMap { clip -> AVPlayerItem? in
            let item = AVPlayerItem(asset: clip.asset)
            item.forwardPlaybackEndTime = clip.trimEnd

            let startTime = clip.trimStart
            if startTime != .zero {
                Task { await item.seek(to: startTime) }
            }

            return item
        }

        guard !items.isEmpty else { return }

        let queuePlayer = AVQueuePlayer(items: items)
        self.player = queuePlayer

        // Track current clip index
        observerToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { _ in
            if currentClipIndex < clips.count - 1 {
                currentClipIndex += 1
            } else {
                isPlaying = false
            }
        }

        queuePlayer.play()
        isPlaying = true
    }

    private func cleanup() {
        player?.pause()
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
