import AVFoundation
import Photos
import PhotosUI
import SwiftUI

enum PhotoLibraryService {
    static func loadAsset(from item: PhotosPickerItem) async throws -> AVAsset {
        guard let identifier = item.itemIdentifier else {
            throw PhotoLibraryError.failedToLoadVideo
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryError.notAuthorized
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let phAsset = fetchResult.firstObject else {
            throw PhotoLibraryError.failedToLoadVideo
        }

        return try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, _ in
                if let avAsset {
                    continuation.resume(returning: avAsset)
                } else {
                    continuation.resume(throwing: PhotoLibraryError.failedToLoadVideo)
                }
            }
        }
    }

    static func saveToPhotoLibrary(url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryError.notAuthorized
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
        Log.photos.info("Video saved to photo library")
    }
}

enum PhotoLibraryError: LocalizedError {
    case failedToLoadVideo
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .failedToLoadVideo: "Failed to load the selected video."
        case .notAuthorized: "Photo library access is required to save your video."
        }
    }
}
