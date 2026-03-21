import AVFoundation
import CoreImage
import Vision

@Observable
@MainActor
final class JumpDetectionService {
    var isAnalysing = false
    var progress: Double = 0
    var detectedJumps: [DetectedJump] = []

    /// Padding before and after detected jump moments.
    var paddingSeconds: Double = 2.0

    /// Analyse a video for jump moments using optical flow motion intensity.
    func analyse(asset: AVAsset) async {
        isAnalysing = true
        progress = 0
        detectedJumps = []

        let assetForAnalysis = asset
        let padding = paddingSeconds

        let jumps = await Self.detectJumps(asset: assetForAnalysis, padding: padding) { [weak self] p in
            await MainActor.run { self?.progress = p }
        }

        detectedJumps = jumps
        isAnalysing = false
        Log.general.info("Jump detection complete: \(jumps.count) jumps found")
    }

    /// Convert accepted jumps into Clip objects.
    func createClips(from asset: AVAsset) -> [Clip] {
        let duration: CMTime
        do {
            // Use a synchronous approximation since we already loaded the asset
            duration = detectedJumps.last.map { CMTimeAdd($0.endTime, CMTime(seconds: 1, preferredTimescale: 600)) } ?? .zero
        }

        return detectedJumps
            .filter(\.isAccepted)
            .map { jump in
                let clip = Clip(asset: asset, duration: duration)
                clip.trimStart = jump.startTime
                clip.trimEnd = jump.endTime
                return clip
            }
    }

    // MARK: - Detection Algorithm

    private static func detectJumps(
        asset: AVAsset,
        padding: Double,
        progressHandler: @Sendable @escaping (Double) async -> Void
    ) async -> [DetectedJump] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 320, height: 180)
        generator.appliesPreferredTrackTransform = true

        guard let totalDuration = try? await asset.load(.duration) else { return [] }
        let totalSeconds = totalDuration.seconds
        guard totalSeconds > 2 else { return [] }

        let sampleInterval: Double = 0.5 // Sample every 0.5s
        let frameCount = Int(totalSeconds / sampleInterval)

        // Compute motion intensity per frame
        var motionScores: [(time: Double, intensity: Double)] = []
        var previousImage: CIImage?

        for i in 0..<frameCount {
            let seconds = Double(i) * sampleInterval
            let time = CMTime(seconds: seconds, preferredTimescale: 600)

            do {
                let (cgImage, _) = try await generator.image(at: time)
                let ciImage = CIImage(cgImage: cgImage)

                if let prev = previousImage {
                    let intensity = measureMotionIntensity(from: prev, to: ciImage)
                    motionScores.append((time: seconds, intensity: intensity))
                }

                previousImage = ciImage
            } catch {
                continue
            }

            await progressHandler(Double(i) / Double(frameCount))
        }

        guard !motionScores.isEmpty else { return [] }

        // Find peaks in motion intensity that indicate jumps
        let threshold = calculateAdaptiveThreshold(scores: motionScores)
        var jumpMoments: [Double] = []

        for score in motionScores where score.intensity > threshold {
            // Avoid duplicate detections within 3s of each other
            if let last = jumpMoments.last, score.time - last < 3.0 {
                continue
            }
            jumpMoments.append(score.time)
        }

        // Create jump segments with padding
        var jumps: [DetectedJump] = []
        for moment in jumpMoments {
            let start = max(0, moment - padding)
            let end = min(totalSeconds, moment + padding)

            let jump = await MainActor.run {
                DetectedJump(
                    startTime: CMTime(seconds: start, preferredTimescale: 600),
                    endTime: CMTime(seconds: end, preferredTimescale: 600),
                    confidence: 0.8
                )
            }
            jumps.append(jump)
        }

        return jumps
    }

    /// Measure motion between two frames using pixel difference.
    private static func measureMotionIntensity(from previous: CIImage, to current: CIImage) -> Double {
        guard let diffFilter = CIFilter(name: "CIDifferenceBlendMode") else { return 0 }
        diffFilter.setValue(previous, forKey: kCIInputImageKey)
        diffFilter.setValue(current, forKey: kCIInputBackgroundImageKey)

        guard let diffImage = diffFilter.outputImage else { return 0 }

        // Compute average brightness of difference image
        guard let avgFilter = CIFilter(name: "CIAreaAverage") else { return 0 }
        avgFilter.setValue(diffImage, forKey: kCIInputImageKey)
        avgFilter.setValue(CIVector(cgRect: diffImage.extent), forKey: "inputExtent")

        guard let avgImage = avgFilter.outputImage else { return 0 }

        let context = CIContext()
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(avgImage, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

        return Double(pixel[0] + pixel[1] + pixel[2]) / (255.0 * 3.0)
    }

    /// Calculate adaptive threshold based on motion score distribution.
    private static func calculateAdaptiveThreshold(scores: [(time: Double, intensity: Double)]) -> Double {
        let intensities = scores.map(\.intensity).sorted()
        let mean = intensities.reduce(0, +) / Double(intensities.count)
        let variance = intensities.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(intensities.count)
        let stdDev = variance.squareRoot()

        // Threshold at mean + 1.5 standard deviations
        return mean + 1.5 * stdDev
    }
}
