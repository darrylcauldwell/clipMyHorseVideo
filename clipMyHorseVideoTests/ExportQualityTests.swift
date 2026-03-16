import AVFoundation
import Testing

@testable import clipMyHorseVideo

struct ExportQualityTests {
    @Test func allCasesHavePresetNames() {
        for quality in ExportQuality.allCases {
            #expect(!quality.presetName.isEmpty)
        }
    }

    @Test func originalUsesHighestQuality() {
        #expect(ExportQuality.original.presetName == AVAssetExportPresetHighestQuality)
    }

    @Test func hd1080Uses1920x1080() {
        #expect(ExportQuality.hd1080.presetName == AVAssetExportPreset1920x1080)
    }

    @Test func hd720Uses1280x720() {
        #expect(ExportQuality.hd720.presetName == AVAssetExportPreset1280x720)
    }

    @Test func allCasesHaveDescriptions() {
        for quality in ExportQuality.allCases {
            #expect(!quality.description.isEmpty)
        }
    }
}
