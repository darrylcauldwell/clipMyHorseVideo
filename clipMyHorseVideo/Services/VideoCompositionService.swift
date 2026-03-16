import AVFoundation

@Observable
@MainActor
final class VideoCompositionService {
    var progress: Double = 0
    var isExporting = false
    var exportError: Error?

    private let crossfadeDuration = CMTime(seconds: 0.5, preferredTimescale: 600)

    func export(
        clips: [Clip],
        quality: ExportQuality,
        transition: TransitionStyle
    ) async throws -> URL {
        guard !clips.isEmpty else { throw CompositionError.noClips }

        isExporting = true
        progress = 0
        exportError = nil

        do {
            let (composition, videoComposition) = try await buildComposition(
                clips: clips,
                transition: transition
            )
            let outputURL = try await performExport(
                composition: composition,
                videoComposition: videoComposition,
                quality: quality
            )
            isExporting = false
            progress = 1.0
            return outputURL
        } catch {
            exportError = error
            isExporting = false
            throw error
        }
    }

    // MARK: - Composition Building

    private func buildComposition(
        clips: [Clip],
        transition: TransitionStyle
    ) async throws -> (AVMutableComposition, AVVideoComposition?) {
        let composition = AVMutableComposition()

        if transition == .crossfade && clips.count > 1 {
            return try await buildCrossfadeComposition(composition: composition, clips: clips)
        } else {
            try await buildSequentialComposition(composition: composition, clips: clips)
            return (composition, nil)
        }
    }

    private func buildSequentialComposition(
        composition: AVMutableComposition,
        clips: [Clip]
    ) async throws {
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw CompositionError.failedToCreateTrack }

        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var insertionTime = CMTime.zero

