import SwiftUI

struct TextOverlayEditorView: View {
    @Bindable var overlay: TextOverlay
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Text") {
                Picker("Preset", selection: .constant(TextOverlay.Preset.custom)) {
                    ForEach(TextOverlay.Preset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }

                TextField("Text", text: $overlay.text, axis: .vertical)
                    .lineLimit(3)
            }

            Section("Position") {
                Picker("Position", selection: $overlay.position) {
                    ForEach(TextOverlay.OverlayPosition.allCases) { pos in
                        Text(pos.rawValue).tag(pos)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Style") {
                HStack {
                    Text("Font Size")
                    Slider(value: $overlay.fontSize, in: 16...72, step: 2)
                    Text("\(Int(overlay.fontSize))")
                        .monospacedDigit()
                        .frame(width: 30)
                }

                ColorPicker("Text Colour", selection: $overlay.colour)

                HStack {
                    Text("Background")
                    Slider(value: $overlay.backgroundOpacity, in: 0...1)
                    Text(String(format: "%.0f%%", overlay.backgroundOpacity * 100))
                        .monospacedDigit()
                        .frame(width: 40)
                }

                Toggle("Text Shadow", isOn: $overlay.showShadow)
            }

            Section("Preview") {
                ZStack {
                    Rectangle()
                        .fill(.black)
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack {
                        if overlay.position == .bottom || overlay.position == .centre {
                            Spacer()
                        }

                        Text(overlay.text.isEmpty ? "Preview" : overlay.text)
                            .font(.system(size: overlay.fontSize * 0.5))
                            .foregroundStyle(overlay.colour)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(overlay.backgroundOpacity))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .shadow(radius: overlay.showShadow ? 2 : 0)

                        if overlay.position == .top || overlay.position == .centre {
                            Spacer()
                        }
                    }
                    .padding(8)
                }
            }
        }
        .navigationTitle("Text Overlay")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
