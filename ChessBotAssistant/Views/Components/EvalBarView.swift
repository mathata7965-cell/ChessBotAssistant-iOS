import SwiftUI

struct EvalBarView: View {
    let analysis: EngineAnalysisResult?
    let perspective: PieceColor
    let isAnalyzing: Bool

    private var whiteFraction: Double {
        analysis?.evalBarFractionWhite ?? 0.5
    }

    private var primaryLine: PVLine? {
        analysis?.primaryLine
    }

    private var evalText: String {
        primaryLine?.formattedScore ?? "0.0"
    }

    private var isWhiteWinning: Bool {
        whiteFraction >= 0.5
    }

    var body: some View {
        GeometryReader { geo in
            let height = max(1, geo.size.height)
            let clampedFraction = whiteFraction.isFinite ? min(1.0, max(0.0, whiteFraction)) : 0.5
            let whiteHeight = height * clampedFraction
            let blackHeight = max(0, height - whiteHeight)

            ZStack {
                VStack(spacing: 0) {
                    if perspective == .white {
                        Color(red: 0.14, green: 0.16, blue: 0.18)
                            .frame(height: blackHeight)
                        Color(red: 0.94, green: 0.94, blue: 0.91)
                            .frame(height: whiteHeight)
                    } else {
                        Color(red: 0.94, green: 0.94, blue: 0.91)
                            .frame(height: whiteHeight)
                        Color(red: 0.14, green: 0.16, blue: 0.18)
                            .frame(height: blackHeight)
                    }
                }
                .animation(.easeInOut(duration: 0.32), value: whiteFraction)

                // Midpoint tick mark
                Rectangle()
                    .fill(Color.gray.opacity(0.45))
                    .frame(height: 1)

                // Score badge anchored to the winning side
                VStack {
                    if (perspective == .white && !isWhiteWinning) || (perspective == .black && isWhiteWinning) {
                        scoreBadge
                            .padding(.top, 5)
                        Spacer()
                    } else {
                        Spacer()
                        scoreBadge
                            .padding(.bottom, 5)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .overlay(alignment: .top) {
                if isAnalyzing {
                    Circle()
                        .fill(Color(red: 0.50, green: 0.72, blue: 0.30))
                        .frame(width: 6, height: 6)
                        .padding(.top, 3)
                }
            }
        }
        .frame(width: 30)
    }

    private var scoreBadge: some View {
        Text(evalText)
            .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
            .minimumScaleFactor(0.65)
            .lineLimit(1)
            .foregroundColor(isWhiteWinning ? Color(red: 0.10, green: 0.12, blue: 0.14) : .white)
            .padding(.horizontal, 2)
    }
}
