import AVFoundation
import UIKit

/// Diagnostic service that annotates video frames with YOLO detections.
/// Draws bounding boxes around detected horses and riders.
enum VisionDiagnosticService {

    struct AnnotatedFrame: Sendable {
        let time: Double
        let image: CGImage
        let horseBox: CGRect?       // Normalized (Vision coords, origin bottom-left)
        let horseConfidence: Float
        let riderBox: CGRect?       // Normalized (Vision coords, origin bottom-left)
        let riderConfidence: Float
    }

    /// Analyse frames using YOLOv8 to detect horse and rider.
    static func analyseFrames(
        url: URL,
        sampleInterval: Double = 0.5,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async -> [AnnotatedFrame] {
        let frameDetections = await YOLODetectionService.analyseFrames(
            url: url,
            sampleInterval: sampleInterval,
            progressHandler: progressHandler
        )

        return frameDetections.map { frame in
            AnnotatedFrame(
                time: frame.time,
                image: frame.image,
                horseBox: frame.detections.horseBox,
                horseConfidence: frame.detections.horseConfidence,
                riderBox: frame.detections.riderBox,
                riderConfidence: frame.detections.riderConfidence
            )
        }
    }

    /// Render an annotated frame as a UIImage with colored boxes.
    static func renderAnnotated(_ frame: AnnotatedFrame) -> UIImage {
        let width = CGFloat(frame.image.width)
        let height = CGFloat(frame.image.height)
        let size = CGSize(width: width, height: height)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            // Draw the base frame (UIImage.draw respects UIKit coordinate system)
            UIImage(cgImage: frame.image).draw(in: CGRect(origin: .zero, size: size))

            // Draw horse box (blue)
            if let box = frame.horseBox {
                let rect = denormalize(box, in: size)
                cgCtx.setStrokeColor(UIColor.systemBlue.cgColor)
                cgCtx.setLineWidth(3)
                cgCtx.stroke(rect)
                drawLabel("Horse \(Int(frame.horseConfidence * 100))%",
                          at: CGPoint(x: rect.minX, y: rect.minY - 20),
                          color: .systemBlue, in: cgCtx)
            }

            // Draw rider box (green)
            if let box = frame.riderBox {
                let rect = denormalize(box, in: size)
                cgCtx.setStrokeColor(UIColor.systemGreen.cgColor)
                cgCtx.setLineWidth(3)
                cgCtx.stroke(rect)
                drawLabel("Rider \(Int(frame.riderConfidence * 100))%",
                          at: CGPoint(x: rect.minX, y: rect.minY - 20),
                          color: .systemGreen, in: cgCtx)
            }

            // Timestamp
            drawLabel(String(format: "%.1fs", frame.time),
                      at: CGPoint(x: 8, y: 8),
                      color: .black.withAlphaComponent(0.6), in: cgCtx)
        }
    }

    /// Render a frame with bounding boxes and a signal value bar at the bottom.
    /// Colour codes the bar: green (< 0.5x IQR), orange (0.5-1.0x), red (> 1.0x).
    static func renderSignalAnnotated(
        _ frame: AnnotatedFrame,
        signalName: String,
        deviation: Double,
        normalised: Double,
        compositeScore: Double
    ) -> UIImage {
        let width = CGFloat(frame.image.width)
        let height = CGFloat(frame.image.height)
        let barHeight: CGFloat = 44
        let size = CGSize(width: width, height: height + barHeight)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            // Draw the base frame
            UIImage(cgImage: frame.image).draw(in: CGRect(x: 0, y: 0, width: width, height: height))

            // Draw bounding boxes
            if let box = frame.horseBox {
                let rect = denormalize(box, in: CGSize(width: width, height: height))
                cgCtx.setStrokeColor(UIColor.systemBlue.cgColor)
                cgCtx.setLineWidth(3)
                cgCtx.stroke(rect)
                drawLabel("Horse \(Int(frame.horseConfidence * 100))%",
                          at: CGPoint(x: rect.minX, y: rect.minY - 20),
                          color: .systemBlue, in: cgCtx)
            }
            if let box = frame.riderBox {
                let rect = denormalize(box, in: CGSize(width: width, height: height))
                cgCtx.setStrokeColor(UIColor.systemGreen.cgColor)
                cgCtx.setLineWidth(3)
                cgCtx.stroke(rect)
                drawLabel("Rider \(Int(frame.riderConfidence * 100))%",
                          at: CGPoint(x: rect.minX, y: rect.minY - 20),
                          color: .systemGreen, in: cgCtx)
            }

            // Timestamp
            drawLabel(String(format: "%.1fs", frame.time),
                      at: CGPoint(x: 8, y: 8),
                      color: .black.withAlphaComponent(0.6), in: cgCtx)

            // Signal bar at bottom
            let absNorm = abs(normalised)
            let barColor: UIColor = if absNorm < 0.5 {
                .systemGreen
            } else if absNorm < 1.0 {
                .systemOrange
            } else {
                .systemRed
            }

            cgCtx.setFillColor(barColor.withAlphaComponent(0.85).cgColor)
            cgCtx.fill(CGRect(x: 0, y: height, width: width, height: barHeight))

            let text = String(format: "%@ dev:%.3f norm:%.2f score:%.2f", signalName, deviation, normalised, compositeScore)
            drawLabel(text,
                      at: CGPoint(x: 8, y: height + 4),
                      color: barColor, in: cgCtx)
        }
    }

    // MARK: - Coordinate Helpers

    /// Convert Vision normalized rect (origin bottom-left) to UIKit rect (origin top-left).
    private static func denormalize(_ box: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: box.minX * size.width,
            y: (1 - box.maxY) * size.height,
            width: box.width * size.width,
            height: box.height * size.height
        )
    }

    private static func drawLabel(_ text: String, at point: CGPoint, color: UIColor, in context: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 16),
            .foregroundColor: UIColor.white,
            .backgroundColor: color.withAlphaComponent(0.7)
        ]
        let string = NSAttributedString(string: " \(text) ", attributes: attrs)
        let line = CTLineCreateWithAttributedString(string)
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: max(0, point.x), y: max(16, point.y + 16))
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
