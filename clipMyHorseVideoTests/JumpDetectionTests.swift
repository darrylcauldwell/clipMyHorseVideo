import AVFoundation
import Testing

@testable import clipMyHorseVideo

@MainActor
struct JumpDetectionTests {
    @Test func analyseWithRealVideo() async throws {
        let url = URL(fileURLWithPath: "/Users/darrylcauldwell/Development/clipMyHorseVideos/IMG_0205.MOV")
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        #expect(duration.seconds > 0, "Video duration: \(duration.seconds)s")

        let service = JumpDetectionService()
        await service.analyse(asset: asset)
        #expect(!service.isAnalysing)

        // 12-jump showjumping round — expect 8-16 detections
        let count = service.detectedJumps.count
        #expect(count >= 8, "Too few detections: \(count) (expected 8+)")
        #expect(count <= 16, "Too many detections: \(count) (expected <=16)")

        for jump in service.detectedJumps {
            #expect(jump.confidence > 0, "Jump at \(jump.momentTime.seconds)s confidence=\(Int(jump.confidence * 100))%")
        }

    }
}
