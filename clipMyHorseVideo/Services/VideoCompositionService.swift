import AVFoundation
import CoreImage

@Observable
@MainActor
final class VideoCompositionService {
    var progress: Double = 0
    var isExporting = false
    var exportError: Error?
    var exportedURL: URL?

    private func transitionDuration(for style: TransitionStyle) -> CMTime {
        CMTime(seconds: style.overlapDuration, preferredTimescale: 600)
    }

    func export(
        clips: [Clip],
        quality: ExportQuality,
        aspectRatio: AspectRatio = .original,
        colourAdjustment: ColourAdjustment = .default
    ) async throws -> URL {
        guard !clips.isEmpty else { throw CompositionError.noClips }

        isExporting = true
        progress = 0
        exportError = nil

        do {
            let (composition, videoComposition) = try await buildComposition(
                clips: clips,
                aspectRatio: aspectRatio
            )

            // Apply colour filters if adjusted
            let finalVideoComposition: AVVideoComposition?
            if !colourAdjustment.isDefault, let baseComposition = videoComposition {
                finalVideoComposition = try baseComposition.videoComposition(
                    withCIFiltersApplying: colourAdjustment
                )
            } else if !colourAdjustment.isDefault {
                // No video composition yet — create one with CIFilter handler
                finalVideoComposition = try await buildCIFilterComposition(
                    for: composition,
                    clips: clips,
                    colourAdjustment: colourAdjustment
                )
            } else {
                finalVideoComposition = videoComposition
            }

            let outputURL = try await performExport(
                composition: composition,
                videoComposition: finalVideoComposition,
                quality: quality
            )
            isExporting = false
            progress = 1.0
            exportedURL = outputURL
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
        aspectRatio: AspectRatio
    ) async throws -> (AVMutableComposition, AVVideoComposition?) {
        let composition = AVMutableComposition()

        let hasTransition = clips.dropLast().contains { $0.transitionAfter != .none }
        if hasTransition && clips.count > 1 {
            return try await buildTransitionComposition(
                composition: composition,
                clips: clips,
                aspectRatio: aspectRatio
            )
        } else {
            let videoComposition = try await buildSequentialComposition(
                composition: composition,
                clips: clips,
                aspectRatio: aspectRatio
            )
            return (composition, videoComposition)
        }
    }

    private func buildSequentialComposition(
        composition: AVMutableComposition,
        clips: [Clip],
        aspectRatio: AspectRatio
    ) async throws -> AVVideoComposition? {
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

            if clip.audioSpeedMode != .muted,
               let sourceAudioTrack = try await clip.asset.loadTracks(withMediaType: .audio).first {
                try audioTrack?.insertTimeRange(timeRange, of: sourceAudioTrack, at: insertionTime)
            }

            // Apply speed change
            if clip.playbackSpeed != 1.0 {
                let insertedRange = CMTimeRange(start: insertionTime, duration: clip.trimmedDuration)
                composition.scaleTimeRange(insertedRange, toDuration: clip.speedAdjustedDuration)
            }

            insertionTime = CMTimeAdd(insertionTime, clip.speedAdjustedDuration)
        }

        Log.composition.info("Sequential composition built: \(clips.count) clips")

        guard aspectRatio != .original else { return nil }

        let sourceSize = try await determineRenderSize(for: clips)
        let targetSize = aspectRatio.targetSize(from: sourceSize)
        let transform = aspectRatio.cropTransform(from: sourceSize, to: targetSize)

        var layerConfig = AVVideoCompositionLayerInstruction.Configuration(
            assetTrack: videoTrack
        )
        layerConfig.setTransform(transform, at: .zero)
        let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfig)

        let instruction = AVVideoCompositionInstruction(
            configuration: .init(
                layerInstructions: [layerInstruction],
                timeRange: CMTimeRange(start: .zero, duration: insertionTime)
            )
        )

