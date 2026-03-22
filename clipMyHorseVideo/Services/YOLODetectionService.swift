import AVFoundation
import CoreML
import Vision

/// Shared YOLO detection service for running YOLOv8n on video frames.
/// Used by both JumpDetectionService and VisionDiagnosticService.
enum YOLODetectionService {

    struct Detections: Sendable {
        var horseBox: CGRect?
        var horseConfidence: Float = 0
        var riderBox: CGRect?
        var riderConfidence: Float = 0
    }

    struct FrameDetection: Sendable {
        let time: Double
        let image: CGImage
        let detections: Detections
    }

    /// Load the YOLOv8n CoreML model for Vision framework.
    static func loadYOLOModel() -> VNCoreMLModel? {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        guard let mlModel = try? yolov8n(configuration: config).model,
              let visionModel = try? VNCoreMLModel(for: mlModel) else {
            return nil
        }
        return visionModel
    }

    /// Run YOLO detection on a single image, returning best horse and rider boxes.
    static func runYOLO(on cgImage: CGImage, model: VNCoreMLModel) -> Detections {
        var detections = Detections()

        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        guard let observations = request.results as? [VNRecognizedObjectObservation] else {
            return detections
        }

        for observation in observations {
            for label in observation.labels {
                if label.identifier == "horse" && label.confidence > detections.horseConfidence {
                    detections.horseBox = observation.boundingBox
                    detections.horseConfidence = label.confidence
                }
                if label.identifier == "person" && label.confidence > detections.riderConfidence {
                    detections.riderBox = observation.boundingBox
                    detections.riderConfidence = label.confidence
                }
            }
        }

        return detections
    }

    /// Analyse video frames at regular intervals using YOLO detection.
    static func analyseFrames(
        url: URL,
        sampleInterval: Double = 0.25,
        maxSize: CGSize = CGSize(width: 640, height: 640),
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async -> [FrameDetection] {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return [] }
        let totalSeconds = duration.seconds
        guard totalSeconds > 0 else { return [] }

        guard let visionModel = loadYOLOModel() else {
            Log.general.error("Failed to load YOLOv8n model")
            return []
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = maxSize
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let frameCount = Int(totalSeconds / sampleInterval)
        var results: [FrameDetection] = []

        for i in 0..<frameCount {
            guard !Task.isCancelled else { break }

            let seconds = Double(i) * sampleInterval
            let time = CMTime(seconds: seconds, preferredTimescale: 600)

            guard let (cgImage, _) = try? await generator.image(at: time) else { continue }

            let detections = runYOLO(on: cgImage, model: visionModel)

            results.append(FrameDetection(
                time: seconds,
                image: cgImage,
                detections: detections
            ))

            progressHandler(Double(i + 1) / Double(frameCount))
        }

        return results
    }
}
