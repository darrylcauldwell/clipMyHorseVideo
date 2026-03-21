import AVFoundation
import CoreImage
import Vision

enum VideoStabilisationService {
    /// Analyses consecutive video frames to detect translational motion and returns
    /// smoothed corrective transforms that counteract camera shake.
    static func analyseMotion(
        asset: AVAsset,
        timeRange: CMTimeRange,
        strength: StabilisationStrength,
        sampleInterval: Double = 1.0 / 30.0
    ) async throws -> [CMTime: CGAffineTransform] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360) // Downscale for speed

        let totalSeconds = timeRange.duration.seconds
        let frameCount = Int(totalSeconds / sampleInterval)
        guard frameCount > 1 else { return [:] }

        // Sample frames and compute frame-to-frame motion vectors
        var motionVectors: [(time: CMTime, dx: CGFloat, dy: CGFloat)] = []
        var previousImage: CIImage?

        for i in 0..<frameCount {
            let seconds = timeRange.start.seconds + Double(i) * sampleInterval
            let time = CMTime(seconds: seconds, preferredTimescale: 600)

            do {
                let (cgImage, _) = try await generator.image(at: time)
                let ciImage = CIImage(cgImage: cgImage)

                if let prev = previousImage {
                    let (dx, dy) = try await detectTranslation(from: prev, to: ciImage)
                    motionVectors.append((time: time, dx: dx, dy: dy))
                }

                previousImage = ciImage
            } catch {
                // Skip failed frames
                continue
            }
        }

        guard !motionVectors.isEmpty else { return [:] }

        // Compute cumulative path
        var cumulativeX: CGFloat = 0
        var cumulativeY: CGFloat = 0
        var cumulativePath: [(time: CMTime, x: CGFloat, y: CGFloat)] = []

        for vector in motionVectors {
            cumulativeX += vector.dx
            cumulativeY += vector.dy
            cumulativePath.append((time: vector.time, x: cumulativeX, y: cumulativeY))
        }

        // Smooth the path using rolling average
        let window = strength.smoothingWindow
        var smoothedPath: [(time: CMTime, x: CGFloat, y: CGFloat)] = []

        for i in 0..<cumulativePath.count {
            let start = max(0, i - window / 2)
            let end = min(cumulativePath.count, i + window / 2 + 1)
            let range = cumulativePath[start..<end]
            let avgX = range.reduce(0) { $0 + $1.x } / CGFloat(range.count)
            let avgY = range.reduce(0) { $0 + $1.y } / CGFloat(range.count)
            smoothedPath.append((time: cumulativePath[i].time, x: avgX, y: avgY))
        }

        // Compute corrective transforms (difference between smoothed and actual path)
        var transforms: [CMTime: CGAffineTransform] = [:]
        for i in 0..<cumulativePath.count {
            let correctionX = smoothedPath[i].x - cumulativePath[i].x
            let correctionY = smoothedPath[i].y - cumulativePath[i].y
            transforms[cumulativePath[i].time] = CGAffineTransform(translationX: correctionX, y: correctionY)
        }

        Log.composition.info("Motion analysis complete: \(transforms.count) corrective transforms, strength: \(strength.rawValue)")
        return transforms
    }

    private static func detectTranslation(from previous: CIImage, to current: CIImage) async throws -> (CGFloat, CGFloat) {
        let request = VNTranslationalImageRegistrationRequest(targetedCIImage: previous)
        let handler = VNImageRequestHandler(ciImage: current, orientation: .up)
        try handler.perform([request])

        guard let result = request.results?.first as? VNImageTranslationAlignmentObservation else {
            return (0, 0)
        }

        let transform = result.alignmentTransform
        return (transform.tx, transform.ty)
    }
}
