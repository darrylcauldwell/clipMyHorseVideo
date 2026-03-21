import SwiftUI

struct TimelineClipRow: View {
    let clip: Clip
    let index: Int

    @State private var shimmerOffset: CGFloat = -96

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnail = clip.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 96, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 96, height: 54)
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
                        shimmerOffset = -96
                        withAnimation(
                            .linear(duration: 1.5)
                            .repeatForever(autoreverses: false)
                        ) {
                            shimmerOffset = 96
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Clip \(index + 1)")
                    .font(.headline)

                Text(clip.speedAdjustedDuration.formattedDuration)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let report = clip.qualityReport, report.hasWarnings {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help(report.warnings.map(\.message).joined(separator: "\n"))
            }
        }
        .padding(.vertical, 8)
    }
}
