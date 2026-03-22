import AVKit
import SwiftUI

struct JumpEvaluationView: View {
    let clips: [Clip]
    @Environment(\.dismiss) private var dismiss
    @State private var service = JumpEvaluationService()
    @State private var exportURL: URL?

    var body: some View {
        Group {
            if service.isEvaluating {
                VStack(spacing: 12) {
                    ProgressView(value: service.evaluationProgress)
                        .progressViewStyle(.linear)
                        .padding(.horizontal, 48)
                    Text("Analysing video... \(Int(service.evaluationProgress * 100))%")
                        .font(.headline)
                        .monospacedDigit()
                    Text("Comparing against manual labels")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let evaluation = service.session?.evaluation {
                resultsList(evaluation)
            } else if let session = service.session {
                preEvaluationView(session)
            } else {
                ContentUnavailableView(
                    "No Labels Found",
                    systemImage: "flag.slash",
                    description: Text("Label jumps first using \"Label Jumps\" from the menu")
                )
            }
        }
        .navigationTitle("Evaluate Detection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            guard let firstClip = clips.first,
                  let urlAsset = firstClip.asset as? AVURLAsset else { return }
            service.loadOrCreateSession(for: urlAsset.url)
        }
    }

    // MARK: - Pre-Evaluation

    private func preEvaluationView(_ session: LabellingSession) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.diamond")
                .font(.system(size: 48))
                .foregroundStyle(.accent)

            Text("\(session.labels.count) label\(session.labels.count == 1 ? "" : "s") found")
                .font(.headline)

            if session.labels.isEmpty {
                Text("Label jumps first using \"Label Jumps\" from the menu")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                Button {
                    Task { await runEvaluation() }
                } label: {
                    Label("Run Evaluation", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
            }
        }
    }

    // MARK: - Results

    private func resultsList(_ evaluation: EvaluationResult) -> some View {
        List {
            // Summary section
            Section("Summary") {
                HStack {
                    MetricCard(
                        title: "Precision",
                        value: String(format: "%.0f%%", evaluation.precision * 100),
                        color: evaluation.precision > 0.8 ? .green : .orange
                    )
                    MetricCard(
                        title: "Recall",
                        value: String(format: "%.0f%%", evaluation.recall * 100),
                        color: evaluation.recall > 0.8 ? .green : .orange
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                LabeledContent("Matched") {
                    Text("\(evaluation.truePositives.count)")
                        .foregroundStyle(.green)
                }
                LabeledContent("False Positives") {
                    Text("\(evaluation.falsePositives.count)")
                        .foregroundStyle(.orange)
                }
                LabeledContent("Missed") {
                    Text("\(evaluation.missedJumps.count)")
                        .foregroundStyle(.red)
                }
                LabeledContent("Tolerance") {
                    Text("\(String(format: "%.1f", evaluation.toleranceSeconds))s")
                }
            }

            // Matched jumps
            if !evaluation.truePositives.isEmpty {
                Section("Matched Jumps") {
                    ForEach(evaluation.truePositives) { match in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text("Label \(formatTime(match.labelTimeSeconds)) \u{2192} Algo \(formatTime(match.algorithmTimeSeconds))")
                                    .font(.subheadline)
                                Text("Offset: \(String(format: "%.1f", match.offsetSeconds))s \u{2022} Confidence: \(Int(match.confidence * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // False positives
            if !evaluation.falsePositives.isEmpty {
                Section("False Positives") {
                    ForEach(evaluation.falsePositives) { fp in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("Algorithm: \(formatTime(fp.algorithmTimeSeconds))")
                                    .font(.subheadline)
                                Spacer()
                                Text("Conf: \(Int(fp.confidence * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let signals = fp.signals {
                                signalSnapshotView(signals)
                            }
                        }
                    }
                }
            }

            // Missed jumps
            if !evaluation.missedJumps.isEmpty {
                Section("Missed Jumps") {
                    ForEach(evaluation.missedJumps) { missed in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text("Label: \(formatTime(missed.labelTimeSeconds))")
                                    .font(.subheadline)
                            }
                            if let signals = missed.signals {
                                signalSnapshotView(signals)
                            }
                        }
                    }
                }
            }

            // Actions
            Section {
                Button {
                    Task { await runEvaluation() }
                } label: {
                    Label("Re-run Evaluation", systemImage: "arrow.clockwise")
                }

                if let url = exportURL {
                    ShareLink(item: url) {
                        Label("Export JSON", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        exportURL = service.exportJSON()
                    } label: {
                        Label("Export JSON", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    // MARK: - Signal Snapshot

    private func signalSnapshotView(_ snapshot: EvaluationResult.SignalSnapshot) -> some View {
        HStack(spacing: 12) {
            signalPill("HCY", value: snapshot.horseCenterYNormalised)
            signalPill("HAR", value: snapshot.horseAspectRatioNormalised)
            signalPill("CCY", value: snapshot.combinedCenterYNormalised)
            signalPill("Score", value: snapshot.compositeScore)
        }
        .font(.caption2)
    }

    private func signalPill(_ label: String, value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(String(format: "%.2f", value))
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Actions

    private func runEvaluation() async {
        guard let firstClip = clips.first else { return }
        exportURL = nil
        await service.evaluate(asset: firstClip.asset)
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frac = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, frac)
    }
}

// MARK: - Metric Card

private struct MetricCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
