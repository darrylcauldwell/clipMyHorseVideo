import AVFoundation

@Observable
@MainActor
final class BackgroundMusic {
    var url: URL?
    var title: String = ""
    var volume: Float = 0.3       // 0.0 to 1.0
    var originalVolume: Float = 1.0  // volume of original clip audio

    var isSelected: Bool { url != nil }

    var asset: AVAsset? {
        guard let url else { return nil }
        return AVAsset(url: url)
    }

    func clear() {
        url = nil
        title = ""
        volume = 0.3
        originalVolume = 1.0
    }
}
