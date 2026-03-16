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
}
