import CoreMedia
import SwiftUI

struct ExportSettingsView: View {
    let clips: [Clip]
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var quality: ExportQuality = .hd1080
    @State private var aspectRatio: AspectRatio = .original
    @State private var showProgress = false

    private var totalDurationTime: CMTime {
        var total = CMTime.zero
        for clip in clips {
            total = CMTimeAdd(total, clip.speedAdjustedDuration)
        }
        // Subtract overlap for each transition boundary
        for clip in clips.dropLast() where clip.transitionAfter != .none {
            let overlap = CMTime(seconds: clip.transitionAfter.overlapDuration, preferredTimescale: 600)
            total = CMTimeSubtract(total, overlap)
        }
        return total
    }

    private var totalDuration: String {
        totalDurationTime.formattedDuration
    }

    private var estimatedFileSize: String {
        let seconds = CMTimeGetSeconds(totalDurationTime)
        guard seconds > 0 else { return "0 bytes" }
        let bytes = Int64(seconds * quality.estimatedBitrate / 8 * aspectRatio.estimatedPixelMultiplier)
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }

    var body: some View {
        Form {
            Section("Summary") {
                LabeledContent("Clips", value: "\(clips.count)")
                LabeledContent("Est. Duration", value: totalDuration)
            }

            Section("Quality") {
                Picker("Export Quality", selection: $quality) {
                    ForEach(ExportQuality.allCases) { q in
                        Text(q.rawValue).tag(q)
                    }
                }
                .pickerStyle(.segmented)

                Text(quality.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Estimated size: ~\(estimatedFileSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Aspect Ratio") {
                Picker("Aspect Ratio", selection: $aspectRatio) {
                    ForEach(AspectRatio.allCases) { ratio in
                        Text(ratio.rawValue).tag(ratio)
                    }
                }
                .pickerStyle(.navigationLink)

                Text(aspectRatio.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Transitions") {
                ForEach(TransitionStyle.allCases) { style in
                    Button {
                        for clip in clips {
                            clip.transitionAfter = style
                        }
                    } label: {
                        Label("Set All to \(style.rawValue)", systemImage: style.iconName)
                    }
                }

                Text("Transitions can also be set individually on the timeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    showProgress = true
                } label: {
                    Label("Export Video", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
            }
        }
        .navigationTitle("Export Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $showProgress) {
            NavigationStack {
                ExportProgressView(
                    clips: clips,
                    quality: quality,
                    aspectRatio: aspectRatio
                ) {
                    dismiss()
                    onComplete()
                }
            }
        }
    }
}
