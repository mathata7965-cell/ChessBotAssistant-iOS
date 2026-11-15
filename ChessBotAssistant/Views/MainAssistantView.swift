import SwiftUI

struct MainAssistantView: View {
    @ObservedObject var viewModel: AssistantViewModel
    @State private var highlightedPVIndex: Int? = 1
    @State private var showLaunchOverlay: Bool = true
    @State private var cardsRevealed: Bool = false

    private let accentGreen = Color(red: 0.506, green: 0.714, blue: 0.298) // #81B64C

    var body: some View {
        ZStack {
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
                            .opacity(cardsRevealed ? 1 : 0)
                            .offset(y: cardsRevealed ? 0 : 10)

                            // Core Quick Toggles (Zero-Emoji SF Symbols)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 7) {
                                    protectionPill(
                                        title: "\(viewModel.campDetectionMode.displayName)(\(viewModel.perspective == .white ? "白" : "黑"))",
                                        icon: "safari.fill",
                                        isActive: true,
                                        activeColor: .teal
                                    ) {
                                        viewModel.cycleCampDetectionMode()
                                    }

                                    protectionPill(
                                        title: viewModel.engineService.playStyleMode.displayName,
                                        icon: viewModel.engineService.playStyleMode.icon,
                                        isActive: viewModel.engineService.playStyleMode != .engineBest,
                                        activeColor: .purple
                                    ) {
                                        viewModel.cyclePlayStyleMode()
                                    }

                                    protectionPill(
                                        title: viewModel.engineService.botTargetProfile.shortName,
                                        icon: "cpu.fill",
                                        isActive: viewModel.engineService.botTargetProfile != .universal,
                                        activeColor: .orange
                                    ) {
                                        viewModel.cycleBotTargetProfile()
                                    }

                                    protectionPill(
                                        title: viewModel.boardTheme.displayName,
                                        icon: "paintpalette.fill",
                                        isActive: true,
                                        activeColor: .blue
                                    ) {
                                        viewModel.cycleBoardTheme()
                                    }

                                    protectionPill(
                                        title: "敵步預測",
                                        icon: "arrow.uturn.down.circle.fill",
                                        isActive: viewModel.engineService.showOpponentReplyArrow,
                                        activeColor: .red
                                    ) {
                                        viewModel.engineService.showOpponentReplyArrow.toggle()
                                    }

                                    protectionPill(
                                        title: "語音",
                                        icon: "speaker.wave.2.fill",
                                        isActive: viewModel.voiceAnnounceEnabled,
                                        activeColor: .mint
                                    ) {
                                        viewModel.voiceAnnounceEnabled.toggle()
                                    }

                                    protectionPill(
                                        title: viewModel.engineService.zeroNetworkIsolationMode ? "離線隔離" : "雲端混合",
                                        icon: viewModel.engineService.zeroNetworkIsolationMode ? "lock.shield.fill" : "network",
                                        isActive: viewModel.engineService.zeroNetworkIsolationMode,
                                        activeColor: accentGreen
                                    ) {
                                        viewModel.engineService.zeroNetworkIsolationMode.toggle()
                                        viewModel.triggerAnalysis()
                                    }
                                }
                            }
                            .opacity(cardsRevealed ? 1 : 0)
                            .offset(y: cardsRevealed ? 0 : 8)

                            // Fair-Play Safety Lock Card
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

