import AVFoundation
import Speech

enum TranscriptionService {
    /// Transcribe speech from a video clip's audio track.
    static func transcribe(asset: AVAsset, timeRange: CMTimeRange) async throws -> String {
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            guard status == .authorized else {
                throw TranscriptionError.notAuthorized
            }
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB")),
              recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        // Export audio segment to a temporary file
        let audioURL = try await extractAudio(from: asset, timeRange: timeRange)
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>) in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result, result.isFinal {
                    continuation.resume(returning: result)
                }
            }
        }

        Log.transcription.info("Transcription complete: \(result.bestTranscription.formattedString.prefix(100))")
        return result.bestTranscription.formattedString
    }

    /// Extract structured announcer info from raw transcript text.
    @MainActor
    static func extractAnnouncerInfo(from transcript: String) -> AnnouncerInfo {
        let info = AnnouncerInfo()
        info.rawTranscript = transcript

        let lowered = transcript.lowercased()

        // Pattern: "[rider] riding [horse]" or "[rider] on [horse]"
        let ridingPatterns = [
            try? NSRegularExpression(pattern: "(?:next|now|we have|in the ring)\\s+(?:is\\s+)?([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)+)\\s+(?:riding|on)\\s+([A-Z][a-z]+(?:\\s+[A-Za-z]+)*)", options: []),
            try? NSRegularExpression(pattern: "([A-Z][a-z]+(?:\\s+[A-Z][a-z]+)+)\\s+(?:riding|on)\\s+([A-Z][a-z]+(?:\\s+[A-Za-z]+)*)", options: [])
        ].compactMap { $0 }

        for pattern in ridingPatterns {
            if let match = pattern.firstMatch(in: transcript, range: NSRange(transcript.startIndex..., in: transcript)) {
                if let riderRange = Range(match.range(at: 1), in: transcript) {
                    info.riderName = String(transcript[riderRange])
                }
                if let horseRange = Range(match.range(at: 2), in: transcript) {
                    info.horseName = String(transcript[horseRange])
                }
                break
            }
        }

        // Look for class mentions
        let classPatterns = ["class", "competition", "grand prix", "open", "novice", "intermediate"]
        for pattern in classPatterns {
            if let range = lowered.range(of: pattern) {
                let start = lowered.index(range.lowerBound, offsetBy: -20, limitedBy: lowered.startIndex) ?? lowered.startIndex
                let end = lowered.index(range.upperBound, offsetBy: 30, limitedBy: lowered.endIndex) ?? lowered.endIndex
                let context = String(transcript[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                if info.className.isEmpty {
                    info.className = context
                }
            }
        }

        return info
    }

    // MARK: - Audio Extraction

    private static func extractAudio(from asset: AVAsset, timeRange: CMTimeRange) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw TranscriptionError.audioExtractionFailed
        }

        exportSession.outputFileType = .m4a
        exportSession.timeRange = timeRange
        try await exportSession.export(to: outputURL, as: .m4a)

        return outputURL
    }
}

enum TranscriptionError: LocalizedError {
    case notAuthorized
    case recognizerUnavailable
    case audioExtractionFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized: "Speech recognition access not authorized."
        case .recognizerUnavailable: "Speech recognizer is not available."
        case .audioExtractionFailed: "Failed to extract audio from video."
        }
    }
}
