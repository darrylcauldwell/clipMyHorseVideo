import AVFoundation
import UIKit

enum ThumbnailService {
    static func generateThumbnail(for asset: AVAsset, at time: CMTime = .zero) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 320, height: 180)
        generator.appliesPreferredTrackTransform = true

        do {
            let (cgImage, _) = try await generator.image(at: time)
            return UIImage(cgImage: cgImage)
        } catch {
            Log.general.error("Thumbnail generation failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Generates thumbnails for multiple clips concurrently using TaskGroup.
    /// Returns results as they complete so callers can apply them incrementally.
    @MainActor
    static func generateThumbnails(for clips: [Clip]) async {
        await withTaskGroup(of: (UUID, UIImage?).self) { group in
            for clip in clips {
                let clipID = clip.id
                let asset = clip.asset
                group.addTask {
                    let image = await generateThumbnail(for: asset)
                    return (clipID, image)
                }
            }

            for await (clipID, image) in group {
                if let clip = clips.first(where: { $0.id == clipID }) {
                    clip.thumbnail = image
                }
            }
        }
    }

    /// Generates evenly-spaced filmstrip thumbnails across a clip's duration for the trim editor.
    static func generateFilmstrip(for asset: AVAsset, count: Int = 10) async -> [UIImage] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 160, height: 90)
        generator.appliesPreferredTrackTransform = true

        guard let duration = try? await asset.load(.duration),
              duration.seconds > 0 else { return [] }

        let totalSeconds = duration.seconds
        let interval = totalSeconds / Double(count)
        var thumbnails: [UIImage] = []

        for i in 0..<count {
            let time = CMTime(seconds: interval * Double(i) + interval / 2, preferredTimescale: 600)
            do {
                let (cgImage, _) = try await generator.image(at: time)
                thumbnails.append(UIImage(cgImage: cgImage))
            } catch {
                // Skip failed frames silently
            }
        }

        return thumbnails
    }
}
