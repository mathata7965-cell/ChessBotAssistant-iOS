import SwiftUI

struct MultiPVPanelView: View {
    let analysis: EngineAnalysisResult?
    let perspective: PieceColor
    let isAnalyzing: Bool
    let selectedPVIndex: Int?
    var boardState: ChessBoardState? = nil
    var coachPieceOnlyMode: Bool = false
    var isSafetyLocked: Bool = false
    var showOpponentReplyArrow: Bool = true
    var recommendedThinkRange: String? = nil
    var targetDepth: Int = 12
    var multiPVCount: Int = 3
    var isBoardDetected: Bool = true
    var isWaitingForOpponentReply: Bool = false
    var paceRemainingSeconds: Int = 0
    var gamePhasePly: Int = 20
    var onChangeDepth: ((Int) -> Void)? = nil
    var onChangeMultiPV: ((Int) -> Void)? = nil
    var onSkipBlockedMove: (() -> Void)? = nil
    var onForceAnalyzeNow: (() -> Void)? = nil
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
        VStack(alignment: .leading, spacing: 9) {
            // Header
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: analysis?.isCloudVerified == true ? "cloud.bolt.fill" : "cpu")
                        .font(.caption.bold())
                        .foregroundColor(Color(red: 0.50, green: 0.78, blue: 0.35))
                    Text(isBoardDetected ? (analysis?.engineSource ?? "準備分析中...") : "等待偵測棋盤")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                Menu {
                    Picker("思考深度", selection: Binding(
                        get: { targetDepth },
                        set: { onChangeDepth?($0) }
                    )) {
                        ForEach([6, 10, 12, 15, 18], id: \.self) { depth in
                            Text("Depth \(depth)").tag(depth)
                        }
                    }
                    Picker("候選走法數", selection: Binding(
                        get: { multiPVCount },
                        set: { onChangeMultiPV?($0) }
                    )) {
                        ForEach([1, 2, 3], id: \.self) { count in
                            Text("\(count) 條推薦").tag(count)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("D\(analysis?.depthReached ?? targetDepth) · \(multiPVCount)線")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.10))
                    .clipShape(Capsule())
                    .foregroundColor(Color(white: 0.88))
                }