                            // King Check & Pin Alert Bar (Diagnoses why a piece cannot move due to the King)
                            if viewModel.tacticalRadar.isKingInCheck || !viewModel.tacticalRadar.pinnedPieces.isEmpty {
                                kingSafetyAndPinAlertBar
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
                                    pvLines: viewModel.isWaitingForOpponentReply ? [] : (viewModel.engineService.currentAnalysis?.lines ?? []),
                                    showAutoHintArrows: viewModel.engineService.autoHintEnabled,
                                    highlightedPVIndex: highlightedPVIndex,
                                    coachPieceOnlyMode: viewModel.engineService.coachPieceOnlyHintMode,
                                    isSafetyLocked: viewModel.isFairPlaySafetyLocked,
                                    hangingSquares: Set(viewModel.tacticalRadar.hangingFriendlySquares),
                                    showOpponentReplyArrow: viewModel.engineService.showOpponentReplyArrow,
                                    boardTheme: viewModel.boardTheme,
                                    onTapSquare: { square in
                                        viewModel.tapSquare(square)
                                    }
                                )
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1.09, contentMode: .fit)
                            .opacity(cardsRevealed ? 1 : 0)
                            .scaleEffect(cardsRevealed ? 1 : 0.98)

                            // 3. Fitted 5-Item Action Strip (Includes One-Tap King-Blocked Rescue)
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
                                    title: "王受阻換步",
                                    icon: "arrow.triangle.branch",
                                    tint: .orange
                                ) {
                                    viewModel.skipBlockedMoveAndReanalyze()
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

                                Menu {
                                    Button {
                                        viewModel.showScreenshotScannerSheet = true
                                    } label: {
                                        Label("開啟截圖辨識掃描器", systemImage: "camera.viewfinder")
                                    }

                                    Button {
                                        viewModel.toggleSideToMove()
                                    } label: {
                                        Label("輪到\(viewModel.boardState.sideToMove.displayName)（切換）", systemImage: "circle.lefthalf.filled")
                                    }

                                    Button {
                                        viewModel.toggleAlwaysAnalyzeMyCampTurn()
                                    } label: {
                                        Label(
                                            "鎖定分析我方回合",
                                            systemImage: viewModel.alwaysAnalyzeMyCampTurn ? "checkmark.circle.fill" : "circle"
                                        )
                                    }

                                    Button {
                                        viewModel.engineService.coachPieceOnlyHintMode.toggle()
                                    } label: {
                                        Label(
                                            "教練半提示模式",
                                            systemImage: viewModel.engineService.coachPieceOnlyHintMode ? "checkmark.circle.fill" : "circle"
                                        )
                                    }

                                    Button {
                                        viewModel.engineService.humanMatchSafetyLockEnabled.toggle()
                                    } label: {
                                        Label(
                                            "真人計時賽防誤觸",
                                            systemImage: viewModel.engineService.humanMatchSafetyLockEnabled ? "checkmark.circle.fill" : "circle"
                                        )
                                    }

                                    Button {
                                        viewModel.engineService.autoHintEnabled.toggle()
                                    } label: {
                                        Label(
                                            "顯示棋盤提示箭頭",
                                            systemImage: viewModel.engineService.autoHintEnabled ? "checkmark.circle.fill" : "circle"
                                        )
                                    }

                                    Divider()

                                    Button {
                                        viewModel.pasteFENOrPGNFromClipboard()
                                    } label: {
                                        Label("貼上 FEN / PGN", systemImage: "doc.on.clipboard")
                                    }

                                    Button {
                                        viewModel.copyCurrentFEN()
                                    } label: {
                                        Label("複製當前 FEN", systemImage: "square.on.square")
                                    }

                                    Button {
                                        viewModel.copyGamePGNAndReviewReport()
                                    } label: {
                                        Label("複製整局 PGN 與複盤報告", systemImage: "chart.bar.doc.horizontal")
                                    }

                                    Button {
                                        viewModel.showBoardEditorSheet = true
                                    } label: {
                                        Label("手動擺盤編輯", systemImage: "square.grid.3x3")
                                    }

                                    if viewModel.screenshotMonitor.hasDeletableScreenshot {
                                        Button(role: .destructive) {
                                            viewModel.deleteLastScreenshot()
                                        } label: {
                                            Label("刪除暫存截圖", systemImage: "trash")
                                        }
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        viewModel.resetBoard()
                                    } label: {
                                        Label("重置標準開局", systemImage: "arrow.counterclockwise")
                                    }
                                } label: {
                                    actionChipLabel(title: "更多", icon: "ellipsis.circle", tint: Color(white: 0.85))
                                }
                            }

                            // 4. Multi-PV Primary Tactical Hint Card & Alternatives
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
                                isWaitingForOpponentReply: viewModel.isWaitingForOpponentReply,
                                paceRemainingSeconds: viewModel.paceRemainingSeconds,
                                gamePhasePly: max(1, (viewModel.boardState.fullMoveNumber - 1) * 2 + (viewModel.boardState.sideToMove == .white ? 0 : 1)),
                                onChangeDepth: { newDepth in
                                    viewModel.engineService.targetDepth = newDepth
                                    viewModel.triggerAnalysis()
                                },
                                onChangeMultiPV: { newCount in
                                    viewModel.engineService.multiPVCount = newCount
                                    viewModel.triggerAnalysis()
                                },
                                onSkipBlockedMove: {
                                    viewModel.skipBlockedMoveAndReanalyze()
                                },
                                onForceAnalyzeNow: {
                                    viewModel.forceAnalyzeNow()
                                },
                                onSelectPV: { line in
                                    highlightedPVIndex = line.multipvIndex
                                },
                                onPlayPV: { line in
                                    viewModel.playPVLine(line)
                                }
                            )
                            .opacity(cardsRevealed ? 1 : 0)
                            .offset(y: cardsRevealed ? 0 : 12)

                            // 5. Anti-Ban Protection Telemetry + Tactical Radar + Sparkline Card
                            tacticalRadarAndSparklineCard
                                .opacity(cardsRevealed ? 1 : 0)
                                .offset(y: cardsRevealed ? 0 : 14)

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

            if showLaunchOverlay {
                LaunchIntroOverlayView(accentColor: accentGreen) {
                    dismissLaunchOverlay()
                }
                .transition(.opacity.combined(with: .scale(scale: 1.03)))
                .zIndex(50)
            }
        }
        .onAppear {
            if showLaunchOverlay {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
                    dismissLaunchOverlay()
                }
            } else {
                cardsRevealed = true
            }
        }
    }

    private func dismissLaunchOverlay() {
        guard showLaunchOverlay else { return }
        withAnimation(.easeOut(duration: 0.32)) {
            showLaunchOverlay = false
        }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.85)) {
            cardsRevealed = true
        }
    }

    private var kingSafetyAndPinAlertBar: some View {
        let radar = viewModel.tacticalRadar
        return VStack(alignment: .leading, spacing: 5) {
            if radar.isKingInCheck {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.caption.bold())
                        .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.42))
                    let checkerText = radar.checkingDescriptions.isEmpty
                        ? ""
                        : "（攻擊源：\(radar.checkingDescriptions.joined(separator: "、"))）"
                    Text("國王正被將軍\(checkerText)，必須優先走解將安全步")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                    Spacer()
                }
            }

            if !radar.pinnedPieces.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                    Text("絕對牽制護王：\(radar.pinnedPieces.map(\.summaryText).joined(separator: "、"))")
                        .font(.caption2.bold())
                        .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.55))
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(radar.isKingInCheck ? Color.red.opacity(0.18) : Color.orange.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke((radar.isKingInCheck ? Color.red : Color.orange).opacity(0.55), lineWidth: 1)
        )
    }

    private var tacticalRadarAndSparklineCard: some View {
        let radar = viewModel.tacticalRadar
        let diff = radar.materialDiffForPerspective
        let diffText = diff == 0 ? "均勢 ±0" : (diff > 0 ? "子力 +\(diff)" : "子力 \(diff)")
        let diffColor: Color = diff > 0 ? accentGreen : (diff < 0 ? .orange : Color(white: 0.78))
        let points = viewModel.evalHistoryWhitePct
        let latestWhitePct = points.last ?? 50.0

        return VStack(alignment: .leading, spacing: 7) {
            // Anti-Ban Protection Telemetry Strip
            HStack(spacing: 6) {
                Label("防護指數 \(viewModel.stealthSafetyScore)%", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(accentGreen)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(viewModel.stealthProtectionBadges, id: \.self) { badge in
                            Text(badge)
                                .font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accentGreen.opacity(0.14))
                                .foregroundColor(Color(red: 0.75, green: 0.94, blue: 0.70))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.08))

            HStack(spacing: 6) {
                Label(radar.openingName, systemImage: "book.closed.fill")
                    .font(.caption.bold())
                    .foregroundColor(.cyan)
                    .lineLimit(1)

                Spacer()

                Text(viewModel.sessionAccuracyText)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.15))
                    .clipShape(Capsule())

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
                        Text("我吃: \(radar.capturedByUser.map(\.unicode).joined())")
                            .font(.caption2)
                            .foregroundColor(accentGreen)
                    }
                    if !radar.capturedByOpponent.isEmpty {
                        Text("敵吃: \(radar.capturedByOpponent.map(\.unicode).joined())")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    Spacer(minLength: 0)
                }
            }

            if !radar.hangingDescriptions.isEmpty {
                Label("懸空警訊：\(radar.hangingDescriptions.joined(separator: "、"))", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.bold())
                    .foregroundColor(.red.opacity(0.95))
            }

            if !radar.freeTargetDescriptions.isEmpty {
                Label("免費吃子機會：\(radar.freeTargetDescriptions.joined(separator: "、"))", systemImage: "scope")
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
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.11, green: 0.14, blue: 0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.cyan.opacity(0.20), lineWidth: 1)
        )
    }

    private func qualityColor(for badge: String) -> Color {
        if badge.hasPrefix("[妙手]") { return .cyan }
        if badge.hasPrefix("[最佳]") { return accentGreen }
        if badge.hasPrefix("[良好]") { return .blue }
        if badge.hasPrefix("[偏差]") { return .orange }
        return .red
    }

    private func protectionPill(
        title: String,
        icon: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .bold))
            }
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
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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

