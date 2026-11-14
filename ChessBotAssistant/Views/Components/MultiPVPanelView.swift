import SwiftUI

struct MultiPVPanelView: View {
    let analysis: EngineAnalysisResult?
    let perspective: PieceColor
    let isAnalyzing: Bool
    let selectedPVIndex: Int?
    let onSelectPV: (PVLine) -> Void
    let onPlayPV: (PVLine) -> Void

    private func rankAccentColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 0.35, green: 0.88, blue: 0.42)
        case 2: return Color(red: 0.22, green: 0.78, blue: 0.96)
        default: return Color(red: 0.98, green: 0.72, blue: 0.22)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: analysis?.isCloudVerified == true ? "cloud.bolt.fill" : "cpu")
                        .font(.caption.bold())
                        .foregroundColor(Color(red: 0.50, green: 0.78, blue: 0.35))
                    Text(analysis?.engineSource ?? "準備分析中...")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                }

                if let analysis, analysis.depthReached > 0 {
                    Text("Depth \(analysis.depthReached)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Capsule())
                        .foregroundColor(Color(white: 0.85))
                }

                Spacer()

                if isAnalyzing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(Color(red: 0.50, green: 0.78, blue: 0.35))
                        Text("計算中")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else if let primary = analysis?.primaryLine {
                    let winPct = Int(primary.winProbability(for: perspective).rounded())
                    Text("\(perspective.displayName)勝率 \(winPct)%")
                        .font(.caption.bold())
                        .foregroundColor(winPct >= 50 ? Color(red: 0.45, green: 0.90, blue: 0.52) : Color(red: 0.96, green: 0.55, blue: 0.48))
                }
            }

            if let lines = analysis?.lines, !lines.isEmpty {
                VStack(spacing: 7) {
                    ForEach(lines) { line in
                        let accent = rankAccentColor(line.multipvIndex)
                        let isHighlighted = selectedPVIndex == line.multipvIndex

                        HStack(spacing: 10) {
                            // Rank strip
                            RoundedRectangle(cornerRadius: 3)
                                .fill(accent)
                                .frame(width: 4)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("#\(line.multipvIndex)")
                                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                                        .foregroundColor(accent)

                                    Text(line.bestMove.san)
                                        .font(.system(size: 16, weight: .heavy, design: .monospaced))
                                        .foregroundColor(.white)

                                    Text(line.bestMove.coordinateDisplay)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(Color(white: 0.72))

                                    if let tag = line.bestMove.tacticalTag {
                                        Text(tag)
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1.5)
                                            .background(accent.opacity(0.18))
                                            .foregroundColor(accent)
                                            .clipShape(Capsule())
                                    }

                                    Spacer()

                                    Text(line.formattedScore)
                                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            line.scoreCentipawns >= 0
                                                ? Color.white.opacity(0.92)
                                                : Color(white: 0.22)
                                        )
                                        .foregroundColor(
                                            line.scoreCentipawns >= 0
                                                ? Color(red: 0.10, green: 0.12, blue: 0.14)
                                                : .white
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }

                                Text(line.continuationPreview)
                                    .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                                    .foregroundColor(Color(white: 0.65))
                                    .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectPV(line)
                            }

                            Button {
                                onPlayPV(line)
                            } label: {
                                Text("走這步")
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(accent.opacity(0.22))
                                    .foregroundColor(accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isHighlighted ? Color.white.opacity(0.10) : Color(red: 0.14, green: 0.16, blue: 0.19))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isHighlighted ? accent.opacity(0.75) : Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }
                }
            } else {
                Text("無合法走法或等待局面中")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.11, green: 0.13, blue: 0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
