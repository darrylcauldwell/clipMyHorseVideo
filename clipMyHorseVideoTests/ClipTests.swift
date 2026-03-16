import AVFoundation
import Testing

@testable import clipMyHorseVideo

@MainActor
struct ClipTests {
    @Test func trimmedDurationMatchesFullDuration() {
        let duration = CMTime(seconds: 10, preferredTimescale: 600)
        let asset = AVMutableComposition()
        let clip = Clip(asset: asset, duration: duration)

        #expect(clip.trimmedDuration == duration)
    }

    @Test func trimmedDurationReflectsTrimChanges() {
        let duration = CMTime(seconds: 10, preferredTimescale: 600)
        let asset = AVMutableComposition()
        let clip = Clip(asset: asset, duration: duration)

        clip.trimStart = CMTime(seconds: 2, preferredTimescale: 600)
        clip.trimEnd = CMTime(seconds: 8, preferredTimescale: 600)

        let expected = CMTime(seconds: 6, preferredTimescale: 600)
        #expect(clip.trimmedDuration == expected)
    }

    @Test func trimmedTimeRangeIsCorrect() {
        let duration = CMTime(seconds: 10, preferredTimescale: 600)
        let asset = AVMutableComposition()
        let clip = Clip(asset: asset, duration: duration)

        clip.trimStart = CMTime(seconds: 3, preferredTimescale: 600)
        clip.trimEnd = CMTime(seconds: 7, preferredTimescale: 600)

        #expect(clip.trimmedTimeRange.start == clip.trimStart)
        #expect(clip.trimmedTimeRange.end == clip.trimEnd)
    }

    @Test func eachClipHasUniqueID() {
        let duration = CMTime(seconds: 5, preferredTimescale: 600)
        let asset = AVMutableComposition()
        let clip1 = Clip(asset: asset, duration: duration)
        let clip2 = Clip(asset: asset, duration: duration)

        #expect(clip1.id != clip2.id)
    }
}
