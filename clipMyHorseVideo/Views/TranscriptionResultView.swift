import SwiftUI

struct TranscriptionResultView: View {
    @Bindable var info: AnnouncerInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Detected Information") {
                LabeledContent("Rider") {
                    TextField("Rider name", text: $info.riderName)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Horse") {
                    TextField("Horse name", text: $info.horseName)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Class") {
                    TextField("Class/competition", text: $info.className)
                        .multilineTextAlignment(.trailing)
                }
            }

            if !info.rawTranscript.isEmpty {
                Section("Raw Transcript") {
                    Text(info.rawTranscript)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Audio Scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
