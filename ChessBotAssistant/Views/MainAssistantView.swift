import SwiftUI

struct MainAssistantView: View {
    @ObservedObject var viewModel: AssistantViewModel
    @State private var highlightedPVIndex: Int? = 1

    private let accentGreen = Color(red: 0.506, green: 0.714, blue: 0.298) // #81B64C

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.082, green: 0.094, blue: 0.110)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 10) {
                        // 1. Sleek Single-Card Top Control Deck
                        PiPPreviewCardView(
                            pipManager: viewModel.pipManager,
                            isAutoSyncEnabled: viewModel.screenshotMonitor.isMonitoring || viewModel.broadcastService.isBroadcastActive,
                            isBroadcastActive: viewModel.broadcastService.isBroadcastActive,
                            isScanning: viewModel.isScanningScreenshot,
                            onTogglePiP: {
                                viewModel.togglePiPWithAutoSync()
                            },
                            onToggleAutoSync: {
                                viewModel.toggleAutoScreenshotSync()
                            },
                            onScanNow: {
                                viewModel.scanLatestScreenshot()
                            },
                            onUnavailableBroadcast: {
                                viewModel.showBanner("免外掛版請用「懸浮窗 + 截圖」")
                            }
                        )

                        // 5 Core Quick Toggles
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                protectionPill(
                                    title: "🧭 \(viewModel.campDetectionMode.displayName)(\(viewModel.perspective == .white ? "白" : "黑"))",
                                    isActive: true,
                                    activeColor: .teal
                                ) {
                                    viewModel.cycleCampDetectionMode()
                                }

                                protectionPill(
                                    title: "🎭 \(viewModel.engineService.playStyleMode.displayName)",
                                    isActive: viewModel.engineService.playStyleMode != .engineBest,
                                    activeColor: .purple
                                ) {
                                    viewModel.cyclePlayStyleMode()
                                }

                                protectionPill(
                                    title: "🔮 敵步預測",
                                    isActive: viewModel.engineService.showOpponentReplyArrow,
                                    activeColor: .red
                                ) {
                                    viewModel.engineService.showOpponentReplyArrow.toggle()
                                }

                                protectionPill(
                                    title: "🔊 語音",
                                    isActive: viewModel.voiceAnnounceEnabled,
                                    activeColor: .mint
                                ) {
                                    viewModel.voiceAnnounceEnabled.toggle()
                                }

                                protectionPill(
                                    title: viewModel.engineService.zeroNetworkIsolationMode ? "🔒 離線" : "🌐 雲端",
                                    isActive: viewModel.engineService.zeroNetworkIsolationMode,
                                    activeColor: accentGreen
                                ) {
                                    viewModel.engineService.zeroNetworkIsolationMode.toggle()
                                    viewModel.triggerAnalysis()
                                }
                            }
                        }

                        // 真人計時賽自動鎖定警告卡片
                        if viewModel.isFairPlaySafetyLocked {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.shield.fill")
                                        .font(.title3)
                                        .foregroundColor(.red)
                                    Text("已觸發防誤封自動鎖定")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                Text(viewModel.safetyLockReason ?? "偵測到倒數計時器且無 Bot 標記，已隱藏所有提示避免誤用於真人對局。")
                                    .font(.caption)
                                    .foregroundColor(Color(white: 0.85))
                                Button {
                                    viewModel.unlockSafetyLockForBotMatch()
                                } label: {
                                    Text("確認為 Bot 對局並解鎖")
                                        .font(.caption.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(Color.red.opacity(0.30))
                                        .foregroundColor(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding(12)
                            .background(Color.red.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.red.opacity(0.60), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Optional toast banner
                        if let banner = viewModel.statusBanner {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(accentGreen)
                                Text(banner)
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.15, green: 0.20, blue: 0.24))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .transition(.opacity)
                        }

                        // 2. Eval Bar + Interactive Chess Board
                        HStack(spacing: 8) {
                            EvalBarView(
                                analysis: viewModel.engineService.currentAnalysis,
                                perspective: viewModel.perspective,
                                isAnalyzing: viewModel.engineService.isAnalyzing
                            )

                            InteractiveChessBoardView(
                                boardState: viewModel.boardState,
                                perspective: viewModel.perspective,
                                selectedSquare: viewModel.selectedSquare,
                                legalTargets: viewModel.legalTargetsForSelection,
                                lastMove: viewModel.lastMove,
                                pvLines: viewModel.engineService.currentAnalysis?.lines ?? [],
                                showAutoHintArrows: viewModel.engineService.autoHintEnabled,
                                highlightedPVIndex: highlightedPVIndex,
                                coachPieceOnlyMode: viewModel.engineService.coachPieceOnlyHintMode,
                                isSafetyLocked: viewModel.isFairPlaySafetyLocked,
                                hangingSquares: Set(viewModel.tacticalRadar.hangingFriendlySquares),
                                showOpponentReplyArrow: viewModel.engineService.showOpponentReplyArrow,
                                onTapSquare: { square in
                                    viewModel.tapSquare(square)
                                }
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1.09, contentMode: .fit)

                        // 3. Fitted 5-Item Action Strip
                        HStack(spacing: 6) {
                            actionChip(
                                title: "走最佳",
                                icon: "bolt.fill",
                                tint: accentGreen,
                                highlighted: true
                            ) {
                                viewModel.playBestMove()
                            }

                            actionChip(
                                title: "執\(viewModel.perspective == .white ? "白" : "黑")",
                                icon: "arrow.up.arrow.down",
                                tint: .white
                            ) {
                                viewModel.flipPerspective()
                            }

                            actionChip(
                                title: "悔棋",
                                icon: "arrow.uturn.backward",
                                tint: .white
                            ) {
                                viewModel.undoLastMove()
                            }

                            actionChip(
                                title: "掃描器",
                                icon: "camera.viewfinder",
                                tint: .cyan
                            ) {
                                viewModel.showScreenshotScannerSheet = true
                            }

                            Menu {
                                Button {
                                    viewModel.toggleSideToMove()
                                } label: {
                                    Label("輪到\(viewModel.boardState.sideToMove.displayName)（切換）", systemImage: "circle.lefthalf.filled")
                                }

                                Button {
                                    viewModel.toggleAlwaysAnalyzeMyCampTurn()
                                } label: {
                                    Label(
                                        viewModel.alwaysAnalyzeMyCampTurn ? "✅ 鎖定分析我方回合" : "⬜ 鎖定分析我方回合",
                                        systemImage: "lock.rotation"
                                    )
                                }

                                Button {
                                    viewModel.engineService.coachPieceOnlyHintMode.toggle()
                                } label: {
                                    Label(
                                        viewModel.engineService.coachPieceOnlyHintMode ? "✅ 教練半提示模式" : "⬜ 教練半提示模式",
                                        systemImage: "graduationcap"
                                    )
                                }

                                Button {
                                    viewModel.engineService.humanMatchSafetyLockEnabled.toggle()
                                } label: {
                                    Label(
                                        viewModel.engineService.humanMatchSafetyLockEnabled ? "✅ 真人計時賽防誤觸" : "⬜ 真人計時賽防誤觸",
                                        systemImage: "shield"
                                    )
                                }

                                Button {
                                    viewModel.engineService.autoHintEnabled.toggle()
                                } label: {
                                    Label(
                                        viewModel.engineService.autoHintEnabled ? "✅ 顯示棋盤提示箭頭" : "⬜ 顯示棋盤提示箭頭",
                                        systemImage: "arrow.up.right"
                                    )
                                }

                                Divider()

                                Button {
                                    viewModel.pasteFENOrPGNFromClipboard()
                                } label: {
                                    Label("📋 貼上 FEN / PGN", systemImage: "doc.on.clipboard")
                                }

                                Button {
                                    viewModel.copyCurrentFEN()
                                } label: {
                                    Label("📄 複製當前 FEN", systemImage: "square.on.square")
                                }

                                Button {
                                    viewModel.showBoardEditorSheet = true
                                } label: {
                                    Label("♟️ 手動擺盤編輯", systemImage: "square.grid.3x3")
                                }

                                if viewModel.screenshotMonitor.hasDeletableScreenshot {
                                    Button(role: .destructive) {
                                        viewModel.deleteLastScreenshot()
                                    } label: {
                                        Label("🧹 刪除暫存截圖", systemImage: "trash")
                                    }
                                }

                                Divider()

                                Button(role: .destructive) {
                                    viewModel.resetBoard()
                                } label: {
                                    Label("🔄 重置標準開局", systemImage: "arrow.counterclockwise")
                                }
                            } label: {
                                actionChipLabel(title: "更多", icon: "ellipsis", tint: Color(white: 0.85))
                            }
                        }

                        // 4. Multi-PV Candidate Moves Panel
                        MultiPVPanelView(
                            analysis: viewModel.engineService.currentAnalysis,
                            perspective: viewModel.perspective,
                            isAnalyzing: viewModel.engineService.isAnalyzing,
                            selectedPVIndex: highlightedPVIndex,
                            boardState: viewModel.boardState,
                            coachPieceOnlyMode: viewModel.engineService.coachPieceOnlyHintMode,
                            isSafetyLocked: viewModel.isFairPlaySafetyLocked,
                            showOpponentReplyArrow: viewModel.engineService.showOpponentReplyArrow,
                            recommendedThinkRange: viewModel.tacticalRadar.recommendedThinkRange,
                            targetDepth: viewModel.engineService.targetDepth,
                            multiPVCount: viewModel.engineService.multiPVCount,
                            onChangeDepth: { newDepth in
                                viewModel.engineService.targetDepth = newDepth
                                viewModel.triggerAnalysis()
                            },
                            onChangeMultiPV: { newCount in
                                viewModel.engineService.multiPVCount = newCount
                                viewModel.triggerAnalysis()
                            },
                            onSelectPV: { line in
                                highlightedPVIndex = line.multipvIndex
                            },
                            onPlayPV: { line in
                                viewModel.playPVLine(line)
                            }
                        )

                        // 4.5 Compact Tactical Radar & Sparkline Card
                        tacticalRadarAndSparklineCard

                        // Move history strip if any
                        if !viewModel.moveHistorySAN.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    Text("走法記錄:")
                                        .font(.caption2.bold())
                                        .foregroundColor(.secondary)
                                    ForEach(Array(viewModel.moveHistorySAN.enumerated()), id: \.offset) { idx, san in
                                        Text("\(idx % 2 == 0 ? "\(idx / 2 + 1)." : "")\(san)")
                                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.white.opacity(0.07))
                                            .foregroundColor(Color(white: 0.85))
                                            .clipShape(RoundedRectangle(cornerRadius: 5))
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Chess Bot 輔助大師")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.scanLatestScreenshot()
                    } label: {
                        if viewModel.isScanningScreenshot {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Label("一鍵讀截圖", systemImage: "camera.shutter.button")
                                .font(.caption.bold())
                        }
                    }
                    .tint(.cyan)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showEngineSettingsSheet = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .tint(accentGreen)
                }
            }
            .sheet(isPresented: $viewModel.showEngineSettingsSheet) {
                EngineSettingsSheetView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showScreenshotScannerSheet) {
                ScreenshotScannerSheetView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showBoardEditorSheet) {
                BoardEditorSheetView(viewModel: viewModel)
            }
            .confirmationDialog(
                "選擇升變棋子",
                isPresented: Binding(
                    get: { viewModel.pendingPromotionPair != nil },
                    set: { if !$0 { viewModel.pendingPromotionPair = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("皇后 (Queen)") { viewModel.completePendingPromotion(with: .queen) }
                Button("城堡 (Rook)") { viewModel.completePendingPromotion(with: .rook) }
                Button("主教 (Bishop)") { viewModel.completePendingPromotion(with: .bishop) }
                Button("騎士 (Knight)") { viewModel.completePendingPromotion(with: .knight) }
                Button("取消", role: .cancel) { viewModel.pendingPromotionPair = nil }
            }
            .alert("輸入 FEN 或 PGN 局面", isPresented: $viewModel.showFENInputAlert) {
                TextField("貼上 FEN 或 PGN 文字", text: $viewModel.fenInputText)
                Button("載入") {
                    _ = viewModel.importPositionText(viewModel.fenInputText)
                    viewModel.fenInputText = ""
                }
                Button("取消", role: .cancel) {
                    viewModel.fenInputText = ""
                }
            } message: {
                Text("支援 Chess.com 分享的 FEN 字串或 PGN 走法記錄。")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var tacticalRadarAndSparklineCard: some View {
        let radar = viewModel.tacticalRadar
        let diff = radar.materialDiffForPerspective
        let diffText = diff == 0 ? "均勢 ±0" : (diff > 0 ? "子力 +\(diff)" : "子力 \(diff)")
        let diffColor: Color = diff > 0 ? accentGreen : (diff < 0 ? .orange : Color(white: 0.78))
        let points = viewModel.evalHistoryWhitePct
        let latestWhitePct = points.last ?? 50.0

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label(radar.openingName, systemImage: "book.closed.fill")
                    .font(.caption.bold())
                    .foregroundColor(.cyan)
                    .lineLimit(1)

                Spacer()

                if let quality = viewModel.lastMoveQualityBadge {
                    Text(quality)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(qualityColor(for: quality))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(qualityColor(for: quality).opacity(0.16))
                        .clipShape(Capsule())
                }

                Text(diffText)
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(diffColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(diffColor.opacity(0.16))
                    .clipShape(Capsule())
            }

            if !radar.capturedByUser.isEmpty || !radar.capturedByOpponent.isEmpty {
                HStack(spacing: 10) {
                    if !radar.capturedByUser.isEmpty {
                        Text("我吃: \(radar.capturedByUser.map(pieceGlyph).joined())")
                            .font(.caption2)
                            .foregroundColor(accentGreen)
                    }
                    if !radar.capturedByOpponent.isEmpty {
                        Text("敵吃: \(radar.capturedByOpponent.map(pieceGlyph).joined())")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    Spacer(minLength: 0)
                }
            }

            if !radar.hangingDescriptions.isEmpty {
                Text("⚠️ 懸空：\(radar.hangingDescriptions.joined(separator: "、"))")
                    .font(.caption2.bold())
                    .foregroundColor(.red.opacity(0.95))
            }

            if !radar.freeTargetDescriptions.isEmpty {
                Text("🎯 白吃：\(radar.freeTargetDescriptions.joined(separator: "、"))")
                    .font(.caption2.bold())
                    .foregroundColor(accentGreen)
            }

            HStack(spacing: 8) {
                Text("白\(Int(latestWhitePct.rounded()))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    ZStack {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: h * 0.5))
                            path.addLine(to: CGPoint(x: w, y: h * 0.5))
                        }
                        .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        if points.count >= 2 {
                            Path { path in
                                for (idx, val) in points.enumerated() {
                                    let x = w * CGFloat(idx) / CGFloat(max(1, points.count - 1))
                                    let y = h * (1.0 - CGFloat(min(100.0, max(0.0, val))) / 100.0)
                                    if idx == 0 {
                                        path.move(to: CGPoint(x: x, y: y))
                                    } else {
                                        path.addLine(to: CGPoint(x: x, y: y))
                                    }
                                }
                            }
                            .stroke(
                                LinearGradient(
                                    colors: [.cyan, accentGreen],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                            )
                        } else if let onlyVal = points.first {
                            let y = h * (1.0 - CGFloat(min(100.0, max(0.0, onlyVal))) / 100.0)
                            Circle()
                                .fill(Color.cyan)
                                .frame(width: 5, height: 5)
                                .position(x: w * 0.5, y: y)
                        }
                    }
                }
                .frame(height: 22)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text("黑\(100 - Int(latestWhitePct.rounded()))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.72))
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.11, green: 0.14, blue: 0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.cyan.opacity(0.20), lineWidth: 1)
        )
    }

    private func pieceGlyph(_ piece: ChessPiece) -> String {
        switch (piece.color, piece.type) {
        case (.white, .king): return "♔"
        case (.white, .queen): return "♕"
        case (.white, .rook): return "♖"
        case (.white, .bishop): return "♗"
        case (.white, .knight): return "♘"
        case (.white, .pawn): return "♙"
        case (.black, .king): return "♚"
        case (.black, .queen): return "♛"
        case (.black, .rook): return "♜"
        case (.black, .bishop): return "♝"
        case (.black, .knight): return "♞"
        case (.black, .pawn): return "♟"
        }
    }

    private func qualityColor(for badge: String) -> Color {
        if badge.hasPrefix("💎") { return .cyan }
        if badge.hasPrefix("✅") { return accentGreen }
        if badge.hasPrefix("👍") { return .blue }
        if badge.hasPrefix("⚠️") { return .orange }
        return .red
    }

    private func protectionPill(
        title: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(isActive ? activeColor.opacity(0.18) : Color.white.opacity(0.07))
                .foregroundColor(isActive ? activeColor : Color(white: 0.70))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isActive ? activeColor.opacity(0.55) : Color.white.opacity(0.10), lineWidth: 1)
                )
        }
    }

    private func actionChip(
        title: String,
        icon: String,
        tint: Color,
        highlighted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionChipLabel(title: title, icon: icon, tint: tint, highlighted: highlighted)
        }
    }

    private func actionChipLabel(
        title: String,
        icon: String,
        tint: Color,
        highlighted: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(size: 11.5, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(
            highlighted
                ? tint.opacity(0.24)
                : Color(red: 0.14, green: 0.17, blue: 0.20)
        )
        .foregroundColor(tint)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(highlighted ? tint.opacity(0.65) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
