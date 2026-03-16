# clipMyRound

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
- `Clip` — `@Observable @MainActor` class: AVAsset + trim state + thumbnail
- `ExportQuality` — enum mapping to AVAssetExportSession presets
- `TransitionStyle` — enum: `.none` (cut) or `.crossfade` (0.5s dissolve)

### Services
- `VideoCompositionService` — `@Observable @MainActor`: builds AVMutableComposition, runs export
- `ThumbnailService` — `enum` with static methods for AVAssetImageGenerator thumbnails
- `PhotoLibraryService` — `enum` with static methods for loading videos + saving to Photos

### Views
- `ContentView` — navigation root (empty → picker, clips → timeline)
- `ClipPickerView` — PhotosPicker multi-select with `.videos` filter
- `TimelineView` / `TimelineClipRow` — vertical list with drag-reorder and swipe-delete
- `TrimEditorView` — AVPlayer preview + range sliders
- `ExportSettingsView` / `ExportProgressView` — quality/transition pickers + progress

## Key Technical Details

### iOS 26 APIs (non-deprecated)
- `AVVideoComposition(configuration:)` with `AVVideoComposition.Configuration`
- `AVVideoCompositionInstruction(configuration:)` with `.Configuration`
- `AVVideoCompositionLayerInstruction(configuration:)` with `.Configuration`
- `insertTimeRange(_:of:at:isolation:)` (async)
- `AVAssetExportSession.export(to:as:isolation:)` (async)
- `AVAssetImageGenerator.image(at:)` (async)

### Bundle ID
`dev.dreamfold.clipMyRound`

### Permissions
- `NSPhotoLibraryAddUsageDescription` — save merged video (only permission needed)
- PhotosPicker handles read access without a permission prompt
