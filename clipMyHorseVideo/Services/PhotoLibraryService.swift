import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct Movie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let fileName = received.file.lastPathComponent
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent(fileName)
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }
}

enum PhotoLibraryService {
    static func loadAsset(from item: PhotosPickerItem) async throws -> AVAsset {
        guard let movie = try await item.loadTransferable(type: Movie.self) else {
            throw PhotoLibraryError.failedToLoadVideo
        }
        return AVAsset(url: movie.url)
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
