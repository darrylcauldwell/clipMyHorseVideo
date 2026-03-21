import SwiftUI

struct ExportProgressView: View {
    let clips: [Clip]
    let quality: ExportQuality
    var aspectRatio: AspectRatio = .original
    var colourAdjustment: ColourAdjustment = .default
    var backgroundMusic: BackgroundMusic?
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var compositionService = VideoCompositionService()
    @State private var exportState: ExportState = .preparing
    @State private var errorMessage: String?
    @State private var exportedFileURL: URL?
    @State private var exportCompleteTrigger = 0

    enum ExportState {
        case preparing
        case exporting
        case saving
        case completed
        case failed
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            switch exportState {
            case .preparing:
                ProgressView()
                    .scaleEffect(1.5)
                Text("Preparing...")
                    .font(.headline)

            case .exporting:
                ProgressView(value: Double(compositionService.progress))
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 48)
                Text("Exporting... \(Int(compositionService.progress * 100))%")
                    .font(.headline)
                    .monospacedDigit()

            case .saving:
                ProgressView()
                    .scaleEffect(1.5)
                Text("Saving to Photos...")
                    .font(.headline)

            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                Text("Video Saved!")
                    .font(.title2.bold())
                Text("Your merged video has been saved to your photo library.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)
                Text("Export Failed")
                    .font(.title2.bold())
                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            Spacer()

            if exportState == .completed {
                VStack(spacing: 12) {
                    if let exportedFileURL {
                        ShareLink(
                            item: exportedFileURL,
                            subject: Text("My Round"),
                            message: Text("Check out my showjumping round!")
                        ) {
                            Label("Share Your Round", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal, 32)
                    }

                    Button {
                        cleanUpExportedFile()
                        onComplete()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.secondary.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 32)
                }
            }

            if exportState == .failed {
                HStack(spacing: 16) {
                    Button("Dismiss") { dismiss() }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.secondary.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Button("Retry") {
                        Task { await startExport() }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 32)
            }
        }
        .padding(.bottom, 32)
        .navigationTitle("Exporting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if exportState != .completed {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(exportState == .exporting || exportState == .saving)
        .sensoryFeedback(.success, trigger: exportCompleteTrigger)
        .onDisappear { cleanUpExportedFile() }
        .task { await startExport() }
    }

    private func startExport() async {
        exportState = .preparing
        errorMessage = nil

        do {
            exportState = .exporting
            let outputURL = try await compositionService.export(
                clips: clips,
                quality: quality,
                aspectRatio: aspectRatio,
                colourAdjustment: colourAdjustment,
                backgroundMusic: backgroundMusic
            )

            exportState = .saving
            try await PhotoLibraryService.saveToPhotoLibrary(url: outputURL)

            // Keep temp file for sharing; cleaned up when user taps Done or view disappears
            exportedFileURL = outputURL

            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                exportState = .completed
            }
            exportCompleteTrigger += 1
        } catch {
            errorMessage = error.localizedDescription
            exportState = .failed
            Log.export.error("Export pipeline failed: \(error.localizedDescription)")
        }
    }

    private func cleanUpExportedFile() {
        if let exportedFileURL {
            try? FileManager.default.removeItem(at: exportedFileURL)
            self.exportedFileURL = nil
        }
    }
}