        for clip in clips {
            let timeRange = clip.trimmedTimeRange

            if let sourceVideoTrack = try await clip.asset.loadTracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: insertionTime)
            }

            if let sourceAudioTrack = try await clip.asset.loadTracks(withMediaType: .audio).first {
                try audioTrack?.insertTimeRange(timeRange, of: sourceAudioTrack, at: insertionTime)
            }

            insertionTime = CMTimeAdd(insertionTime, clip.trimmedDuration)
        }

        Log.composition.info("Sequential composition built: \(clips.count) clips")
    }

    private func buildCrossfadeComposition(
        composition: AVMutableComposition,
        clips: [Clip]
    ) async throws -> (AVMutableComposition, AVVideoComposition) {
        guard let trackA = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let trackB = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw CompositionError.failedToCreateTrack }

        let audioTrackA = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let audioTrackB = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var insertionTime = CMTime.zero
        var clipTimeRanges: [(track: AVMutableCompositionTrack, timeRange: CMTimeRange)] = []

        for (index, clip) in clips.enumerated() {
            let isTrackA = index % 2 == 0
            let videoTrack = isTrackA ? trackA : trackB
            let audioTrack = isTrackA ? audioTrackA : audioTrackB
            let timeRange = clip.trimmedTimeRange

            if let sourceVideo = try await clip.asset.loadTracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(timeRange, of: sourceVideo, at: insertionTime)
            }
            if let sourceAudio = try await clip.asset.loadTracks(withMediaType: .audio).first {
                try audioTrack?.insertTimeRange(timeRange, of: sourceAudio, at: insertionTime)
            }

            let compositionTimeRange = CMTimeRange(start: insertionTime, duration: clip.trimmedDuration)
            clipTimeRanges.append((track: videoTrack, timeRange: compositionTimeRange))

            if index < clips.count - 1 {
                insertionTime = CMTimeAdd(insertionTime, CMTimeSubtract(clip.trimmedDuration, crossfadeDuration))
            } else {
                insertionTime = CMTimeAdd(insertionTime, clip.trimmedDuration)
            }
        }

        let renderSize = try await determineRenderSize(for: clips)
        let videoComposition = buildVideoComposition(
            clipTimeRanges: clipTimeRanges,
            totalDuration: insertionTime,
            renderSize: renderSize
        )

        Log.composition.info("Crossfade composition built: \(clips.count) clips")
        return (composition, videoComposition)
    }

    // MARK: - Video Composition (iOS 26 Configuration APIs)

    private func buildVideoComposition(
        clipTimeRanges: [(track: AVMutableCompositionTrack, timeRange: CMTimeRange)],
        totalDuration: CMTime,
        renderSize: CGSize
    ) -> AVVideoComposition {
        var instructions: [AVVideoCompositionInstruction] = []

        for i in 0..<clipTimeRanges.count {
            let current = clipTimeRanges[i]

            if i < clipTimeRanges.count - 1 {
                let next = clipTimeRanges[i + 1]
                let overlapStart = next.timeRange.start
                let currentEnd = CMTimeAdd(current.timeRange.start, current.timeRange.duration)

                // Pre-overlap segment: just the current track at full opacity
                let preOverlapEnd = overlapStart
                if CMTimeCompare(current.timeRange.start, preOverlapEnd) < 0 {
                    let preRange = CMTimeRange(start: current.timeRange.start, end: preOverlapEnd)

                    var layerConfig = AVVideoCompositionLayerInstruction.Configuration(
                        assetTrack: current.track
                    )
                    layerConfig.setOpacity(1.0, at: preRange.start)
                    let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfig)

                    let instruction = AVVideoCompositionInstruction(
                        configuration: .init(
                            layerInstructions: [layerInstruction],
                            timeRange: preRange
                        )
                    )
                    instructions.append(instruction)
                }

                // Overlap segment: crossfade from current to next
                let overlapEnd = minTime(currentEnd, CMTimeAdd(overlapStart, crossfadeDuration))
                let overlapRange = CMTimeRange(start: overlapStart, end: overlapEnd)

                // Current track fades out
                var fadeOutConfig = AVVideoCompositionLayerInstruction.Configuration(
                    assetTrack: current.track
                )
                fadeOutConfig.addOpacityRamp(
                    AVVideoCompositionLayerInstruction.OpacityRamp(
                        timeRange: overlapRange,
                        start: 1.0,
                        end: 0.0
                    )
                )
                let fadeOutInstruction = AVVideoCompositionLayerInstruction(configuration: fadeOutConfig)

                // Next track fades in
                var fadeInConfig = AVVideoCompositionLayerInstruction.Configuration(
                    assetTrack: next.track
                )
                fadeInConfig.addOpacityRamp(
                    AVVideoCompositionLayerInstruction.OpacityRamp(
                        timeRange: overlapRange,
                        start: 0.0,
                        end: 1.0
                    )
                )
                let fadeInInstruction = AVVideoCompositionLayerInstruction(configuration: fadeInConfig)

                let overlapInstruction = AVVideoCompositionInstruction(
                    configuration: .init(
                        layerInstructions: [fadeOutInstruction, fadeInInstruction],
                        timeRange: overlapRange
                    )
                )
                instructions.append(overlapInstruction)
            } else {
                // Last clip: remaining segment after previous overlap
                let segmentStart = current.timeRange.start
                let segmentEnd = CMTimeAdd(current.timeRange.start, current.timeRange.duration)

                let lastInstructionEnd = instructions.last.map {
                    CMTimeAdd($0.timeRange.start, $0.timeRange.duration)
                } ?? .zero

                let effectiveStart = maxTime(segmentStart, lastInstructionEnd)
                if CMTimeCompare(effectiveStart, segmentEnd) < 0 {
                    let remainingRange = CMTimeRange(start: effectiveStart, end: segmentEnd)

                    var layerConfig = AVVideoCompositionLayerInstruction.Configuration(
                        assetTrack: current.track
                    )
                    layerConfig.setOpacity(1.0, at: remainingRange.start)
                    let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfig)

                    let instruction = AVVideoCompositionInstruction(
                        configuration: .init(
                            layerInstructions: [layerInstruction],
                            timeRange: remainingRange
                        )
                    )
                    instructions.append(instruction)
                }
            }
        }

        return AVVideoComposition(
            configuration: .init(
                frameDuration: CMTime(value: 1, timescale: 30),
                instructions: instructions,
                renderSize: renderSize
            )
        )
    }

    // MARK: - Export

    private func performExport(
        composition: AVMutableComposition,
        videoComposition: AVVideoComposition?,
        quality: ExportQuality
    ) async throws -> URL {
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: quality.presetName
        ) else { throw CompositionError.exportSessionFailed }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        exportSession.videoComposition = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true

        Log.export.info("Starting export with preset: \(quality.presetName)")

        // Monitor progress in background
        let progressTask = Task.detached { [weak self] in
            for await state in exportSession.states(updateInterval: 0.1) {
                switch state {
                case .pending, .waiting:
                    break
                case .exporting(let p):
                    await MainActor.run { self?.progress = p.fractionCompleted }
                @unknown default:
                    break
                }
            }
        }

        defer { progressTask.cancel() }

        try await exportSession.export(to: outputURL, as: .mov)

        Log.export.info("Export completed successfully")
        return outputURL
    }

    // MARK: - Helpers

    private func determineRenderSize(for clips: [Clip]) async throws -> CGSize {
        for clip in clips {
            if let track = try await clip.asset.loadTracks(withMediaType: .video).first {
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let transformedSize = size.applying(transform)
                return CGSize(
                    width: abs(transformedSize.width),
                    height: abs(transformedSize.height)
                )
            }
        }
        return CGSize(width: 1920, height: 1080)
    }

    private func maxTime(_ a: CMTime, _ b: CMTime) -> CMTime {
        CMTimeCompare(a, b) >= 0 ? a : b
    }

    private func minTime(_ a: CMTime, _ b: CMTime) -> CMTime {
        CMTimeCompare(a, b) <= 0 ? a : b
    }
}

enum CompositionError: LocalizedError {
    case noClips
    case failedToCreateTrack
    case exportSessionFailed
    case exportFailed
    case exportCancelled

    var errorDescription: String? {
        switch self {
        case .noClips: "No clips to export."
        case .failedToCreateTrack: "Failed to create composition track."
        case .exportSessionFailed: "Failed to create export session."
        case .exportFailed: "Video export failed."
        case .exportCancelled: "Export was cancelled."
        }
    }
}