private struct LaunchIntroOverlayView: View {
    let accentColor: Color
    let onDismiss: () -> Void

    @State private var pulseScale: CGFloat = 0.78
    @State private var pathProgress: CGFloat = 0.0
    @State private var barProgress: CGFloat = 0.0
    @State private var contentOpacity: Double = 0.0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.070, blue: 0.095),
                    Color(red: 0.082, green: 0.110, blue: 0.135)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .stroke(accentColor.opacity(0.20), lineWidth: 2)
                        .frame(width: 146, height: 146)
                        .scaleEffect(pulseScale)

                    Circle()
                        .stroke(Color.cyan.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 118, height: 118)
                        .scaleEffect(2.0 - pulseScale)

                    // Mini 4x4 animated tactical grid + trajectory stroke
                    ZStack {
                        VStack(spacing: 0) {
                            ForEach(0..<4, id: \.self) { r in
                                HStack(spacing: 0) {
                                    ForEach(0..<4, id: \.self) { c in
                                        Rectangle()
                                            .fill((r + c).isMultiple(of: 2)
                                                  ? Color.white.opacity(0.14)
                                                  : accentColor.opacity(0.24))
                                            .frame(width: 18, height: 18)
                                    }
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(accentColor.opacity(0.65), lineWidth: 1.5)
                        )

                        Path { path in
                            path.move(to: CGPoint(x: 9, y: 63))
                            path.addLine(to: CGPoint(x: 27, y: 45))
                            path.addLine(to: CGPoint(x: 45, y: 9))
                            path.addLine(to: CGPoint(x: 63, y: 27))
                        }
                        .trim(from: 0, to: pathProgress)
                        .stroke(
                            LinearGradient(colors: [.cyan, accentColor], startPoint: .bottomLeading, endPoint: .topTrailing),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 72, height: 72)

                        Image(systemName: "shield.checkered")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: accentColor.opacity(0.6), radius: 8)
                    }
                }

                VStack(spacing: 6) {
                    Text("Chess Bot 輔助大師")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Text("10MB 離線 GM 引擎包 · 防誤封多層護盾已就緒")
                        .font(.caption.bold())
                        .foregroundColor(.cyan)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                        Capsule()
                            .fill(LinearGradient(colors: [.cyan, accentColor], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * barProgress)
                    }
                }
                .frame(width: 180, height: 5)
            }
            .opacity(contentOpacity)
        }
        .onTapGesture {
            onDismiss()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                contentOpacity = 1.0
            }
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                pulseScale = 1.12
            }
            withAnimation(.easeInOut(duration: 0.85)) {
                pathProgress = 1.0
                barProgress = 1.0
            }
        }
    }
}
