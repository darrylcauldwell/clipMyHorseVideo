import AVFoundation
import CoreImage

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

        let padding = paddingSeconds

        // Run heavy frame processing off the main thread
        let results = await Task.detached(priority: .userInitiated) {
            await Self.detectJumps(asset: asset, padding: padding) { p in
                await MainActor.run { [weak self] in self?.progress = p }
            }
        }.value

        // Create @MainActor DetectedJump objects on MainActor
        var jumps: [DetectedJump] = []
        for result in results {
            jumps.append(DetectedJump(
                startTime: CMTime(seconds: result.start, preferredTimescale: 600),
                endTime: CMTime(seconds: result.end, preferredTimescale: 600),
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

    // MARK: - Detection (runs off MainActor)

    /// Plain data struct for passing results across actor boundaries.
    private struct JumpResult: Sendable {
        let start: Double
        let end: Double
        let confidence: Double
    }

    private static func detectJumps(
        asset: AVAsset,
        padding: Double,
        progressHandler: @escaping (Double) async -> Void
    ) async -> [JumpResult] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 320, height: 180)
        generator.appliesPreferredTrackTransform = true

        guard let totalDuration = try? await asset.load(.duration) else { return [] }
        let totalSeconds = totalDuration.seconds
        guard totalSeconds > 2 else { return [] }

        let sampleInterval: Double = 0.5
        let frameCount = Int(totalSeconds / sampleInterval)

        // Single CIContext reused across all frames
        let context = CIContext()

        var motionScores: [(time: Double, intensity: Double)] = []
        var previousImage: CIImage?

        for i in 0..<frameCount {
            guard !Task.isCancelled else { break }

            let seconds = Double(i) * sampleInterval
            let time = CMTime(seconds: seconds, preferredTimescale: 600)

            do {
                let (cgImage, _) = try await generator.image(at: time)
                let ciImage = CIImage(cgImage: cgImage)

                if let prev = previousImage {
                    let intensity = measureMotionIntensity(from: prev, to: ciImage, context: context)
                    motionScores.append((time: seconds, intensity: intensity))
                }

                previousImage = ciImage
            } catch {
                continue
            }

            await progressHandler(Double(i) / Double(frameCount))
        }

        guard !motionScores.isEmpty else { return [] }

        let threshold = calculateAdaptiveThreshold(scores: motionScores)
        var jumpMoments: [Double] = []

        for score in motionScores where score.intensity > threshold {
            if let last = jumpMoments.last, score.time - last < 3.0 {
                continue
            }
            jumpMoments.append(score.time)
        }

        return jumpMoments.map { moment in
            JumpResult(
                start: max(0, moment - padding),
                end: min(totalSeconds, moment + padding),
                confidence: 0.8
            )
        }
    }

    /// Measure motion between two frames using pixel difference.
    private static func measureMotionIntensity(from previous: CIImage, to current: CIImage, context: CIContext) -> Double {
        guard let diffFilter = CIFilter(name: "CIDifferenceBlendMode") else { return 0 }
        diffFilter.setValue(previous, forKey: kCIInputImageKey)
        diffFilter.setValue(current, forKey: kCIInputBackgroundImageKey)

        guard let diffImage = diffFilter.outputImage else { return 0 }

        guard let avgFilter = CIFilter(name: "CIAreaAverage") else { return 0 }
        avgFilter.setValue(diffImage, forKey: kCIInputImageKey)
        avgFilter.setValue(CIVector(cgRect: diffImage.extent), forKey: "inputExtent")

        guard let avgImage = avgFilter.outputImage else { return 0 }

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

        return mean + 1.5 * stdDev
    }
}
