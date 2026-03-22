import Testing

@testable import clipMyHorseVideo

struct JumpEvaluationTests {
    // Helper to create a minimal algorithm jump result
    private func makeJump(moment: Double, confidence: Double = 0.8) -> JumpDetectionService.DetailedJumpResult {
        JumpDetectionService.DetailedJumpResult(
            moment: moment,
            confidence: confidence,
            peakIndex: 0,
            arcWindowStart: 0,
            arcWindowEnd: 0
        )
    }

    // Helper to create a minimal label
    private func makeLabel(time: Double) -> ManualJumpLabel {
        ManualJumpLabel(timeSeconds: time)
    }

    @Test func perfectMatch() {
        let labels = [makeLabel(time: 10), makeLabel(time: 25), makeLabel(time: 40)]
        let jumps = [makeJump(moment: 10.5), makeJump(moment: 24.8), makeJump(moment: 40.2)]

        let result = JumpEvaluationService.compare(
            labels: labels,
            algorithmJumps: jumps,
            signals: [],
            tolerance: 2.0
        )

        #expect(result.truePositives.count == 3)
        #expect(result.falsePositives.isEmpty)
        #expect(result.missedJumps.isEmpty)
        #expect(result.precision == 1.0)
        #expect(result.recall == 1.0)
    }

    @Test func falsePositiveDetected() {
        let labels = [makeLabel(time: 10)]
        let jumps = [makeJump(moment: 10.5), makeJump(moment: 30)]

        let result = JumpEvaluationService.compare(
            labels: labels,
            algorithmJumps: jumps,
            signals: [],
            tolerance: 2.0
        )

        #expect(result.truePositives.count == 1)
        #expect(result.falsePositives.count == 1)
        #expect(result.falsePositives[0].algorithmTimeSeconds == 30)
        #expect(result.missedJumps.isEmpty)
        #expect(result.precision == 0.5)
        #expect(result.recall == 1.0)
    }

    @Test func missedJumpDetected() {
        let labels = [makeLabel(time: 10), makeLabel(time: 25)]
        let jumps = [makeJump(moment: 10.5)]

        let result = JumpEvaluationService.compare(
            labels: labels,
            algorithmJumps: jumps,
            signals: [],
            tolerance: 2.0
        )

        #expect(result.truePositives.count == 1)
        #expect(result.falsePositives.isEmpty)
        #expect(result.missedJumps.count == 1)
        #expect(result.missedJumps[0].labelTimeSeconds == 25)
        #expect(result.precision == 1.0)
        #expect(result.recall == 0.5)
    }

    @Test func toleranceWindowRespected() {
        let labels = [makeLabel(time: 10)]
        let jumps = [makeJump(moment: 13)] // 3s offset > 2s tolerance

        let result = JumpEvaluationService.compare(
            labels: labels,
            algorithmJumps: jumps,
            signals: [],
            tolerance: 2.0
        )

        #expect(result.truePositives.isEmpty)
        #expect(result.falsePositives.count == 1)
        #expect(result.missedJumps.count == 1)
        #expect(result.precision == 0)
        #expect(result.recall == 0)
    }
}
