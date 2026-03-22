import AVFoundation

@Observable
@MainActor
final class JumpEvaluationService {
    var session: LabellingSession?
    var isEvaluating = false
    var evaluationProgress: Double = 0

    private var videoURL: URL?

    // MARK: - Session Management

    func loadOrCreateSession(for url: URL) {
        videoURL = url
        let fileName = url.lastPathComponent
        if let existing = loadSession(fileName: fileName) {
            session = existing
            Log.labelling.info("Loaded existing session for \(fileName) with \(existing.labels.count) labels")
        } else {
            session = LabellingSession(videoFileName: fileName)
            Log.labelling.info("Created new session for \(fileName)")
        }
    }

    // MARK: - Label CRUD

    func addLabel(timeSeconds: Double, note: String = "") {
        guard session != nil else { return }
        let label = ManualJumpLabel(timeSeconds: timeSeconds, note: note)
        session!.labels.append(label)
        session!.labels.sort { $0.timeSeconds < $1.timeSeconds }
        saveSession()
        Log.labelling.info("Added label at \(String(format: "%.1f", timeSeconds))s")
    }

    func deleteLabel(id: UUID) {
        guard session != nil else { return }
        session!.labels.removeAll { $0.id == id }
        saveSession()
        Log.labelling.info("Deleted label \(id)")
    }

    // MARK: - Evaluation

    func evaluate(asset: AVAsset) async {
        guard let session, let urlAsset = asset as? AVURLAsset else { return }
        isEvaluating = true
        evaluationProgress = 0

        let url = urlAsset.url
        let labels = session.labels

        let result = await Task.detached(priority: .userInitiated) {
            let frameData = await JumpDetectionService.extractFrameData(
                url: url,
                sampleInterval: 0.25
            ) { p in
                Task { @MainActor [weak self] in self?.evaluationProgress = p }
            }

            let diagnostics = JumpDetectionService.detectJumpsWithDiagnostics(frameData)

            return Self.compare(
                labels: labels,
                algorithmJumps: diagnostics.jumps,
                signals: diagnostics.signals,
                tolerance: 2.0
            )
        }.value

        self.session!.evaluation = result
        saveSession()
        isEvaluating = false
        Log.labelling.info("Evaluation complete: precision=\(String(format: "%.0f", result.precision * 100))% recall=\(String(format: "%.0f", result.recall * 100))%")
    }

    // MARK: - Comparison Logic

    nonisolated static func compare(
        labels: [ManualJumpLabel],
        algorithmJumps: [JumpDetectionService.DetailedJumpResult],
        signals: [JumpDetectionService.SignalBreakdown],
        tolerance: Double
    ) -> EvaluationResult {
        var matchedLabels = Set<UUID>()
        var matchedAlgorithm = Set<Int>()
        var truePositives: [EvaluationResult.MatchedJump] = []

        // Greedy matching: for each label, find closest unmatched algorithm jump within tolerance
        for label in labels.sorted(by: { $0.timeSeconds < $1.timeSeconds }) {
            var bestIdx: Int?
            var bestOffset = Double.infinity

            for (idx, jump) in algorithmJumps.enumerated() {
                guard !matchedAlgorithm.contains(idx) else { continue }
                let offset = abs(jump.moment - label.timeSeconds)
                if offset <= tolerance && offset < bestOffset {
                    bestOffset = offset
                    bestIdx = idx
                }
            }

            if let idx = bestIdx {
                matchedLabels.insert(label.id)
                matchedAlgorithm.insert(idx)
                truePositives.append(EvaluationResult.MatchedJump(
                    labelTimeSeconds: label.timeSeconds,
                    algorithmTimeSeconds: algorithmJumps[idx].moment,
                    offsetSeconds: bestOffset,
                    confidence: algorithmJumps[idx].confidence
                ))
            }
        }

        // False positives: algorithm jumps not matched to any label
        let falsePositives: [EvaluationResult.AlgorithmOnly] = algorithmJumps.enumerated()
            .filter { !matchedAlgorithm.contains($0.offset) }
            .map { _, jump in
                let snapshot = signalSnapshot(at: jump.moment, signals: signals)
                return EvaluationResult.AlgorithmOnly(
                    algorithmTimeSeconds: jump.moment,
                    confidence: jump.confidence,
                    signals: snapshot
                )
            }

        // Missed jumps: labels not matched to any algorithm jump
        let missedJumps: [EvaluationResult.MissedJump] = labels
            .filter { !matchedLabels.contains($0.id) }
            .map { label in
                let snapshot = signalSnapshot(at: label.timeSeconds, signals: signals)
                return EvaluationResult.MissedJump(
                    labelTimeSeconds: label.timeSeconds,
                    signals: snapshot
                )
            }

        return EvaluationResult(
            toleranceSeconds: tolerance,
            truePositives: truePositives,
            falsePositives: falsePositives,
            missedJumps: missedJumps
        )
    }

    // MARK: - Export

    func exportJSON() -> URL? {
        guard let session else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(session) else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "labels_\(session.videoFileName).json"
        let url = tempDir.appendingPathComponent(fileName)

        do {
            try data.write(to: url)
            Log.labelling.info("Exported session JSON to \(url.lastPathComponent)")
            return url
        } catch {
            Log.labelling.error("Failed to export JSON: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Persistence

    private func saveSession() {
        guard let session else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session) else { return }

        let url = sessionFileURL(for: session.videoFileName)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url)
    }

    private func loadSession(fileName: String) -> LabellingSession? {
        let url = sessionFileURL(for: fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LabellingSession.self, from: data)
    }

    private func sessionFileURL(for videoFileName: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("labels_\(videoFileName).json")
    }

    // MARK: - Helpers

    private nonisolated static func signalSnapshot(
        at time: Double,
        signals: [JumpDetectionService.SignalBreakdown]
    ) -> EvaluationResult.SignalSnapshot? {
        // Find the signal entry closest to the given time
        guard let closest = signals.min(by: { abs($0.time - time) < abs($1.time - time) }) else {
            return nil
        }
        return EvaluationResult.SignalSnapshot(
            horseCenterYNormalised: closest.horseCenterYNormalised,
            horseAspectRatioNormalised: closest.horseAspectRatioNormalised,
            combinedCenterYNormalised: closest.combinedCenterYNormalised,
            compositeScore: closest.compositeScore
        )
    }
}