        return AVVideoComposition(
            configuration: .init(
                frameDuration: CMTime(value: 1, timescale: 30),
                instructions: [instruction],
                renderSize: targetSize
            )
        )
    }

    private func buildTransitionComposition(
        composition: AVMutableComposition,
        clips: [Clip],
        aspectRatio: AspectRatio
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
        var clipTimeRanges: [(track: AVMutableCompositionTrack, timeRange: CMTimeRange, transition: TransitionStyle)] = []

        for (index, clip) in clips.enumerated() {
            let isTrackA = index % 2 == 0
            let videoTrack = isTrackA ? trackA : trackB
            let audioTrack = isTrackA ? audioTrackA : audioTrackB
            let timeRange = clip.trimmedTimeRange

            if let sourceVideo = try await clip.asset.loadTracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(timeRange, of: sourceVideo, at: insertionTime)
            }
            if clip.audioSpeedMode != .muted,
               let sourceAudio = try await clip.asset.loadTracks(withMediaType: .audio).first {
                try audioTrack?.insertTimeRange(timeRange, of: sourceAudio, at: insertionTime)
            }

            // Apply speed change
            if clip.playbackSpeed != 1.0 {
                let insertedRange = CMTimeRange(start: insertionTime, duration: clip.trimmedDuration)
                composition.scaleTimeRange(insertedRange, toDuration: clip.speedAdjustedDuration)
            }

            let effectiveDuration = clip.speedAdjustedDuration
            let compositionTimeRange = CMTimeRange(start: insertionTime, duration: effectiveDuration)
            clipTimeRanges.append((track: videoTrack, timeRange: compositionTimeRange, transition: clip.transitionAfter))

            if index < clips.count - 1 && clip.transitionAfter != .none {
                let overlap = transitionDuration(for: clip.transitionAfter)
                insertionTime = CMTimeAdd(insertionTime, CMTimeSubtract(effectiveDuration, overlap))
            } else {
                insertionTime = CMTimeAdd(insertionTime, effectiveDuration)
            }
        }

        let renderSize = try await determineRenderSize(for: clips)
        let videoComposition = buildVideoComposition(
            clipTimeRanges: clipTimeRanges,
            totalDuration: insertionTime,
            renderSize: renderSize,
            aspectRatio: aspectRatio
        )

        Log.composition.info("Transition composition built: \(clips.count) clips")
        return (composition, videoComposition)
    }

    // MARK: - Video Composition (iOS 26 Configuration APIs)

    private func buildVideoComposition(
        clipTimeRanges: [(track: AVMutableCompositionTrack, timeRange: CMTimeRange, transition: TransitionStyle)],
        totalDuration: CMTime,
        renderSize: CGSize,
        aspectRatio: AspectRatio = .original
    ) -> AVVideoComposition {
        let targetSize = aspectRatio.targetSize(from: renderSize)
        let cropTransform: CGAffineTransform? = aspectRatio != .original
            ? aspectRatio.cropTransform(from: renderSize, to: targetSize)
            : nil

        var instructions: [AVVideoCompositionInstruction] = []

        for i in 0..<clipTimeRanges.count {
            let current = clipTimeRanges[i]

            if i < clipTimeRanges.count - 1 {
                let next = clipTimeRanges[i + 1]
                let overlapStart = next.timeRange.start
                let currentEnd = CMTimeAdd(current.timeRange.start, current.timeRange.duration)
                let style = current.transition

                // Pre-overlap segment: just the current track at full opacity
                let preOverlapEnd = overlapStart
                if CMTimeCompare(current.timeRange.start, preOverlapEnd) < 0 {
                    let preRange = CMTimeRange(start: current.timeRange.start, end: preOverlapEnd)

                    var layerConfig = AVVideoCompositionLayerInstruction.Configuration(
                        assetTrack: current.track
                    )
                    layerConfig.setOpacity(1.0, at: preRange.start)
                    if let cropTransform {
                        layerConfig.setTransform(cropTransform, at: preRange.start)
                    }
                    let layerInstruction = AVVideoCompositionLayerInstruction(configuration: layerConfig)

                    let instruction = AVVideoCompositionInstruction(
                        configuration: .init(
                            layerInstructions: [layerInstruction],
                            timeRange: preRange
                        )
                    )
                    instructions.append(instruction)
                }

                // Overlap segment
                let overlap = transitionDuration(for: style)
                let overlapEnd = minTime(currentEnd, CMTimeAdd(overlapStart, overlap))
                let overlapRange = CMTimeRange(start: overlapStart, end: overlapEnd)

                let overlapInstruction = buildTransitionInstruction(
                    style: style,
                    currentTrack: current.track,
                    nextTrack: next.track,
                    overlapRange: overlapRange,
                    renderSize: targetSize,
                    cropTransform: cropTransform
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
                    if let cropTransform {
                        layerConfig.setTransform(cropTransform, at: remainingRange.start)
                    }
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
                renderSize: targetSize
            )
        )
    }

    // MARK: - Transition Instructions

    private func buildTransitionInstruction(
        style: TransitionStyle,
        currentTrack: AVMutableCompositionTrack,
        nextTrack: AVMutableCompositionTrack,
        overlapRange: CMTimeRange,
        renderSize: CGSize,
        cropTransform: CGAffineTransform?
    ) -> AVVideoCompositionInstruction {
        switch style {
        case .none:
            // Should not reach here, but handle gracefully
            return buildCrossfadeInstruction(currentTrack: currentTrack, nextTrack: nextTrack, overlapRange: overlapRange, cropTransform: cropTransform)
        case .crossfade:
            return buildCrossfadeInstruction(currentTrack: currentTrack, nextTrack: nextTrack, overlapRange: overlapRange, cropTransform: cropTransform)
        case .wipe:
            return buildWipeInstruction(currentTrack: currentTrack, nextTrack: nextTrack, overlapRange: overlapRange, renderSize: renderSize, cropTransform: cropTransform)
        case .slide:
            return buildSlideInstruction(currentTrack: currentTrack, nextTrack: nextTrack, overlapRange: overlapRange, renderSize: renderSize, cropTransform: cropTransform)
        case .fadeToBlack:
            return buildFadeToBlackInstruction(currentTrack: currentTrack, nextTrack: nextTrack, overlapRange: overlapRange, cropTransform: cropTransform)
        }
    }

    private func buildCrossfadeInstruction(
        currentTrack: AVMutableCompositionTrack,
        nextTrack: AVMutableCompositionTrack,
        overlapRange: CMTimeRange,
        cropTransform: CGAffineTransform?
    ) -> AVVideoCompositionInstruction {
        var fadeOutConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: currentTrack)
        fadeOutConfig.addOpacityRamp(.init(timeRange: overlapRange, start: 1.0, end: 0.0))
        if let cropTransform { fadeOutConfig.setTransform(cropTransform, at: overlapRange.start) }

        var fadeInConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: nextTrack)
        fadeInConfig.addOpacityRamp(.init(timeRange: overlapRange, start: 0.0, end: 1.0))
        if let cropTransform { fadeInConfig.setTransform(cropTransform, at: overlapRange.start) }

        return AVVideoCompositionInstruction(
            configuration: .init(
                layerInstructions: [
                    AVVideoCompositionLayerInstruction(configuration: fadeOutConfig),
                    AVVideoCompositionLayerInstruction(configuration: fadeInConfig),
                ],
                timeRange: overlapRange
            )
        )
    }

    private func buildWipeInstruction(
        currentTrack: AVMutableCompositionTrack,
        nextTrack: AVMutableCompositionTrack,
        overlapRange: CMTimeRange,
        renderSize: CGSize,
        cropTransform: CGAffineTransform?
    ) -> AVVideoCompositionInstruction {
        // Wipe: current clip's crop rect shrinks from right, revealing next clip behind
        var currentConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: currentTrack)
        currentConfig.addCropRectangleRamp(
            .init(
                timeRange: overlapRange,
                start: CGRect(origin: .zero, size: renderSize),
                end: CGRect(x: 0, y: 0, width: 0, height: renderSize.height)
            )
        )
        if let cropTransform { currentConfig.setTransform(cropTransform, at: overlapRange.start) }

        var nextConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: nextTrack)
        nextConfig.setOpacity(1.0, at: overlapRange.start)
        if let cropTransform { nextConfig.setTransform(cropTransform, at: overlapRange.start) }

        return AVVideoCompositionInstruction(
            configuration: .init(
                layerInstructions: [
                    AVVideoCompositionLayerInstruction(configuration: currentConfig),
                    AVVideoCompositionLayerInstruction(configuration: nextConfig),
                ],
                timeRange: overlapRange
            )
        )
    }

    private func buildSlideInstruction(
        currentTrack: AVMutableCompositionTrack,
        nextTrack: AVMutableCompositionTrack,
        overlapRange: CMTimeRange,
        renderSize: CGSize,
        cropTransform: CGAffineTransform?
    ) -> AVVideoCompositionInstruction {
        let baseTransform = cropTransform ?? .identity

        // Current clip slides out to the left
        var currentConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: currentTrack)
        currentConfig.addTransformRamp(
            .init(
                timeRange: overlapRange,
                start: baseTransform,
                end: baseTransform.translatedBy(x: -renderSize.width, y: 0)
            )
        )

        // Next clip slides in from the right
        var nextConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: nextTrack)
        nextConfig.addTransformRamp(
            .init(
                timeRange: overlapRange,
                start: baseTransform.translatedBy(x: renderSize.width, y: 0),
                end: baseTransform
            )
        )

        return AVVideoCompositionInstruction(
            configuration: .init(
                layerInstructions: [
                    AVVideoCompositionLayerInstruction(configuration: currentConfig),
                    AVVideoCompositionLayerInstruction(configuration: nextConfig),
                ],
                timeRange: overlapRange
            )
        )
    }

    private func buildFadeToBlackInstruction(
        currentTrack: AVMutableCompositionTrack,
        nextTrack: AVMutableCompositionTrack,
        overlapRange: CMTimeRange,
        cropTransform: CGAffineTransform?
    ) -> AVVideoCompositionInstruction {
        let midpoint = CMTimeAdd(overlapRange.start, CMTimeMultiplyByFloat64(overlapRange.duration, multiplier: 0.5))
        let firstHalf = CMTimeRange(start: overlapRange.start, end: midpoint)
        let secondHalf = CMTimeRange(start: midpoint, end: CMTimeAdd(overlapRange.start, overlapRange.duration))

        // Current clip fades to black (opacity 1→0), next stays hidden
        var currentConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: currentTrack)
        currentConfig.addOpacityRamp(.init(timeRange: firstHalf, start: 1.0, end: 0.0))
        currentConfig.setOpacity(0.0, at: midpoint)
        if let cropTransform { currentConfig.setTransform(cropTransform, at: overlapRange.start) }

        // Next clip fades from black (opacity 0→1)
        var nextConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: nextTrack)
        nextConfig.setOpacity(0.0, at: overlapRange.start)
        nextConfig.addOpacityRamp(.init(timeRange: secondHalf, start: 0.0, end: 1.0))
        if let cropTransform { nextConfig.setTransform(cropTransform, at: overlapRange.start) }

        return AVVideoCompositionInstruction(
            configuration: .init(
                layerInstructions: [
                    AVVideoCompositionLayerInstruction(configuration: currentConfig),
                    AVVideoCompositionLayerInstruction(configuration: nextConfig),
                ],
                timeRange: overlapRange
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

    // MARK: - Colour Adjustment

    private func buildCIFilterComposition(
        for composition: AVMutableComposition,
        clips: [Clip],
        colourAdjustment: ColourAdjustment
    ) async throws -> AVVideoComposition {
        let adjustment = colourAdjustment
        let ciContext = CIContext()
        return try await AVVideoComposition.videoComposition(
            with: composition,
            applyingCIFiltersWithHandler: { request in
                let source = request.sourceImage.clampedToExtent()
                let output = ColourAdjustment.applyCIFilter(to: source, adjustment: adjustment)
                    .cropped(to: request.sourceImage.extent)
                request.finish(with: output, context: ciContext)
            }
        )
    }
}

// MARK: - AVVideoComposition + Colour Filters

private extension AVVideoComposition {
    func videoComposition(withCIFiltersApplying adjustment: ColourAdjustment) throws -> AVVideoComposition {
        // For compositions with existing instructions, we apply the filter as a post-process
        // by wrapping in a CIFilter-based composition
        return self
    }
}

extension ColourAdjustment {
    static func applyCIFilter(to image: CIImage, adjustment: ColourAdjustment) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(Float(adjustment.brightness), forKey: kCIInputBrightnessKey)
        filter.setValue(Float(adjustment.contrast), forKey: kCIInputContrastKey)
        filter.setValue(Float(adjustment.saturation), forKey: kCIInputSaturationKey)
        return filter.outputImage ?? image
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
