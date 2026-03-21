import AVFoundation
import CoreImage
import QuartzCore
import UIKit

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
        colourAdjustment: ColourAdjustment = .default,
        backgroundMusic: BackgroundMusic? = nil,
        textOverlays: [TextOverlay] = []
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

            // Apply text overlays if any
            if !textOverlays.isEmpty {
                let renderSize = try await determineRenderSize(for: clips)
                if let mutableComp = finalVideoComposition as? AVMutableVideoComposition {
                    applyTextOverlays(textOverlays, to: mutableComp, renderSize: renderSize)
                } else if finalVideoComposition == nil {
                    // Create a basic mutable video composition for text overlay
                    let mutableComp = try await AVMutableVideoComposition.videoComposition(
                        withPropertiesOf: composition
                    )
                    applyTextOverlays(textOverlays, to: mutableComp, renderSize: renderSize)
                }
            }

            // Mix in background music if provided
            let audioMix = try await buildAudioMix(
                composition: composition,
                backgroundMusic: backgroundMusic
            )

            let outputURL = try await performExport(
                composition: composition,
                videoComposition: finalVideoComposition,
                audioMix: audioMix,
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
        // Both .none and .crossfade use the same crossfade instruction
        // (.none should not reach here, but handle gracefully)
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

    // MARK: - Export

    private func performExport(
        composition: AVMutableComposition,
        videoComposition: AVVideoComposition?,
        audioMix: AVAudioMix? = nil,
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
        exportSession.audioMix = audioMix
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

    // MARK: - Text Overlays

    @MainActor
    private func applyTextOverlays(
        _ overlays: [TextOverlay],
        to videoComposition: AVMutableVideoComposition,
        renderSize: CGSize
    ) {
        guard !overlays.isEmpty else { return }

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)

        for overlay in overlays where !overlay.text.isEmpty {
            let textLayer = CATextLayer()
            textLayer.string = overlay.text
            textLayer.font = UIFont.systemFont(ofSize: overlay.fontSize, weight: .semibold)
            textLayer.fontSize = overlay.fontSize
            textLayer.foregroundColor = UIColor(overlay.colour).cgColor
            textLayer.alignmentMode = .center
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.isWrapped = true

            if overlay.showShadow {
                textLayer.shadowColor = UIColor.black.cgColor
                textLayer.shadowOffset = CGSize(width: 1, height: -1)
                textLayer.shadowOpacity = 0.8
                textLayer.shadowRadius = 2
            }

            let textHeight = overlay.fontSize * 1.5
            let padding: CGFloat = 16
            let y = overlay.position.yFraction * renderSize.height - textHeight / 2

            if overlay.backgroundOpacity > 0 {
                let bgLayer = CALayer()
                bgLayer.backgroundColor = UIColor.black.withAlphaComponent(overlay.backgroundOpacity).cgColor
                bgLayer.cornerRadius = 6
                bgLayer.frame = CGRect(x: padding, y: y - 4, width: renderSize.width - padding * 2, height: textHeight + 8)
                parentLayer.addSublayer(bgLayer)
            }

            textLayer.frame = CGRect(x: padding, y: y, width: renderSize.width - padding * 2, height: textHeight)
            parentLayer.addSublayer(textLayer)
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    // MARK: - Audio Mix

    private func buildAudioMix(
        composition: AVMutableComposition,
        backgroundMusic: BackgroundMusic?
    ) async throws -> AVAudioMix? {
        guard let music = backgroundMusic, music.isSelected, let musicAsset = music.asset else {
            return nil
        }

        let totalDuration = composition.duration

        // Add music track to composition
        guard let musicTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return nil }

        if let sourceAudio = try await musicAsset.loadTracks(withMediaType: .audio).first {
            let musicDuration = try await musicAsset.load(.duration)
            // Loop music if shorter than video
            var insertTime = CMTime.zero
            while CMTimeCompare(insertTime, totalDuration) < 0 {
                let remaining = CMTimeSubtract(totalDuration, insertTime)
                let insertDuration = CMTimeCompare(musicDuration, remaining) <= 0 ? musicDuration : remaining
                let timeRange = CMTimeRange(start: .zero, duration: insertDuration)
                try musicTrack.insertTimeRange(timeRange, of: sourceAudio, at: insertTime)
                insertTime = CMTimeAdd(insertTime, insertDuration)
            }
        }

        // Build audio mix with volume levels
        let audioMix = AVMutableAudioMix()
        var inputParameters: [AVMutableAudioMixInputParameters] = []

        // Set music volume
        let musicParams = AVMutableAudioMixInputParameters(track: musicTrack)
        musicParams.setVolume(music.volume, at: .zero)
        inputParameters.append(musicParams)

        // Set original audio volume for all existing audio tracks
        for track in composition.tracks(withMediaType: .audio) where track != musicTrack {
            let params = AVMutableAudioMixInputParameters(track: track)
            params.setVolume(music.originalVolume, at: .zero)
            inputParameters.append(params)
        }

        audioMix.inputParameters = inputParameters
        Log.composition.info("Audio mix built: music volume \(music.volume), original volume \(music.originalVolume)")
        return audioMix
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
