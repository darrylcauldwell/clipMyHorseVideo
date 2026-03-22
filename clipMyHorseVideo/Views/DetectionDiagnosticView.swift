import AVFoundation
import SwiftUI

/// Diagnostic view for evaluating YOLO horse/rider detection quality.
/// Shows annotated frames with bounding boxes that can be scrubbed through.
struct DetectionDiagnosticView: View {
    let clips: [Clip]
    @Environment(\.dismiss) private var dismiss
    @State private var frames: [VisionDiagnosticService.AnnotatedFrame] = []
    @State private var renderedImages: [UIImage] = []
    @State private var currentIndex = 0
    @State private var isAnalysing = false
    @State private var progress: Double = 0
    @State private var errorMessage: String?

    private var detectionStats: (horseRate: Int, riderRate: Int) {
        guard !frames.isEmpty else { return (0, 0) }
        let horseCount = frames.filter { $0.horseBox != nil }.count
        let riderCount = frames.filter { $0.riderBox != nil }.count
        return (
            horseRate: Int(Double(horseCount) / Double(frames.count) * 100),
            riderRate: Int(Double(riderCount) / Double(frames.count) * 100)
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.secondary)
            } else if isAnalysing {
                VStack(spacing: 12) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 48)
                    Text("Analysing frames... \(Int(progress * 100))%")
                        .font(.headline)
                        .monospacedDigit()
                    Text("Running YOLO detection on each frame")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !renderedImages.isEmpty {
                // Annotated frame display
                Image(uiImage: renderedImages[currentIndex])
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 8)

                // Frame scrubber
                VStack(spacing: 4) {
                    Slider(value: Binding(
                        get: { Double(currentIndex) },
                        set: { currentIndex = Int($0) }
                    ), in: 0...Double(max(0, renderedImages.count - 1)), step: 1)
                    .padding(.horizontal, 16)

                    HStack {
                        Text(String(format: "%.1fs", frames[currentIndex].time))
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text("Frame \(currentIndex + 1) / \(frames.count)")
                            .font(.caption.monospacedDigit())
                    }
                    .padding(.horizontal, 16)
                    .foregroundStyle(.secondary)
                }

                // Current frame detection info
                let frame = frames[currentIndex]
                HStack(spacing: 24) {
                    VStack {
                        Image(systemName: frame.horseBox != nil ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(frame.horseBox != nil ? .blue : .secondary)
                        Text("Horse")
                            .font(.caption2)
                        if frame.horseConfidence > 0 {
                            Text("\(Int(frame.horseConfidence * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    VStack {
                        Image(systemName: frame.riderBox != nil ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(frame.riderBox != nil ? .green : .secondary)
                        Text("Rider")
                            .font(.caption2)
                        if frame.riderConfidence > 0 {
                            Text("\(Int(frame.riderConfidence * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Overall stats
                let stats = detectionStats
                HStack(spacing: 16) {
                    Label("Horse: \(stats.horseRate)%", systemImage: "hare")
                        .font(.caption)
                    Label("Rider: \(stats.riderRate)%", systemImage: "figure.equestrian.sports")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

            } else {
                Text("No frames to display")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Detection Diagnostic")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            await runAnalysis()
        }
    }

    private func runAnalysis() async {
        guard let firstClip = clips.first,
              let urlAsset = firstClip.asset as? AVURLAsset else {
            errorMessage = "No video clip to analyse."
            return
        }

        isAnalysing = true
        let url = urlAsset.url

        let analysedFrames = await Task.detached {
            await VisionDiagnosticService.analyseFrames(
                url: url,
                sampleInterval: 0.5
            ) { p in
                Task { @MainActor in progress = p }
            }
        }.value

        frames = analysedFrames

        // Render annotated images
        renderedImages = await Task.detached {
            analysedFrames.map { VisionDiagnosticService.renderAnnotated($0) }
        }.value

        isAnalysing = false
    }
}
