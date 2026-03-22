import AVKit
import SwiftUI

struct TrimEditorView: View {
    @Bindable var clip: Clip
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var startFraction: Double = 0
    @State private var endFraction: Double = 1
    @State private var trimBoundaryTrigger = 0

    private var totalSeconds: Double {
        clip.originalDuration.seconds
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 16) {
                // Video preview — fills ~45% of screen
                if let player {
                    VideoPlayer(player: player)
                        .frame(height: geometry.size.height * 0.45)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quaternary)
                        .frame(height: geometry.size.height * 0.45)
                        .overlay { ProgressView() }
                        .padding(.horizontal)
                }

                // Filmstrip trim control
                FilmstripTrimControl(
                    thumbnails: clip.filmstripThumbnails,
                    startFraction: $startFraction,
                    endFraction: $endFraction,
                    onStartDrag: { seekToFraction($0) },
                    onEndDrag: { seekToFraction($0) }
                )
                .padding(.horizontal, 16)
                .sensoryFeedback(.impact(weight: .light), trigger: trimBoundaryTrigger)

                // Duration info
                HStack {
                    Label("Keeping", systemImage: "scissors")
                    Text(clip.speedAdjustedDuration.formattedDuration)
                        .monospacedDigit()
                        .fontWeight(.medium)
                    Spacer()
                    Text("of \(clip.originalDuration.formattedDuration)")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

                // Speed control
                VStack(spacing: 8) {
                    Text("Speed")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(Clip.speedPresets, id: \.self) { speed in
                            Button {
                                clip.playbackSpeed = speed
                                player?.rate = Float(speed)
                            } label: {
                                Text(speed.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0fx", speed) : "\(speed)x")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(clip.playbackSpeed == speed ? .accent : .secondary.opacity(0.2))
                                    .foregroundStyle(clip.playbackSpeed == speed ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    if clip.playbackSpeed != 1.0 {
                        Picker("Audio", selection: $clip.audioSpeedMode) {
                            ForEach(AudioSpeedMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 32)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                Button("Reset Trim") {
                    startFraction = 0
                    endFraction = 1
                    applyTrim()
                }
                .foregroundStyle(.red)
                .padding(.bottom)
            }
        }
        .navigationTitle("Trim Clip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            startFraction = clip.trimStart.seconds / totalSeconds
            endFraction = clip.trimEnd.seconds / totalSeconds
            player = AVPlayer(playerItem: AVPlayerItem(asset: clip.asset))

            if clip.filmstripThumbnails.isEmpty, let urlAsset = clip.asset as? AVURLAsset {
                let url = urlAsset.url
                Task {
                    clip.filmstripThumbnails = await ThumbnailService.generateFilmstrip(for: url)
                }
            }
        }
        .onChange(of: startFraction) { applyTrim() }
        .onChange(of: endFraction) { applyTrim() }
    }

    private func applyTrim() {
        let start = totalSeconds * startFraction
        let end = totalSeconds * endFraction
        clip.trimStart = CMTime(seconds: start, preferredTimescale: 600)
        clip.trimEnd = CMTime(seconds: end, preferredTimescale: 600)

        // Haptic at boundaries
        if startFraction < 0.005 || endFraction > 0.995 {
            trimBoundaryTrigger += 1
        }
    }

    private func seekToFraction(_ fraction: Double) {
        let seconds = totalSeconds * fraction
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

// MARK: - Filmstrip Trim Control

private struct FilmstripTrimControl: View {
    let thumbnails: [UIImage]
    @Binding var startFraction: Double
    @Binding var endFraction: Double
    var onStartDrag: (Double) -> Void
    var onEndDrag: (Double) -> Void

    private let handleWidth: CGFloat = 20
    private let filmstripHeight: CGFloat = 50

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width - handleWidth * 2

            ZStack(alignment: .leading) {
                // Filmstrip thumbnails
                HStack(spacing: 0) {
                    ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(
                                width: thumbnails.isEmpty ? 0 : (geometry.size.width / CGFloat(thumbnails.count)),
                                height: filmstripHeight
                            )
                            .clipped()
                    }
                }
                .frame(height: filmstripHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    // Dim trimmed regions
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(.black.opacity(0.5))
                            .frame(width: handleWidth + startFraction * trackWidth)
                        Spacer()
                        Rectangle()
                            .fill(.black.opacity(0.5))
                            .frame(width: handleWidth + (1 - endFraction) * trackWidth)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Active region border
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.yellow, lineWidth: 2)
                    .frame(
                        width: (endFraction - startFraction) * trackWidth + handleWidth * 2,
                        height: filmstripHeight
                    )
                    .offset(x: startFraction * trackWidth)

                // Left handle
                trimHandle(isLeading: true)
                    .offset(x: startFraction * trackWidth)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newFraction = value.location.x / trackWidth
                                startFraction = min(max(newFraction, 0), endFraction - 0.02)
                                onStartDrag(startFraction)
                            }
                    )

                // Right handle
                trimHandle(isLeading: false)
                    .offset(x: handleWidth + endFraction * trackWidth)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let base = endFraction * trackWidth
                                let newFraction = (base + value.translation.width) / trackWidth
                                endFraction = min(max(newFraction, startFraction + 0.02), 1)
                                onEndDrag(endFraction)
                            }
                    )
            }
            .frame(height: filmstripHeight)
        }
        .frame(height: filmstripHeight)
    }

    private func trimHandle(isLeading: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.yellow)
            .frame(width: handleWidth, height: filmstripHeight)
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.6))
                    .frame(width: 4, height: 20)
            }
            .contentShape(Rectangle().size(width: 44, height: filmstripHeight))
    }
}
