import AVFoundation

@Observable
@MainActor
final class JumpDetectionService {
    var isAnalysing = false
    var progress: Double = 0
    var detectedJumps: [DetectedJump] = []

    /// Padding before and after detected jump moments.
    var paddingSeconds: Double = 2.0

    /// Analyse a video for jump moments using YOLO bounding-box analysis.
    func analyse(asset: AVAsset) async {
        isAnalysing = true
        progress = 0
        detectedJumps = []

        guard let urlAsset = asset as? AVURLAsset else {
            isAnalysing = false
            Log.general.error("Jump detection requires a URL-based asset")
            return
        }
        let videoURL = urlAsset.url
        let padding = paddingSeconds

        Log.general.info("Starting YOLO bounding-box jump detection")

        let results = await Task.detached(priority: .userInitiated) {
            // Phase 1: Extract frame data with YOLO
            let frameData = await Self.extractFrameData(url: videoURL, sampleInterval: 0.25) { p in
                Task { @MainActor [weak self] in self?.progress = p }
            }
            // Phases 2-6: Signal processing
            return Self.detectJumpsFromSamples(frameData)
        }.value

        let videoDuration = (try? await asset.load(.duration)) ?? .zero

        var jumps: [DetectedJump] = []
        for result in results {
            jumps.append(DetectedJump(
                momentTime: CMTime(seconds: result.moment, preferredTimescale: 600),
                videoDuration: videoDuration,
                padding: padding,
                confidence: result.confidence
            ))
        }

        detectedJumps = jumps
        isAnalysing = false
        Log.general.info("Jump detection complete: \(jumps.count) jumps found")
    }

    /// Convert accepted jumps into Clip objects.
    func createClips(from asset: AVAsset) -> [Clip] {
        let duration = detectedJumps.last.map {
            CMTimeAdd($0.endTime, CMTime(seconds: 1, preferredTimescale: 600))
        } ?? .zero

        return detectedJumps
            .filter(\.isAccepted)
            .map { jump in
                let clip = Clip(asset: asset, duration: duration)
                clip.trimStart = jump.startTime
                clip.trimEnd = jump.endTime
                return clip
            }
    }

    // MARK: - Padding

    /// Recalculate start/end times for all detected jumps with new padding.
    func updatePadding(_ padding: Double) {
        paddingSeconds = padding
        for jump in detectedJumps {
            jump.updatePadding(padding)
        }
    }

    // MARK: - Phase 1: Extract Frame Data (YOLO)

    struct FrameSample: Sendable {
        let time: Double
        let horseCenterY: Double?      // Vision coords: 0=bottom, 1=top
        let horseAspectRatio: Double?  // width / height
        let horseConfidence: Float
        let riderCenterY: Double?
        let riderConfidence: Float
    }

