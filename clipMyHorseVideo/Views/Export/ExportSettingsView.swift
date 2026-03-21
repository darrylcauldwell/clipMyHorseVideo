import CoreMedia
import SwiftUI
import UniformTypeIdentifiers

struct ExportSettingsView: View {
    let clips: [Clip]
    var textOverlays: [TextOverlay] = []
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var quality: ExportQuality = .hd1080
    @State private var aspectRatio: AspectRatio = .original
    @State private var colourAdjustment: ColourAdjustment = .default
    @State private var backgroundMusic = BackgroundMusic()
    @State private var showMusicPicker = false
    @State private var cropMode: CropMode = .centre
    @State private var stabilise = false
    @State private var stabilisationStrength: StabilisationStrength = .medium
    @State private var showProgress = false

    private var totalDurationTime: CMTime {
        var total = CMTime.zero
        for clip in clips {
            total = CMTimeAdd(total, clip.speedAdjustedDuration)
        }
        // Subtract overlap for each transition boundary
        for clip in clips.dropLast() where clip.transitionAfter != .none {
            let overlap = CMTime(seconds: clip.transitionAfter.overlapDuration, preferredTimescale: 600)
            total = CMTimeSubtract(total, overlap)
        }
        return total
    }

    private var totalDuration: String {
        totalDurationTime.formattedDuration
    }

    private var estimatedFileSize: String {
        let seconds = CMTimeGetSeconds(totalDurationTime)
        guard seconds > 0 else { return "0 bytes" }
        let bytes = Int64(seconds * quality.estimatedBitrate / 8 * aspectRatio.estimatedPixelMultiplier)
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }

    var body: some View {
        Form {
            Section("Summary") {
                LabeledContent("Clips", value: "\(clips.count)")
                LabeledContent("Est. Duration", value: totalDuration)
            }

            Section("Quality") {
                Picker("Export Quality", selection: $quality) {
                    ForEach(ExportQuality.allCases) { q in
                        Text(q.rawValue).tag(q)
                    }
                }
                .pickerStyle(.segmented)

                Text(quality.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Estimated size: ~\(estimatedFileSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Aspect Ratio") {
                Picker("Aspect Ratio", selection: $aspectRatio) {
                    ForEach(AspectRatio.allCases) { ratio in
                        Text(ratio.rawValue).tag(ratio)
                    }
                }
                .pickerStyle(.navigationLink)

                Text(aspectRatio.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if aspectRatio != .original {
                    Picker("Crop Mode", selection: $cropMode) {
                        ForEach(CropMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.iconName).tag(mode)
                        }
                    }

                    Text(cropMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Background Music") {
                if backgroundMusic.isSelected {
                    LabeledContent("Track", value: backgroundMusic.title)
                    HStack {
                        Text("Music Volume")
                            .font(.caption)
                        Slider(value: $backgroundMusic.volume, in: 0...1)
                    }
                    HStack {
                        Text("Original Audio")
                            .font(.caption)
                        Slider(value: $backgroundMusic.originalVolume, in: 0...1)
                    }
                    Button("Remove Music", role: .destructive) {
                        backgroundMusic.clear()
                    }
                } else {
                    Button {
                        showMusicPicker = true
                    } label: {
                        Label("Add Music", systemImage: "music.note")
                    }
                }

                Text("Import a royalty-free audio file from your device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fileImporter(
                isPresented: $showMusicPicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    guard url.startAccessingSecurityScopedResource() else { return }
                    // Copy to temp to retain access
                    let dest = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(url.pathExtension)
                    try? FileManager.default.copyItem(at: url, to: dest)
                    url.stopAccessingSecurityScopedResource()
                    backgroundMusic.url = dest
                    backgroundMusic.title = url.deletingPathExtension().lastPathComponent
                }
            }

            Section("Stabilisation") {
                Toggle("Stabilise Video", isOn: $stabilise)

                if stabilise {
                    Picker("Strength", selection: $stabilisationStrength) {
                        ForEach(StabilisationStrength.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(stabilisationStrength.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Stabilisation crops the frame slightly to allow for correction.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Colour Adjustment") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Brightness")
                            .font(.caption)
                        Slider(value: $colourAdjustment.brightness, in: -1.0...1.0)
                        Text(String(format: "%.1f", colourAdjustment.brightness))
                            .font(.caption.monospacedDigit())
                            .frame(width: 36)
                    }
                    HStack {
                        Text("Contrast")
                            .font(.caption)
                        Slider(value: $colourAdjustment.contrast, in: 0.5...2.0)
                        Text(String(format: "%.1f", colourAdjustment.contrast))
                            .font(.caption.monospacedDigit())
                            .frame(width: 36)
                    }
                    HStack {
                        Text("Saturation")
                            .font(.caption)
                        Slider(value: $colourAdjustment.saturation, in: 0.0...2.0)
                        Text(String(format: "%.1f", colourAdjustment.saturation))
                            .font(.caption.monospacedDigit())
                            .frame(width: 36)
                    }
                }

                if !colourAdjustment.isDefault {
                    Button("Reset Colour") {
                        colourAdjustment = .default
                    }
                    .foregroundStyle(.red)
                }
            }

            Section("Transitions") {
                ForEach(TransitionStyle.allCases) { style in
                    Button {
                        for clip in clips {
                            clip.transitionAfter = style
                        }
                    } label: {
                        Label("Set All to \(style.rawValue)", systemImage: style.iconName)
                    }
                }

                Text("Transitions can also be set individually on the timeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    showProgress = true
                } label: {
                    Label("Export Video", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
            }
        }
        .navigationTitle("Export Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $showProgress) {
            NavigationStack {
                ExportProgressView(
                    clips: clips,
                    quality: quality,
                    aspectRatio: aspectRatio,
                    colourAdjustment: colourAdjustment,
                    backgroundMusic: backgroundMusic,
                    textOverlays: textOverlays
                ) {
                    dismiss()
                    onComplete()
                }
            }
        }
    }
}
