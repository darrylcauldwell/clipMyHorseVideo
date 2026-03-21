import AVFoundation
import Vision

enum SceneClassificationService {
    /// Classify a clip's scene type by sampling frames and running VNClassifyImageRequest.
    @MainActor
    static func classify(clip: Clip, sampleCount: Int = 3) async -> SceneType {
        let asset = clip.asset
        let trimStartSeconds = clip.trimStart.seconds
        let duration = clip.trimmedDuration.seconds
        guard duration > 0 else { return .unknown }

        return await classifyAsset(asset, trimStartSeconds: trimStartSeconds, duration: duration, sampleCount: sampleCount)
    }

    private static func classifyAsset(_ asset: AVAsset, trimStartSeconds: Double, duration: Double, sampleCount: Int) async -> SceneType {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 320, height: 180)
        generator.appliesPreferredTrackTransform = true

        var aggregatedScores: [String: Float] = [:]

        for i in 0..<sampleCount {
            let seconds = duration * Double(i + 1) / Double(sampleCount + 1) + trimStartSeconds
            let time = CMTime(seconds: seconds, preferredTimescale: 600)

            do {
                let (cgImage, _) = try await generator.image(at: time)
                let scores = try await classifyImage(cgImage)
                for (key, value) in scores {
                    aggregatedScores[key, default: 0] += value
                }
            } catch {
                Log.general.error("Scene classification frame failed: \(error.localizedDescription)")
            }
        }

        return SceneType.classify(from: aggregatedScores)
    }

    /// Classify multiple clips concurrently, updating each clip's sceneType.
    @MainActor
    static func classifyAll(_ clips: [Clip]) async {
        await withTaskGroup(of: (UUID, SceneType).self) { group in
            for clip in clips {
                let clipID = clip.id
                group.addTask {
                    let scene = await classify(clip: clip)
                    return (clipID, scene)
                }
            }

            for await (clipID, scene) in group {
                if let clip = clips.first(where: { $0.id == clipID }) {
                    clip.sceneType = scene
                    clip.isClassifying = false
                }
            }
        }
    }

    private static func classifyImage(_ cgImage: CGImage) async throws -> [String: Float] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        try handler.perform([request])

        var scores: [String: Float] = [:]
        if let results = request.results {
            // Only include results with meaningful confidence
            for observation in results where observation.confidence > 0.1 {
                scores[observation.identifier] = observation.confidence
            }
        }
        return scores
    }
}