    nonisolated static func extractFrameData(
        url: URL,
        sampleInterval: Double,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async -> [FrameSample] {
        let frameDetections = await YOLODetectionService.analyseFrames(
            url: url,
            sampleInterval: sampleInterval,
            progressHandler: progressHandler
        )

        return frameDetections.map { frame in
            let d = frame.detections
            let horseCenterY = d.horseBox.map { Double($0.midY) }
            let horseAR = d.horseBox.map { Double($0.width / $0.height) }
            let riderCenterY = d.riderBox.map { Double($0.midY) }

            return FrameSample(
                time: frame.time,
                horseCenterY: horseCenterY,
                horseAspectRatio: horseAR,
                horseConfidence: d.horseConfidence,
                riderCenterY: riderCenterY,
                riderConfidence: d.riderConfidence
            )
        }
    }

    // MARK: - Phases 2-6: Signal Processing

    struct JumpResult: Sendable {
        let moment: Double
        let confidence: Double
    }

    struct SignalBreakdown: Sendable {
        let time: Double
        let horseCenterYDeviation: Double
        let horseCenterYNormalised: Double
        let horseAspectRatioDeviation: Double
        let horseAspectRatioNormalised: Double
        let combinedCenterYDeviation: Double
        let combinedCenterYNormalised: Double
        let compositeScore: Double
    }

    struct DetailedJumpResult: Sendable {
        let moment: Double
        let confidence: Double
        let peakIndex: Int
        let arcWindowStart: Int
        let arcWindowEnd: Int
    }

    struct DiagnosticOutput: Sendable {
        let signals: [SignalBreakdown]
        let jumps: [DetailedJumpResult]
    }

    nonisolated static func detectJumpsFromSamples(_ samples: [FrameSample]) -> [JumpResult] {
        let output = detectJumpsWithDiagnostics(samples)
        return output.jumps.map { JumpResult(moment: $0.moment, confidence: $0.confidence) }
    }

    nonisolated static func detectJumpsWithDiagnostics(_ samples: [FrameSample]) -> DiagnosticOutput {
        let count = samples.count
        guard count > 20 else { return DiagnosticOutput(signals: [], jumps: []) }

        // Phase 2: Interpolate missing detections (fill 1-2 frame gaps)
        let horseCenterY = interpolateGaps(samples.map(\.horseCenterY), maxGap: 2)
        let horseAspectRatio = interpolateGaps(samples.map(\.horseAspectRatio), maxGap: 2)
        let combinedCenterY = computeCombinedCenterY(samples)

        // Phase 3: Smooth & baseline
        let smoothedHCY = gaussianSmooth(horseCenterY, windowSize: 5)
        let smoothedHAR = gaussianSmooth(horseAspectRatio, windowSize: 5)
        let smoothedCCY = gaussianSmooth(combinedCenterY, windowSize: 5)

        let baselineWindow = min(count, 32) // 8s at 0.25s intervals
        let baseHAR = rollingMedian(smoothedHAR, windowSize: baselineWindow)
        let baseCCY = rollingMedian(smoothedCCY, windowSize: baselineWindow)

        // horseCenterY: use velocity + reversal gating instead of deviation from baseline.
        // A jump bascule produces sharp upward velocity then reversal (down).
        // Walking toward camera produces steady one-direction velocity — no reversal.
        let devHCY = velocityWithReversalGating(smoothedHCY, reversalWindow: 5)
        let devHAR = zip(smoothedHAR, baseHAR).map { $0 - $1 }
        let devCCY = zip(smoothedCCY, baseCCY).map { $0 - $1 }

        // Phase 4: Score with IQR normalisation and weights
        let iqrHCY = interquartileRange(devHCY)
        let iqrHAR = interquartileRange(devHAR)
        let iqrCCY = interquartileRange(devCCY)

        let weightHCY = 3.0
        let weightHAR = 2.0
        let weightCCY = 2.0

        var scores = [Double](repeating: 0, count: count)
        var signalBreakdowns: [SignalBreakdown] = []
        signalBreakdowns.reserveCapacity(count)

        for i in 0..<count {
            let normHCY = iqrHCY > 0.0001 ? devHCY[i] / iqrHCY : 0
            let normHAR = iqrHAR > 0.0001 ? devHAR[i] / iqrHAR : 0
            let normCCY = iqrCCY > 0.0001 ? devCCY[i] / iqrCCY : 0

            let clampedHCY = max(0, normHCY)
            let clampedHAR = max(0, normHAR)
            let clampedCCY = max(0, normCCY)

            let baseScore = clampedHCY * weightHCY + clampedHAR * weightHAR + clampedCCY * weightCCY

            // Corroboration boost: reward when multiple signals spike together
            let spiking = [clampedHCY > 0.5, clampedHAR > 0.5, clampedCCY > 0.5]
            let spikeCount = spiking.filter { $0 }.count
            let boost: Double = switch spikeCount {
            case 3: 1.56  // all three
            case 2: 1.30  // two signals
            default: 1.0
            }

            scores[i] = baseScore * boost

            signalBreakdowns.append(SignalBreakdown(
                time: samples[i].time,
                horseCenterYDeviation: devHCY[i],
                horseCenterYNormalised: normHCY,
                horseAspectRatioDeviation: devHAR[i],
                horseAspectRatioNormalised: normHAR,
                combinedCenterYDeviation: devCCY[i],
                combinedCenterYNormalised: normCCY,
                compositeScore: scores[i]
            ))
        }

        // Phase 5: Peak detection
        let smoothedScores = gaussianSmooth(scores, windowSize: 5)

        let scoreThreshold = max(1.5, percentile(smoothedScores, p: 0.80))
        let minSeparation = 6.0
        let peakWindow = 4

        struct PeakCandidate {
            let moment: Double
            let confidence: Double
            let index: Int
        }

        var peaks: [PeakCandidate] = []
        for i in peakWindow..<(count - peakWindow) {
            guard smoothedScores[i] > scoreThreshold else { continue }

            // Local maximum in ±peakWindow
            var isMax = true
            for j in (i - peakWindow)...(i + peakWindow) where j != i {
                if smoothedScores[j] > smoothedScores[i] {
                    isMax = false
                    break
                }
            }
            guard isMax else { continue }

            let time = samples[i].time

            // Enforce minimum separation — keep stronger peak
            if let lastIdx = peaks.indices.last,
               time - peaks[lastIdx].moment < minSeparation {
                if smoothedScores[i] > peaks[lastIdx].confidence {
                    peaks[lastIdx] = PeakCandidate(moment: time, confidence: smoothedScores[i], index: i)
                }
                continue
            }

            peaks.append(PeakCandidate(moment: time, confidence: smoothedScores[i], index: i))
        }

        // Phase 6: Parabolic validation — check for rise-then-fall arc
        let validated = peaks.map { peak -> PeakCandidate in
            let hasArc = checkParabolicArc(in: smoothedScores, at: peak.index, window: 6)
            let multiplier = hasArc ? 1.0 : 0.6
            return PeakCandidate(moment: peak.moment, confidence: peak.confidence * multiplier, index: peak.index)
        }

        // Filter out peaks that fell below threshold after validation
        let finalPeaks = validated.filter { $0.confidence > scoreThreshold * 0.5 }

        // Normalise confidence to 0-1
        let maxScore = finalPeaks.map(\.confidence).max() ?? 1.0
        let detailedJumps: [DetailedJumpResult] = finalPeaks.map { peak in
            // Walk outward from peak until composite score < 20% of peak or 12 frames (3s)
            let peakScore = smoothedScores[peak.index]
            let threshold = peakScore * 0.2
            let maxArcFrames = 12

            var arcStart = peak.index
            for i in stride(from: peak.index - 1, through: max(0, peak.index - maxArcFrames), by: -1) {
                if smoothedScores[i] < threshold { break }
                arcStart = i
            }

            var arcEnd = peak.index
            for i in (peak.index + 1)...min(count - 1, peak.index + maxArcFrames) {
                if smoothedScores[i] < threshold { break }
                arcEnd = i
            }

            return DetailedJumpResult(
                moment: peak.moment,
                confidence: min(1.0, max(0.3, peak.confidence / maxScore)),
                peakIndex: peak.index,
                arcWindowStart: arcStart,
                arcWindowEnd: arcEnd
            )
        }

        return DiagnosticOutput(signals: signalBreakdowns, jumps: detailedJumps)
    }

    // MARK: - Signal Processing Helpers

    /// Compute frame-to-frame velocity, gated by reversal detection.
    /// Returns positive velocity only at frames where the signal rises and then
    /// falls within `reversalWindow` frames. Walking toward camera (steady rise,
    /// no reversal) produces zero. Jump bascule (up then down) passes through.
    private nonisolated static func velocityWithReversalGating(
        _ values: [Double],
        reversalWindow: Int
    ) -> [Double] {
        let count = values.count
        guard count > 1 else { return [Double](repeating: 0, count: count) }

        // Compute velocity (first derivative)
        var velocity = [Double](repeating: 0, count: count)
        for i in 1..<count {
            velocity[i] = values[i] - values[i - 1]
        }

        // Gate: only keep positive velocity where a negative velocity follows
        // within reversalWindow frames (characteristic of bascule arc)
        var gated = [Double](repeating: 0, count: count)
        for i in 0..<count {
            guard velocity[i] > 0 else { continue }

            // Look ahead for reversal (velocity going negative)
            let searchEnd = min(count - 1, i + reversalWindow)
            guard searchEnd > i else { continue }
            var hasReversal = false
            for j in (i + 1)...searchEnd {
                if velocity[j] < 0 {
                    hasReversal = true
                    break
                }
            }

            if hasReversal {
                gated[i] = velocity[i]
            }
        }

        return gated
    }

    /// Fill gaps of up to maxGap nil values with linear interpolation.
    private nonisolated static func interpolateGaps(_ values: [Double?], maxGap: Int) -> [Double] {
        var result = [Double](repeating: 0, count: values.count)

        // First pass: copy known values, mark unknowns
        var lastKnown: (index: Int, value: Double)?
        for i in 0..<values.count {
            if let v = values[i] {
                // Fill gap from lastKnown to here if small enough
                if let prev = lastKnown, i - prev.index > 1, i - prev.index - 1 <= maxGap {
                    let gap = i - prev.index
                    for g in 1..<gap {
                        let t = Double(g) / Double(gap)
                        result[prev.index + g] = prev.value + t * (v - prev.value)
                    }
                }
                result[i] = v
                lastKnown = (i, v)
            } else if let prev = lastKnown {
                result[i] = prev.value // hold last known
            }
        }

        return result
    }

    /// Compute confidence-weighted average of horse and rider centerY.
    private nonisolated static func computeCombinedCenterY(_ samples: [FrameSample]) -> [Double] {
        samples.map { sample in
            let hConf = Double(sample.horseConfidence)
            let rConf = Double(sample.riderConfidence)
            let totalConf = hConf + rConf

            if totalConf < 0.01 { return 0 }

            let hY = sample.horseCenterY ?? 0
            let rY = sample.riderCenterY ?? 0
            return (hY * hConf + rY * rConf) / totalConf
        }
    }

    /// Gaussian-weighted smoothing.
    private nonisolated static func gaussianSmooth(_ values: [Double], windowSize: Int) -> [Double] {
        let half = windowSize / 2
        // Precompute Gaussian weights
        let sigma = Double(half) / 2.0
        var weights = [Double]()
        for j in -half...half {
            weights.append(exp(-Double(j * j) / (2 * sigma * sigma)))
        }
        let totalWeight = weights.reduce(0, +)
        let normalised = weights.map { $0 / totalWeight }

        return values.indices.map { i in
            var sum = 0.0
            var wSum = 0.0
            for j in -half...half {
                let idx = i + j
                guard idx >= 0, idx < values.count else { continue }
                let w = normalised[j + half]
                sum += values[idx] * w
                wSum += w
            }
            return wSum > 0 ? sum / wSum : values[i]
        }
    }

    private nonisolated static func rollingMedian(_ values: [Double], windowSize: Int) -> [Double] {
        let half = windowSize / 2
        return values.indices.map { i in
            let lo = max(0, i - half)
            let hi = min(values.count - 1, i + half)
            let window = Array(values[lo...hi]).sorted()
            return window[window.count / 2]
        }
    }

    private nonisolated static func percentile(_ values: [Double], p: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let idx = min(sorted.count - 1, Int(Double(sorted.count) * p))
        return sorted[idx]
    }

    private nonisolated static func interquartileRange(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard sorted.count >= 4 else { return sorted.max().map { $0 - (sorted.min() ?? 0) } ?? 1.0 }
        let q1 = sorted[sorted.count / 4]
        let q3 = sorted[3 * sorted.count / 4]
        return q3 - q1
    }

    /// Check whether the score curve forms a rise-then-fall arc around a peak.
    private nonisolated static func checkParabolicArc(in scores: [Double], at index: Int, window: Int) -> Bool {
        let count = scores.count
        let peakValue = scores[index]

        // Check left side: at least one sample lower by 30%+
        var leftDrop = false
        for i in max(0, index - window)..<index {
            if scores[i] < peakValue * 0.7 {
                leftDrop = true
                break
            }
        }

        // Check right side: at least one sample lower by 30%+
        var rightDrop = false
        for i in (index + 1)...min(count - 1, index + window) {
            if scores[i] < peakValue * 0.7 {
                rightDrop = true
                break
            }
        }

        return leftDrop && rightDrop
    }
}
