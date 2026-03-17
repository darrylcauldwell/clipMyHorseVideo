# clipMyHorseVideo

Simple iOS 26 utility app for merging multiple short horse showjumping video clips into a single video.

## Tech Stack

- **Language**: Swift 6.2+ (iOS 26)
- **UI**: SwiftUI with MVVM using `@Observable`
- **Concurrency**: async/await only
- **Media**: AVFoundation (composition, export, thumbnails)
- **Photos**: PhotosPicker (SwiftUI) + PHPhotoLibrary for saving

## Architecture

No persistence — everything is transient (pick, edit, export, done).

### Models
- `Clip` — `@Observable @MainActor` class: AVAsset + trim state + thumbnail + filmstrip thumbnails + per-clip transition
- `ExportQuality` — enum mapping to AVAssetExportSession presets + estimated bitrate
- `TransitionStyle` — enum: `.none` (cut) or `.crossfade` (0.5s dissolve)

### Services
- `VideoCompositionService` — `@Observable @MainActor`: builds AVMutableComposition with per-clip transitions, runs export
- `ThumbnailService` — `enum` with static methods: single thumbnail, concurrent batch (`generateThumbnails`), filmstrip generation
- `PhotoLibraryService` — `enum` with static methods for loading videos + saving to Photos

### Views
- `ContentView` — navigation root (empty → picker, clips → timeline)
- `ClipPickerView` — equestrian-themed empty state with 3-step flow hint + PhotosPicker
- `TimelineView` — vertical list with drag-reorder, swipe-delete + undo toast, mini timeline strip, per-clip transition indicators, preview button
- `TimelineClipRow` — thumbnail with shimmer loading animation + clip info
- `PreviewPlayerView` — full-screen AVQueuePlayer preview of all clips in sequence
- `TrimEditorView` — AVPlayer preview + filmstrip trim control with drag handles
- `ExportSettingsView` — quality picker with estimated file size + "set all transitions" option
- `ExportProgressView` — progress + success state with ShareLink + haptic feedback

## Key Technical Details

### iOS 26 APIs (non-deprecated)
- `AVVideoComposition(configuration:)` with `AVVideoComposition.Configuration`
- `AVVideoCompositionInstruction(configuration:)` with `.Configuration`
- `AVVideoCompositionLayerInstruction(configuration:)` with `.Configuration`
- `insertTimeRange(_:of:at:isolation:)` (async)
- `AVAssetExportSession.export(to:as:isolation:)` (async)
- `AVAssetImageGenerator.image(at:)` (async)

### Bundle ID
`dev.dreamfold.clipMyHorseVideo`

### Permissions
- `NSPhotoLibraryAddUsageDescription` — save merged video (only permission needed)
- PhotosPicker handles read access without a permission prompt
