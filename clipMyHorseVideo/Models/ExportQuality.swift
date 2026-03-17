import AVFoundation

enum ExportQuality: String, CaseIterable, Identifiable {
    case original = "Original"
    case hd1080 = "1080p"
    case hd720 = "720p"

    var id: String { rawValue }

    var presetName: String {
        switch self {
        case .original: AVAssetExportPresetHighestQuality
        case .hd1080: AVAssetExportPreset1920x1080
        case .hd720: AVAssetExportPreset1280x720
        }
    }

    var description: String {
        switch self {
        case .original: "Original quality"
        case .hd1080: "1920x1080 (Full HD)"
        case .hd720: "1280x720 (HD)"
        }
    }

    /// Estimated bitrate in bits per second for file size estimation.
    var estimatedBitrate: Double {
        switch self {
        case .original: 50_000_000
        case .hd1080: 17_000_000
        case .hd720: 8_000_000
        }
    }
}
