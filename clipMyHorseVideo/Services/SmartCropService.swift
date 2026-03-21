import AVFoundation
import CoreImage
import Vision

enum SmartCropService {
    struct CropPath {
        var frames: [(time: CMTime, rect: CGRect)]

        /// Interpolate the crop rect at a given time.
        func cropRect(at time: CMTime) -> CGRect? {
            guard !frames.isEmpty else { return nil }

            // Find surrounding keyframes
            let timeSeconds = time.seconds
            var before: (time: CMTime, rect: CGRect)?
            var after: (time: CMTime, rect: CGRect)?

            for frame in frames {
                if frame.time.seconds <= timeSeconds {
                    before = frame
                } else if after == nil {
                    after = frame
                }
            }

            guard let b = before else { return frames.first?.rect }
            guard let a = after else { return b.rect }

            // Linear interpolation between keyframes
            let totalSpan = a.time.seconds - b.time.seconds
            guard totalSpan > 0 else { return b.rect }
            let t = CGFloat((timeSeconds - b.time.seconds) / totalSpan)

            return CGRect(
                x: b.rect.origin.x + (a.rect.origin.x - b.rect.origin.x) * t,
                y: b.rect.origin.y + (a.rect.origin.y - b.rect.origin.y) * t,
                width: b.rect.width + (a.rect.width - b.rect.width) * t,
                height: b.rect.height + (a.rect.height - b.rect.height) * t
            )
        }
    }

    /// Track the primary subject across video frames and generate a crop path.
    static func generateCropPath(
        asset: AVAsset,
        timeRange: CMTimeRange,
        targetAspectRatio: CGFloat,
        sampleInterval: Double = 0.25
    ) async throws -> CropPath {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 640, height: 360)
        generator.appliesPreferredTrackTransform = true

        let videoTrack = try await asset.loadTracks(withMediaType: .video).first
        let naturalSize: CGSize
        if let track = videoTrack {
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let transformed = size.applying(transform)
            naturalSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
        } else {
            naturalSize = CGSize(width: 1920, height: 1080)
        }

        let totalSeconds = timeRange.duration.seconds
        let frameCount = Int(totalSeconds / sampleInterval)
        guard frameCount > 0 else { return CropPath(frames: []) }

        var lastObservation: VNDetectedObjectObservation?
        var frames: [(time: CMTime, rect: CGRect)] = []
        let requestHandler = VNSequenceRequestHandler()

        for i in 0..<frameCount {
            let seconds = timeRange.start.seconds + Double(i) * sampleInterval
            let time = CMTime(seconds: seconds, preferredTimescale: 600)

            do {
                let (cgImage, _) = try await generator.image(at: time)

                if let previous = lastObservation {
                    // Track existing observation
                    let trackRequest = VNTrackObjectRequest(detectedObjectObservation: previous)
                    trackRequest.trackingLevel = .fast
                    try requestHandler.perform([trackRequest], on: cgImage, orientation: .up)

                    if let result = trackRequest.results?.first as? VNDetectedObjectObservation,
                       result.confidence > 0.3 {
                        lastObservation = result
                        let cropRect = computeCropRect(
                            subjectBounds: result.boundingBox,
                            frameSize: naturalSize,
                            targetAspectRatio: targetAspectRatio
                        )
                        frames.append((time: time, rect: cropRect))
                    } else {
                        // Tracking lost — re-detect
                        lastObservation = try await detectSubject(in: cgImage)
                        if let obs = lastObservation {
                            let cropRect = computeCropRect(
                                subjectBounds: obs.boundingBox,
                                frameSize: naturalSize,
                                targetAspectRatio: targetAspectRatio
                            )
                            frames.append((time: time, rect: cropRect))
                        }
                    }
                } else {
                    // Initial detection
                    lastObservation = try await detectSubject(in: cgImage)
                    if let obs = lastObservation {
                        let cropRect = computeCropRect(
                            subjectBounds: obs.boundingBox,
                            frameSize: naturalSize,
                            targetAspectRatio: targetAspectRatio
                        )
                        frames.append((time: time, rect: cropRect))
                    }
                }
            } catch {
                continue
            }
        }

        Log.composition.info("Smart crop path generated: \(frames.count) keyframes")
        return CropPath(frames: frames)
    }

    /// Detect the most prominent subject using saliency.
    private static func detectSubject(in cgImage: CGImage) async throws -> VNDetectedObjectObservation? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        try handler.perform([request])

        guard let result = request.results?.first,
              let salientObject = result.salientObjects?.first else {
            return nil
        }

        return VNDetectedObjectObservation(boundingBox: salientObject.boundingBox)
    }

    /// Compute a crop rect centred on the subject with the target aspect ratio.
    private static func computeCropRect(
        subjectBounds: CGRect,
        frameSize: CGSize,
        targetAspectRatio: CGFloat
    ) -> CGRect {
        let subjectCentreX = subjectBounds.midX * frameSize.width
        let subjectCentreY = subjectBounds.midY * frameSize.height

        // Compute crop size based on target aspect ratio
        var cropWidth: CGFloat
        var cropHeight: CGFloat

        if targetAspectRatio > 1 {
            // Landscape target
            cropHeight = frameSize.height
            cropWidth = cropHeight * targetAspectRatio
            if cropWidth > frameSize.width {
                cropWidth = frameSize.width
                cropHeight = cropWidth / targetAspectRatio
            }
        } else {
            // Portrait target
            cropWidth = frameSize.width
            cropHeight = cropWidth / targetAspectRatio
            if cropHeight > frameSize.height {
                cropHeight = frameSize.height
                cropWidth = cropHeight * targetAspectRatio
            }
        }

        // Centre on subject, clamped to frame bounds
        var x = subjectCentreX - cropWidth / 2
        var y = subjectCentreY - cropHeight / 2
        x = max(0, min(x, frameSize.width - cropWidth))
        y = max(0, min(y, frameSize.height - cropHeight))

        return CGRect(x: x, y: y, width: cropWidth, height: cropHeight)
    }
}
