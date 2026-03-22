import AVFoundation
import SwiftUI

struct JumpSignalDiagnosticView: View {
    let clips: [Clip]
    @Environment(\.dismiss) private var dismiss

    enum Signal: String, CaseIterable {
        case horseCenterY = "Horse Y"
        case horseAspectRatio = "Aspect Ratio"
        case combinedCenterY = "Combined Y"
    }

    @State private var frames: [VisionDiagnosticService.AnnotatedFrame] = []
    @State private var signals: [JumpDetectionService.SignalBreakdown] = []
    @State private var jumps: [JumpDetectionService.DetailedJumpResult] = []
    @State private var selectedJumpIndex = 0
    @State private var selectedSignal: Signal = .horseCenterY
    @State private var selectedFrameIndex = 0
    @State private var isAnalysing = false
    @State private var progress: Double = 0
    @State private var errorMessage: String?

    private var selectedJump: JumpDetectionService.DetailedJumpResult? {
        jumps.indices.contains(selectedJumpIndex) ? jumps[selectedJumpIndex] : nil
    }

    private var arcFrameIndices: [Int] {
        guard let jump = selectedJump else { return [] }
        return Array(jump.arcWindowStart...jump.arcWindowEnd)
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
                    Text("Analysing signals... \(Int(progress * 100))%")
                        .font(.headline)
                        .monospacedDigit()
                    Text("Running YOLO detection and signal processing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !jumps.isEmpty {
                // Jump picker
                HStack {
                    Text("Jump")
                        .font(.subheadline.weight(.medium))
                    Menu {
                        ForEach(jumps.indices, id: \.self) { i in
                            Button {
                                selectedJumpIndex = i
                                if let jump = selectedJump {
                                    selectedFrameIndex = jump.peakIndex
                                }
                            } label: {
                                let jump = jumps[i]
                                Text(String(format: "#%d — %.1fs (%.0f%%)", i + 1, jump.moment, jump.confidence * 100))
                            }
                        }
                    } label: {
                        if let jump = selectedJump {
                            Text(String(format: "#%d — %.1fs (%.0f%%)", selectedJumpIndex + 1, jump.moment, jump.confidence * 100))
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)

                // Signal picker
                Picker("Signal", selection: $selectedSignal) {
                    ForEach(Signal.allCases, id: \.self) { signal in
                        Text(signal.rawValue).tag(signal)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                // Annotated frame
                if frames.indices.contains(selectedFrameIndex) {
                    let annotatedImage = renderCurrentFrame()
                    Image(uiImage: annotatedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 8)
                }

                // Thumbnail strip
                SignalFrameStrip(
                    frames: frames,
                    arcIndices: arcFrameIndices,
                    peakIndex: selectedJump?.peakIndex ?? 0,
                    selectedIndex: $selectedFrameIndex
                )

                // Signal detail text
                if signals.indices.contains(selectedFrameIndex) {
                    let s = signals[selectedFrameIndex]
                    let (dev, norm) = signalValues(for: selectedSignal, from: s)
                    VStack(spacing: 4) {
                        HStack(spacing: 16) {
                            Label(String(format: "Dev: %.4f", dev), systemImage: "arrow.up.and.down")
                            Label(String(format: "Norm: %.2f", norm), systemImage: "chart.bar")
                            Label(String(format: "Score: %.2f", s.compositeScore), systemImage: "flame")
                        }
                        .font(.caption.monospacedDigit())

                        Text(String(format: "Frame %d — %.2fs", selectedFrameIndex + 1, s.time))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                }
            } else {
                Text("No jumps detected")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Signal Diagnostic")
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

    // MARK: - Analysis

    private func runAnalysis() async {
        guard let firstClip = clips.first,
              let urlAsset = firstClip.asset as? AVURLAsset else {
            errorMessage = "No video clip to analyse."
            return
        }

        isAnalysing = true
        let url = urlAsset.url

        let (analysedFrames, diagnosticOutput) = await Task.detached {
            let frameDetections = await YOLODetectionService.analyseFrames(
                url: url,
                sampleInterval: 0.25
            ) { p in
                Task { @MainActor in progress = p }
            }

            let annotated = frameDetections.map { frame in
                VisionDiagnosticService.AnnotatedFrame(
                    time: frame.time,
                    image: frame.image,
                    horseBox: frame.detections.horseBox,
                    horseConfidence: frame.detections.horseConfidence,
                    riderBox: frame.detections.riderBox,
                    riderConfidence: frame.detections.riderConfidence
                )
            }

            let samples = frameDetections.map { frame -> JumpDetectionService.FrameSample in
                let d = frame.detections
                return JumpDetectionService.FrameSample(
                    time: frame.time,
                    horseCenterY: d.horseBox.map { Double($0.midY) },
                    horseAspectRatio: d.horseBox.map { Double($0.width / $0.height) },
                    horseConfidence: d.horseConfidence,
                    riderCenterY: d.riderBox.map { Double($0.midY) },
                    riderConfidence: d.riderConfidence
                )
            }

            let output = JumpDetectionService.detectJumpsWithDiagnostics(samples)
            return (annotated, output)
        }.value

        frames = analysedFrames
        signals = diagnosticOutput.signals
        jumps = diagnosticOutput.jumps

        if let first = jumps.first {
            selectedFrameIndex = first.peakIndex
        }

        isAnalysing = false
    }

    // MARK: - Rendering

    private func renderCurrentFrame() -> UIImage {
        let frame = frames[selectedFrameIndex]
        guard signals.indices.contains(selectedFrameIndex) else {
            return VisionDiagnosticService.renderAnnotated(frame)
        }
        let s = signals[selectedFrameIndex]
        let (dev, norm) = signalValues(for: selectedSignal, from: s)
        return VisionDiagnosticService.renderSignalAnnotated(
            frame,
            signalName: selectedSignal.rawValue,
            deviation: dev,
            normalised: norm,
            compositeScore: s.compositeScore
        )
    }

    private func signalValues(
        for signal: Signal,
        from breakdown: JumpDetectionService.SignalBreakdown
    ) -> (deviation: Double, normalised: Double) {
        switch signal {
        case .horseCenterY:
            (breakdown.horseCenterYDeviation, breakdown.horseCenterYNormalised)
        case .horseAspectRatio:
            (breakdown.horseAspectRatioDeviation, breakdown.horseAspectRatioNormalised)
        case .combinedCenterY:
            (breakdown.combinedCenterYDeviation, breakdown.combinedCenterYNormalised)
        }
    }
}

// MARK: - Frame Strip

private struct SignalFrameStrip: View {
    let frames: [VisionDiagnosticService.AnnotatedFrame]
    let arcIndices: [Int]
    let peakIndex: Int
    @Binding var selectedIndex: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(arcIndices, id: \.self) { index in
                        if frames.indices.contains(index) {
                            let isPeak = index == peakIndex
                            let isSelected = index == selectedIndex
                            Image(uiImage: UIImage(cgImage: frames[index].image))
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(
                                            isPeak ? .red : (isSelected ? .blue : .clear),
                                            lineWidth: isPeak ? 3 : 2
                                        )
                                )
                                .id(index)
                                .onTapGesture {
                                    selectedIndex = index
                                }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 52)
            .onChange(of: selectedIndex) {
                withAnimation {
                    proxy.scrollTo(selectedIndex, anchor: .center)
                }
            }
        }
    }
}
