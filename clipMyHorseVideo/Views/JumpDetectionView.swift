import AVKit
import SwiftUI

struct JumpDetectionView: View {
    @Binding var clips: [Clip]
    @Environment(\.dismiss) private var dismiss
    @State private var detectionService = JumpDetectionService()
    @State private var sourceAsset: AVAsset?
    @State private var errorMessage: String?

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
                Button("Cancel") { dismiss() }
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
}
