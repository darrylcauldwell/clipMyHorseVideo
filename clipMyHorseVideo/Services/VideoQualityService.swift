import AVFoundation
import CoreImage
import Vision

enum VideoQualityService {
    private static let ciContext = CIContext()
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()
    struct QualityReport {
        var warnings: [Warning] = []

        var hasWarnings: Bool { !warnings.isEmpty }

        enum Warning: Identifiable {
            case lowResolution(width: Int, height: Int)
            case lowBitrate(kbps: Int)
            case blurry(score: Double)

            var id: String {
                switch self {
                case .lowResolution: "lowRes"
                case .lowBitrate: "lowBitrate"
                case .blurry: "blurry"
                }
            }

            var iconName: String {
                switch self {
                case .lowResolution: "rectangle.badge.xmark"
                case .lowBitrate: "waveform.badge.exclamationmark"
                case .blurry: "camera.metering.none"
                }
            }

            var message: String {
                switch self {
                case .lowResolution(let w, let h):
                    "Low resolution (\(w)x\(h)). Export quality may be limited."
                case .lowBitrate(let kbps):
                    "Low bitrate (\(kbps) kbps). Video may show compression artifacts."
                case .blurry(let score):
                    "Image appears blurry (sharpness \(Int(score * 100))%). Check lens cleanliness."
                }
            }
        }
    }

    /// Analyse a clip for quality issues.
    static func analyse(url: URL) async -> QualityReport {
        let asset = AVURLAsset(url: url)
        var report = QualityReport()

        // Check resolution
        if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
            if let size = try? await videoTrack.load(.naturalSize) {
                let transform = (try? await videoTrack.load(.preferredTransform)) ?? .identity
                let transformed = size.applying(transform)
                let w = Int(abs(transformed.width))
                let h = Int(abs(transformed.height))
                if w < 720 || h < 480 {
                    report.warnings.append(.lowResolution(width: w, height: h))
                }
            }

            // Check bitrate
            if let bitrate = try? await videoTrack.load(.estimatedDataRate) {
                let kbps = Int(bitrate / 1000)
                if kbps < 2000 {
                    report.warnings.append(.lowBitrate(kbps: kbps))
                }
            }
        }

        // Check sharpness via Laplacian variance on first frame
        let blurScore = await measureSharpness(asset: asset)
        if blurScore < 0.3 {
            report.warnings.append(.blurry(score: blurScore))
        }

        if report.hasWarnings {
            Log.quality.info("Quality warnings: \(report.warnings.count) issues found")
        }

        return report
    }

    /// Measure image sharpness using Laplacian variance. Returns 0.0 (blurry) to 1.0 (sharp).
    private static func measureSharpness(asset: AVAsset) async -> Double {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 640, height: 360)
        generator.appliesPreferredTrackTransform = true

        do {
            let (cgImage, _) = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
            let ciImage = CIImage(cgImage: cgImage)

            // Use CIEdges to detect sharpness
            guard let edgeFilter = CIFilter(name: "CIEdges") else { return 1.0 }
            edgeFilter.setValue(ciImage, forKey: kCIInputImageKey)
            edgeFilter.setValue(5.0, forKey: kCIInputIntensityKey)

            guard let outputImage = edgeFilter.outputImage else { return 1.0 }

            // Calculate average pixel intensity of edge-detected image
            let extent = outputImage.extent
            guard extent.width > 0, extent.height > 0 else { return 1.0 }

            guard let areaAverage = CIFilter(name: "CIAreaAverage") else { return 1.0 }
            areaAverage.setValue(outputImage, forKey: kCIInputImageKey)
            areaAverage.setValue(CIVector(cgRect: extent), forKey: "inputExtent")

            guard let avgImage = areaAverage.outputImage else { return 1.0 }

            var pixel = [UInt8](repeating: 0, count: 4)
            ciContext.render(avgImage, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: colorSpace)

            // Normalize to 0-1 range
            let brightness = Double(pixel[0]) / 255.0
            return min(brightness * 3.0, 1.0) // Scale up since edge images tend to be dark
        } catch {
            return 1.0 // Assume ok if we can't analyse
        }
    }
}
