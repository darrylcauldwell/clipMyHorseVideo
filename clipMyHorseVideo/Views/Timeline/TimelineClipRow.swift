import SwiftUI

struct TimelineClipRow: View {
    let clip: Clip
    let index: Int

    @State private var shimmerOffset: CGFloat = -80

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnail = clip.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 45)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 80, height: 45)
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.3), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 40)
                        .offset(x: shimmerOffset)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        Image(systemName: "film")
                            .foregroundStyle(.secondary)
                    }
                    .onAppear {
                        shimmerOffset = -80
                        withAnimation(
                            .linear(duration: 1.5)
                            .repeatForever(autoreverses: false)
                        ) {
                            shimmerOffset = 80
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Clip \(index + 1)")
                    .font(.headline)

                HStack(spacing: 8) {
                    Label(clip.trimmedDuration.formattedDuration, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if clip.trimStart != .zero || clip.trimEnd != clip.originalDuration {
                        Text("Trimmed")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