                if isBoardDetected, let analysis, analysis.searchTimeMs > 0 {
                    let nodeStr: String = {
                        if analysis.nodesSearched >= 1000 {
                            return " · \(analysis.nodesSearched / 1000)k點"
                        } else if analysis.nodesSearched > 0 {
                            return " · \(analysis.nodesSearched)點"
                        } else {
                            return ""
                        }
                    }()
                    Text("\(analysis.searchTimeMs)ms\(nodeStr)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.12))
                        .foregroundColor(.cyan)
                        .clipShape(Capsule())
                }

                Spacer()

                if !isBoardDetected {
                    Text("待機掃描")
                        .font(.caption2.bold())
                        .foregroundColor(.cyan)
                } else if isAnalyzing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(Color(red: 0.50, green: 0.78, blue: 0.35))
                        Text("穩定計算中")
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

            if !isBoardDetected {
                VStack(spacing: 6) {
                    Image(systemName: "viewfinder")
                        .font(.title2)
                        .foregroundColor(.cyan)
                    Text("等待偵測棋盤")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Text("讀取到 Chess.com 棋盤後，將在此顯示最佳走法、螢幕位置座標與戰術分析")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else if isSafetyLocked {
                HStack(spacing: 10) {
                    Image(systemName: "shield.slash.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已啟用真人計時賽防誤封鎖定")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Text("已隱藏推薦走法與箭頭，避免誤用於真人對局。")
                            .font(.caption)
                            .foregroundColor(Color(white: 0.72))
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.red.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if isWaitingForOpponentReply {
                HStack(spacing: 10) {
                    Image(systemName: "hourglass.circle.fill")
                        .font(.title3)
                        .foregroundColor(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已偵測我方落子 · 等待對手落子中")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Text("畫面穩定鎖定中，對手走棋後會立即更新最佳路徑，避免跳幀誤判。")
                            .font(.caption2)
                            .foregroundColor(Color(white: 0.72))
                    }
                    Spacer()
                    if let onForceAnalyzeNow {
                        Button {
                            onForceAnalyzeNow()
                        } label: {
                            Text("立即分析")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.cyan.opacity(0.22))
                                .foregroundColor(.cyan)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(12)
                .background(Color.cyan.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.cyan.opacity(0.42), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let lines = analysis?.lines, let primary = lines.first {
                // Primary Tactical Hint Command Card (#1)
                primaryCommandCard(line: primary)

                // Alternative Candidates (#2, #3)
                let secondaryLines = Array(lines.dropFirst())
                if !secondaryLines.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(secondaryLines) { line in
                            secondaryLineRow(line: line)
                        }
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

    @ViewBuilder
    private func primaryCommandCard(line: PVLine) -> some View {
        let accent = rankAccentColor(1)
        let isHighlighted = selectedPVIndex == line.multipvIndex
        let movingPiece = boardState?.piece(at: line.bestMove.from)
        let pieceLabel = movingPiece?.type.fullChineseName ?? "棋子"
        let symbolName = movingPiece?.type.sfSymbolName ?? "arrow.right.circle.fill"
        let wdl = line.wdlBreakdown(for: perspective, gamePhasePly: gamePhasePly)
        let posHint = coachPieceOnlyMode
            ? line.bestMove.from.relativePositionHint(for: perspective)
            : "\(line.bestMove.from.relativePositionHint(for: perspective)) -> \(line.bestMove.to.relativePositionHint(for: perspective))"
        let reasonText = line.tacticalReason.isEmpty
            ? (boardState?.explainMoveTactics(line.bestMove) ?? "推薦主線")
            : line.tacticalReason

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(accent)
                    .padding(6)
                    .background(accent.opacity(0.18))
                    .clipShape(Circle())

                if coachPieceOnlyMode {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("動 \(pieceLabel) (\(line.bestMove.from.algebraic))")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundColor(.white)
                            Text(posHint)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.cyan.opacity(0.18))
                                .foregroundColor(.cyan)
                                .clipShape(Capsule())
                        }
                        Text("教練半提示模式：隱藏具體終點與續著")
                            .font(.caption2)
                            .foregroundColor(Color(white: 0.68))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(pieceLabel)
                                .font(.caption.bold())
                                .foregroundColor(accent)
                            Text(line.bestMove.coordinateDisplay)
                                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white)
                            Text("[\(line.bestMove.san)]")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(white: 0.78))
                        }

                        HStack(spacing: 6) {
                            Text(posHint)
                                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.cyan.opacity(0.16))
                                .foregroundColor(.cyan)
                                .clipShape(Capsule())

                            Text(reasonText)
                                .font(.caption2.bold())
                                .foregroundColor(Color(red: 0.78, green: 0.92, blue: 0.80))
                                .lineLimit(2)
                        }
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 3) {
                    if let mate = line.mateInMoves {
                        let isMyMate = (perspective == .white && mate > 0) || (perspective == .black && mate < 0)
                        Text(isMyMate ? "[必殺 M\(abs(mate))]" : "[敵殺 M\(abs(mate))]")
                            .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                isMyMate
                                    ? Color(red: 1.0, green: 0.78, blue: 0.22)
                                    : Color(red: 0.92, green: 0.28, blue: 0.30)
                            )
                            .foregroundColor(
                                isMyMate
                                    ? Color(red: 0.14, green: 0.08, blue: 0.0)
                                    : .white
                            )
                            .clipShape(Capsule())
                    }

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
            }

            // Phase-calibrated WDL Bar (Win / Draw / Loss)
            VStack(spacing: 4) {
                GeometryReader { geo in
                    let totalW = max(1, geo.size.width)
                    let safeWin = max(0, min(100, wdl.win))
                    let safeDraw = max(0, min(100 - safeWin, wdl.draw))
                    let winW = totalW * CGFloat(safeWin) / 100.0
                    let drawW = totalW * CGFloat(safeDraw) / 100.0
                    let lossW = max(0, totalW - winW - drawW)
                    HStack(spacing: 1) {
                        Rectangle()
                            .fill(Color(red: 0.35, green: 0.85, blue: 0.45))
                            .frame(width: winW)
                        Rectangle()
                            .fill(Color(white: 0.45))
                            .frame(width: drawW)
                        Rectangle()
                            .fill(Color(red: 0.90, green: 0.36, blue: 0.38))
                            .frame(width: lossW)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 5)

                HStack(spacing: 8) {
                    Text("勝 \(wdl.win)%")
                        .foregroundColor(Color(red: 0.45, green: 0.90, blue: 0.52))
                    Text("和 \(wdl.draw)%")
                        .foregroundColor(Color(white: 0.68))
                    Text("負 \(wdl.loss)%")
                        .foregroundColor(Color(red: 0.96, green: 0.52, blue: 0.50))

                    Spacer()

                    if !coachPieceOnlyMode && showOpponentReplyArrow,
                       let reply = line.predictedOpponentReply {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.uturn.down.circle.fill")
                                .font(.system(size: 10))
                            Text("預計敵應 \(reply.san)")
                        }
                        .foregroundColor(Color(red: 1.0, green: 0.58, blue: 0.58))
                    }
                }
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
            }

            if !coachPieceOnlyMode {
                HStack(spacing: 6) {
                    Text(line.continuationPreview)
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .foregroundColor(Color(white: 0.62))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    HStack(spacing: 3) {
                        Image(systemName: paceRemainingSeconds > 0 ? "hourglass" : "checkmark.circle.fill")
                            .font(.system(size: 9.5))
                        Text(paceRemainingSeconds > 0 ? "防封停頓 \(paceRemainingSeconds)s" : (recommendedThinkRange ?? "節奏就緒"))
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(paceRemainingSeconds > 0 ? Color(red: 0.98, green: 0.80, blue: 0.35) : .cyan)

                    if let onSkipBlockedMove {
                        Button {
                            onSkipBlockedMove()
                        } label: {
                            Label("王受阻/換步", systemImage: "arrow.triangle.branch")
                                .font(.system(size: 10.5, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.20))
                                .foregroundColor(.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                    }

                    Button {
                        onPlayPV(line)
                    } label: {
                        Text("走這步")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(accent.opacity(0.24))
                            .foregroundColor(accent)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHighlighted ? Color(red: 0.14, green: 0.20, blue: 0.17) : Color(red: 0.13, green: 0.17, blue: 0.19))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isHighlighted ? accent.opacity(0.80) : accent.opacity(0.35), lineWidth: 1.2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectPV(line)
        }
    }

    @ViewBuilder
    private func secondaryLineRow(line: PVLine) -> some View {
        let accent = rankAccentColor(line.multipvIndex)
        let isHighlighted = selectedPVIndex == line.multipvIndex

        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("#\(line.multipvIndex)")
                        .font(.system(size: 11.5, weight: .heavy, design: .rounded))
                        .foregroundColor(accent)

                    if coachPieceOnlyMode {
                        let pieceName = boardState?.piece(at: line.bestMove.from)?.type.displayName ?? "棋子"
                        Text("動\(pieceName) (\(line.bestMove.from.algebraic))")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text(line.bestMove.san)
                            .font(.system(size: 14.5, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)

                        Text(line.bestMove.coordinateDisplay)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(white: 0.72))

                        if !line.tacticalReason.isEmpty {
                            Text("· \(line.tacticalReason)")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(Color(white: 0.68))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if let mate = line.mateInMoves {
                        let isMyMate = (perspective == .white && mate > 0) || (perspective == .black && mate < 0)
                        Text(isMyMate ? "[必殺M\(abs(mate))]" : "[敵殺M\(abs(mate))]")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                isMyMate
                                    ? Color(red: 1.0, green: 0.78, blue: 0.22)
                                    : Color(red: 0.92, green: 0.28, blue: 0.30)
                            )
                            .foregroundColor(
                                isMyMate
                                    ? Color(red: 0.14, green: 0.08, blue: 0.0)
                                    : .white
                            )
                            .clipShape(Capsule())
                    }

                    Text(line.formattedScore)
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.90))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                    if !coachPieceOnlyMode {
                        Button {
                            onPlayPV(line)
                        } label: {
                            Text("走這步")
                                .font(.system(size: 10.5, weight: .bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(accent.opacity(0.20))
                                .foregroundColor(accent)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelectPV(line)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHighlighted ? Color.white.opacity(0.10) : Color(red: 0.14, green: 0.16, blue: 0.19))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isHighlighted ? accent.opacity(0.75) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}
