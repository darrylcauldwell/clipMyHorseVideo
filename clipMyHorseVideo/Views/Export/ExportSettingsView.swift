import CoreMedia
import SwiftUI

struct ExportSettingsView: View {
    let clips: [Clip]
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var quality: ExportQuality = .hd1080
    @State private var transition: TransitionStyle = .crossfade
    @State private var showProgress = false

    private var totalDuration: String {
        var total = CMTime.zero
        for clip in clips {
            total = CMTimeAdd(total, clip.trimmedDuration)
        }
        if transition == .crossfade && clips.count > 1 {
            let overlapCount = clips.count - 1
            let overlap = CMTime(seconds: transition.overlapDuration * Double(overlapCount), preferredTimescale: 600)
            total = CMTimeSubtract(total, overlap)
        }
        return total.formattedDuration
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
            }

            Section("Transition") {
                Picker("Transition Style", selection: $transition) {
                    ForEach(TransitionStyle.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                Text(transition.description)
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
                    transition: transition
                ) {
                    dismiss()
                    onComplete()
                }
            }
        }
    }
}
