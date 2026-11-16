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
                                        title: viewModel.engineService.masterPersonaMode.shortName,
                                        icon: viewModel.engineService.masterPersonaMode.icon,
                                        isActive: true,
                                        activeColor: .cyan
                                    ) {
                                        viewModel.cycleMasterPersonaMode()
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

                                    protectionPill(
                                        title: "大螢幕橫幅",
                                        icon: "rectangle.topthird.inset.filled",
                                        isActive: viewModel.bigScreenBannerPromptEnabled,
                                        activeColor: .cyan
                                    ) {
                                        viewModel.toggleBigScreenBannerPrompt()
                                    }

                                    protectionPill(
                                        title: viewModel.pipBigScreenBoardMode ? "PiP 巨型盤" : "PiP 雙顯盤",
                                        icon: "rectangle.inset.filled",
                                        isActive: viewModel.pipBigScreenBoardMode,
                                        activeColor: .indigo
                                    ) {
                                        viewModel.togglePiPBigScreenBoardMode()
                                    }

                                    protectionPill(
                                        title: "配色:\(viewModel.boardTheme.displayName)",
                                        icon: "paintpalette.fill",
                                        isActive: true,
                                        activeColor: .yellow
                                    ) {
                                        viewModel.cycleBoardTheme()
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

                            // King Check, Pin & Immediate Threat Alert Bar
                            if viewModel.isBoardDetected && (
                                viewModel.tacticalRadar.isKingInCheck ||
                                !viewModel.tacticalRadar.pinnedPieces.isEmpty ||
                                (viewModel.threatRadarEnabled && viewModel.tacticalRadar.immediateThreat != nil)
                            ) {
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

                            // 2. Conditional Hero Dashboard & Detected Chessboard
                            if !viewModel.isBoardDetected {
                                waitingForBoardDetectionCard
                                    .opacity(cardsRevealed ? 1 : 0)
                                    .scaleEffect(cardsRevealed ? 1 : 0.98)
                            } else {
                                liveWinRateDashboardCard
                                    .opacity(cardsRevealed ? 1 : 0)
                                    .scaleEffect(cardsRevealed ? 1 : 0.98)

                                detectedBoardSection
                                    .opacity(cardsRevealed ? 1 : 0)
                                    .scaleEffect(cardsRevealed ? 1 : 0.98)

                                // 3. Action Strip
                                HStack(spacing: 6) {
                                    actionChip(
                                        title: "走最佳",
                                        icon: "play.fill",
                                        tint: accentGreen,
                                        highlighted: true
                                    ) {
                                        viewModel.playBestMove()
                                    }

                                    actionChip(
                                        title: "換步",
                                        icon: "arrow.triangle.branch",
                                        tint: .orange
                                    ) {
                                        viewModel.skipBlockedMoveAndReanalyze()
                                    }

                                    actionChip(
                                        title: "大螢幕",
                                        icon: "arrow.up.left.and.arrow.down.right",
                                        tint: .cyan
                                    ) {
                                        viewModel.showFullScreenBigBoard = true
                                    }

                                    actionChip(
                                        title: "悔棋",
                                        icon: "arrow.uturn.backward",
                                        tint: .white
                                    ) {
                                        viewModel.undoLastMove()
                                    }

                                    actionChip(
                                        title: "待機",
                                        icon: "viewfinder",
                                        tint: Color(white: 0.80)
                                    ) {
                                        viewModel.resetBoard()
                                    }

                                    Menu {
                                        Button {
                                            viewModel.forceAnalyzeNow()
                                        } label: {
                                            Label("立即重算當前局面", systemImage: "arrow.clockwise")
                                        }

                                        Button {
                                            viewModel.flipPerspective()
                                        } label: {
                                            Label("切換我方視角（目前：執\(viewModel.perspective == .white ? "白" : "黑")）", systemImage: "arrow.up.arrow.down")
                                        }

                                        Button {
                                            viewModel.showBoardEditorSheet = true
                                        } label: {
                                            Label("手動擺盤與微調", systemImage: "square.grid.3x3.topleft.filled")
                                        }

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

                                        if viewModel.screenshotMonitor.hasDeletableScreenshot {
                                            Button(role: .destructive) {
                                                viewModel.deleteLastScreenshot()
                                            } label: {
                                                Label("刪除暫存截圖", systemImage: "trash")
                                            }
                                        }
                                    } label: {
                                        actionChipLabel(title: "更多", icon: "ellipsis.circle", tint: Color(white: 0.85))
                                    }
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
                                isBoardDetected: viewModel.isBoardDetected,
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
                                    viewModel.selectPreviewPVLine(line)
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
                            if viewModel.isBoardDetected && !viewModel.moveHistorySAN.isEmpty {
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
                .background(
                    Color.clear
                        .sheet(isPresented: $viewModel.showScreenshotScannerSheet) {
                            ScreenshotScannerSheetView(viewModel: viewModel)
                        }
                )
                .background(
                    Color.clear
                        .sheet(isPresented: $viewModel.showBoardEditorSheet) {
                            BoardEditorSheetView(viewModel: viewModel)
                        }
                )
                .fullScreenCover(isPresented: $viewModel.showFullScreenBigBoard) {
                    FullScreenTacticalBoardView(
                        viewModel: viewModel,
                        highlightedPVIndex: $highlightedPVIndex
                    )
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

    private var waitingForBoardDetectionCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.cyan)

                VStack(alignment: .leading, spacing: 3) {
                    Text("等待偵測棋盤")
                        .font(.title3.bold())
                        .foregroundColor(.white)

                    let syncStateText = viewModel.broadcastService.isBroadcastActive
                        ? "螢幕直播實時同步運作中，請切換至 Chess.com 對局畫面"
                        : (viewModel.screenshotMonitor.isMonitoring
                            ? "截圖自動監聽中，在 Chess.com 截圖或開啟直播即可辨識"
                            : "請開啟「啟動懸浮」或進行螢幕直播以自動讀取 Chess.com 棋盤")
                    Text(syncStateText)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.74))
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.scanLatestScreenshot()
                } label: {
                    Label("讀取最新截圖", systemImage: "bolt.fill")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(accentGreen.opacity(0.22))
                        .foregroundColor(accentGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }

                Button {
                    viewModel.showScreenshotScannerSheet = true
                } label: {
                    Label("從相簿選圖", systemImage: "photo.on.rectangle")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.cyan.opacity(0.16))
                        .foregroundColor(.cyan)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }

                Button {
                    viewModel.pasteFENOrPGNFromClipboard()
                } label: {
                    Label("貼上 FEN", systemImage: "doc.on.clipboard")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.09))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.11, green: 0.145, blue: 0.19))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.cyan.opacity(0.32), lineWidth: 1.2)
        )
    }

    private var liveWinRateDashboardCard: some View {
        let primary = viewModel.engineService.currentAnalysis?.primaryLine
        let gamePly = max(1, (viewModel.boardState.fullMoveNumber - 1) * 2 + (viewModel.boardState.sideToMove == .white ? 0 : 1))
        let winPct = primary.map { Int($0.winProbability(for: viewModel.perspective).rounded()) } ?? viewModel.lastKnownWinPct
        let wdl = primary?.wdlBreakdown(for: viewModel.perspective, gamePhasePly: gamePly) ?? viewModel.lastKnownWDL
        let evalStr = primary?.formattedScore ?? viewModel.lastKnownEvalStr
        let campText = viewModel.perspective == .white ? "白方" : "黑方"
        let winTint: Color = winPct >= 52 ? accentGreen : (winPct >= 44 ? .yellow : Color(red: 0.96, green: 0.45, blue: 0.45))

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("我方(\(campText))勝率")
                        .font(.caption.bold())
                        .foregroundColor(.cyan)
                    Text("\(winPct)%")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(winTint)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("評估 \(evalStr)")
                            .font(.system(size: 16, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)

                        Text(viewModel.isWaitingForOpponentReply ? "等待對手落子" : "輪到\(campText)")
                            .font(.system(size: 10.5, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background((viewModel.isWaitingForOpponentReply ? Color.cyan : accentGreen).opacity(0.18))
                            .foregroundColor(viewModel.isWaitingForOpponentReply ? .cyan : accentGreen)
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 6) {
                        Text(viewModel.detectedCampReason)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(Color(white: 0.68))
                            .lineLimit(1)

                        Text(viewModel.paceRemainingSeconds > 0 ? "建議停頓 \(viewModel.paceRemainingSeconds)s" : "節奏就緒")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((viewModel.paceRemainingSeconds > 0 ? Color.orange : Color.cyan).opacity(0.16))
                            .foregroundColor(viewModel.paceRemainingSeconds > 0 ? .orange : .cyan)
                            .clipShape(Capsule())
                    }
                }
            }

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
                            .fill(Color(red: 0.30, green: 0.86, blue: 0.44))
                            .frame(width: winW)
                        Rectangle()
                            .fill(Color(white: 0.48))
                            .frame(width: drawW)
                        Rectangle()
                            .fill(Color(red: 0.92, green: 0.34, blue: 0.38))
                            .frame(width: lossW)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 8)

                HStack {
                    Text("勝 \(wdl.win)%")
                        .foregroundColor(Color(red: 0.45, green: 0.92, blue: 0.54))
                    Spacer()
                    Text("和 \(wdl.draw)%")
                        .foregroundColor(Color(white: 0.72))
                    Spacer()
                    Text("負 \(wdl.loss)%")
                        .foregroundColor(Color(red: 0.98, green: 0.50, blue: 0.48))
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.115, green: 0.155, blue: 0.20))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(winTint.opacity(0.30), lineWidth: 1.2)
        )
    }

    private var detectedBoardSection: some View {
        let campText = viewModel.perspective == .white ? "白方視角" : "黑方視角"
        let activeLines = viewModel.isWaitingForOpponentReply ? [] : (viewModel.engineService.currentAnalysis?.lines ?? [])

        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accentGreen)
                    .frame(width: 7, height: 7)

                Text("已偵測實戰棋盤 · \(campText)")
                    .font(.caption.bold())
                    .foregroundColor(.white)

                Spacer()

                Button {
                    viewModel.flipPerspective()
                } label: {
                    Label("翻轉", systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 10.5, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }

                Button {
                    viewModel.showFullScreenBigBoard = true
                } label: {
                    Label("大螢幕全屏", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10.5, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.cyan.opacity(0.18))
                        .foregroundColor(.cyan)
                        .clipShape(Capsule())
                }
            }

            HStack(alignment: .center, spacing: 8) {
                EvalBarView(
                    analysis: viewModel.engineService.currentAnalysis,
                    perspective: viewModel.perspective,
                    isAnalyzing: viewModel.engineService.isAnalyzing
                )

                InteractiveChessBoardView(
                    boardState: viewModel.displayedBoardState,
                    perspective: viewModel.perspective,
                    selectedSquare: viewModel.previewPlyOffset == 0 ? viewModel.selectedSquare : nil,
                    legalTargets: viewModel.previewPlyOffset == 0 ? viewModel.legalTargetsForSelection : [],
                    lastMove: viewModel.displayedLastMove,
                    pvLines: viewModel.previewPlyOffset == 0 ? activeLines : [],
                    showAutoHintArrows: viewModel.previewPlyOffset == 0 && viewModel.engineService.autoHintEnabled && !viewModel.isWaitingForOpponentReply,
                    highlightedPVIndex: highlightedPVIndex,
                    coachPieceOnlyMode: viewModel.engineService.coachPieceOnlyHintMode,
                    isSafetyLocked: viewModel.isFairPlaySafetyLocked,
                    hangingSquares: viewModel.previewPlyOffset == 0 ? Set(viewModel.tacticalRadar.hangingFriendlySquares) : [],
                    showOpponentReplyArrow: viewModel.engineService.showOpponentReplyArrow,
                    boardTheme: viewModel.boardTheme,
                    onTapSquare: { square in
                        guard viewModel.previewPlyOffset == 0 else {
                            viewModel.resetPreviewToLive()
                            return
                        }
                        viewModel.tapSquare(square)
                    }
                )
            }
            .aspectRatio(1.09, contentMode: .fit)

            // Interactive PV Continuation Stepper
            if viewModel.previewMaxPlies > 0 && !viewModel.isFairPlaySafetyLocked && !viewModel.isWaitingForOpponentReply && !viewModel.engineService.coachPieceOnlyHintMode {
                HStack(spacing: 6) {
                    Button {
                        viewModel.stepPreviewBackward()
                    } label: {
                        Label("上一步", systemImage: "chevron.left")
                            .font(.system(size: 10.5, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(viewModel.previewPlyOffset > 0 ? 0.12 : 0.04))
                            .foregroundColor(viewModel.previewPlyOffset > 0 ? .white : Color(white: 0.42))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .disabled(viewModel.previewPlyOffset == 0)

                    Spacer()

                    if viewModel.previewPlyOffset == 0 {
                        Text("推演後續變化 (線#\(viewModel.activePreviewLine?.multipvIndex ?? 1) · 共 \(viewModel.previewMaxPlies) 手)")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(white: 0.72))
                    } else {
                        Text("推演第 \(viewModel.previewPlyOffset)/\(viewModel.previewMaxPlies) 手: \(viewModel.previewStepMoveLabel)")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundColor(.yellow)
                    }

                    Spacer()

                    if viewModel.previewPlyOffset > 0 {
                        Button {
                            viewModel.resetPreviewToLive()
                        } label: {
                            Text("回實戰")
                                .font(.system(size: 10.5, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.cyan.opacity(0.20))
                                .foregroundColor(.cyan)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                    }

                    Button {
                        viewModel.stepPreviewForward()
                    } label: {
                        HStack(spacing: 3) {
                            Text("下一步")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 10.5, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(viewModel.previewPlyOffset < viewModel.previewMaxPlies ? accentGreen.opacity(0.22) : Color.white.opacity(0.04))
                        .foregroundColor(viewModel.previewPlyOffset < viewModel.previewMaxPlies ? accentGreen : Color(white: 0.42))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .disabled(viewModel.previewPlyOffset >= viewModel.previewMaxPlies)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }

            // Big-Screen Overlay Modes Quick Switch Bar
            HStack(spacing: 6) {
                Button {
                    viewModel.toggleBigScreenBannerPrompt()
                } label: {
                    Label(
                        "頂部橫幅:\(viewModel.bigScreenBannerPromptEnabled ? "開" : "關")",
                        systemImage: "rectangle.topthird.inset.filled"
                    )
                    .font(.system(size: 10.5, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(viewModel.bigScreenBannerPromptEnabled ? Color.cyan.opacity(0.16) : Color.white.opacity(0.06))
                    .foregroundColor(viewModel.bigScreenBannerPromptEnabled ? .cyan : Color(white: 0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    viewModel.togglePiPBigScreenBoardMode()
                } label: {
                    Label(
                        "懸浮:\(viewModel.pipBigScreenBoardMode ? "巨型盤" : "雙顯盤")",
                        systemImage: "pip.fill"
                    )
                    .font(.system(size: 10.5, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(viewModel.pipBigScreenBoardMode ? Color.indigo.opacity(0.24) : Color.white.opacity(0.06))
                    .foregroundColor(viewModel.pipBigScreenBoardMode ? Color(red: 0.68, green: 0.72, blue: 1.0) : Color(white: 0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    viewModel.showBoardEditorSheet = true
                } label: {
                    Label("擺盤微調", systemImage: "square.grid.3x3.topleft.filled")
                        .font(.system(size: 10.5, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.06))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.11, green: 0.145, blue: 0.19))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accentGreen.opacity(0.25), lineWidth: 1.2)
        )
    }

    private var kingSafetyAndPinAlertBar: some View {
        let radar = viewModel.tacticalRadar
        let activeThreat = viewModel.threatRadarEnabled ? radar.immediateThreat : nil
        let isUrgent = radar.isKingInCheck || (activeThreat?.severity ?? 0) >= 2

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

            if let threat = activeThreat {
                HStack(spacing: 6) {
                    Image(systemName: threat.severity >= 3 ? "bolt.shield.fill" : "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundColor(threat.severity >= 2 ? Color(red: 1.0, green: 0.45, blue: 0.42) : .orange)
                    Text(threat.summary)
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
                .fill(isUrgent ? Color.red.opacity(0.18) : Color.orange.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke((isUrgent ? Color.red : Color.orange).opacity(0.55), lineWidth: 1)
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

            if viewModel.isBoardDetected {
                Divider()
                    .background(Color.white.opacity(0.08))

                HStack(spacing: 6) {
                    Label(radar.openingName, systemImage: "book.closed.fill")
                        .font(.caption.bold())
                        .foregroundColor(.cyan)
                        .lineLimit(1)

                    Text(viewModel.engineService.lastAIJudgmentReason)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.24))
                        .foregroundColor(Color(red: 0.72, green: 0.86, blue: 1.0))
                        .clipShape(Capsule())
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
                        let w = max(1, geo.size.width)
                        let h = max(1, geo.size.height)
                        ZStack {
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: h * 0.5))
                                path.addLine(to: CGPoint(x: w, y: h * 0.5))
                            }
                            .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                            if points.count >= 2 {
                                Path { path in
                                    for (idx, val) in points.enumerated() {
                                        let finiteVal = val.isFinite ? val : 50.0
                                        let x = w * CGFloat(idx) / CGFloat(max(1, points.count - 1))
                                        let y = h * (1.0 - CGFloat(min(100.0, max(0.0, finiteVal))) / 100.0)
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
                                let finiteVal = onlyVal.isFinite ? onlyVal : 50.0
                                let y = h * (1.0 - CGFloat(min(100.0, max(0.0, finiteVal))) / 100.0)
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
                        .stroke(accentColor.opacity(0.22), lineWidth: 2)
                        .frame(width: 148, height: 148)
                        .scaleEffect(pulseScale)

                    Circle()
                        .stroke(Color.cyan.opacity(0.32), lineWidth: 1.8)
                        .frame(width: 112, height: 112)
                        .scaleEffect(2.0 - pulseScale)

                    Circle()
                        .fill(Color(red: 0.11, green: 0.16, blue: 0.21))
                        .frame(width: 78, height: 78)
                        .overlay(
                            Circle()
                                .stroke(accentColor.opacity(0.65), lineWidth: 1.5)
                        )

                    Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(accentColor)
                        .shadow(color: accentColor.opacity(0.6), radius: 8)
                }

                VStack(spacing: 6) {
                    let shortVer = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "2.0.0"
                    let buildNum = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "2"
                    Text("Chess Bot 輔助大師")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Text("v\(shortVer) (Build \(buildNum)) · 10MB 離線 GM 引擎包 · 大師AI自理系統就緒")
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
                barProgress = 1.0
            }
        }
    }
}

private struct FullScreenTacticalBoardView: View {
    @ObservedObject var viewModel: AssistantViewModel
    @Binding var highlightedPVIndex: Int?
    @Environment(\.dismiss) private var dismiss

    private let accentGreen = Color(red: 0.506, green: 0.714, blue: 0.298)

    var body: some View {
        let primary = viewModel.engineService.currentAnalysis?.primaryLine
        let gamePly = max(1, (viewModel.boardState.fullMoveNumber - 1) * 2 + (viewModel.boardState.sideToMove == .white ? 0 : 1))
        let winPct = primary.map { Int($0.winProbability(for: viewModel.perspective).rounded()) } ?? viewModel.lastKnownWinPct
        let wdl = primary?.wdlBreakdown(for: viewModel.perspective, gamePhasePly: gamePly) ?? viewModel.lastKnownWDL
        let evalStr = primary?.formattedScore ?? viewModel.lastKnownEvalStr
        let winTint: Color = winPct >= 52 ? accentGreen : (winPct >= 44 ? .yellow : Color(red: 0.96, green: 0.45, blue: 0.45))
        let activeLines = viewModel.isWaitingForOpponentReply ? [] : (viewModel.engineService.currentAnalysis?.lines ?? [])

        ZStack {
            Color(red: 0.055, green: 0.068, blue: 0.088)
                .ignoresSafeArea()

            GeometryReader { geo in
                let isLandscape = geo.size.width > geo.size.height

                VStack(spacing: 10) {
                    // Top Bar
                    HStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(accentGreen)
                                .frame(width: 8, height: 8)
                            Text("大螢幕戰術投影 · \(viewModel.perspective == .white ? "執白" : "執黑")")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                        }

                        Spacer()

                        Button {
                            viewModel.toggleBigScreenBannerPrompt()
                        } label: {
                            Label(
                                "頂部橫幅:\(viewModel.bigScreenBannerPromptEnabled ? "開" : "關")",
                                systemImage: "rectangle.topthird.inset.filled"
                            )
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(viewModel.bigScreenBannerPromptEnabled ? Color.cyan.opacity(0.20) : Color.white.opacity(0.08))
                            .foregroundColor(viewModel.bigScreenBannerPromptEnabled ? .cyan : .white)
                            .clipShape(Capsule())
                        }

                        Button {
                            viewModel.showFullScreenBigBoard = false
                            dismiss()
                        } label: {
                            Label("退出全屏", systemImage: "xmark.circle.fill")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.24))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }

                    if isLandscape {
                        HStack(spacing: 16) {
                            boardBlock(activeLines: activeLines)
                                .frame(maxWidth: geo.size.height * 0.85, maxHeight: .infinity)

                            hudBlock(primary: primary, winPct: winPct, wdl: wdl, evalStr: evalStr, winTint: winTint)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        hudBlock(primary: primary, winPct: winPct, wdl: wdl, evalStr: evalStr, winTint: winTint)

                        Spacer(minLength: 0)

                        boardBlock(activeLines: activeLines)

                        Spacer(minLength: 0)
                    }

                    // Bottom Action Strip
                    HStack(spacing: 8) {
                        Button {
                            viewModel.playBestMove()
                        } label: {
                            Label("走最佳步", systemImage: "play.fill")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(accentGreen)
                                .foregroundColor(Color(red: 0.05, green: 0.08, blue: 0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Button {
                            viewModel.skipBlockedMoveAndReanalyze()
                        } label: {
                            Label("王受阻換步", systemImage: "arrow.triangle.branch")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.orange.opacity(0.24))
                                .foregroundColor(.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Button {
                            viewModel.flipPerspective()
                        } label: {
                            Label("翻轉視角", systemImage: "arrow.up.arrow.down")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.10))
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(12)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func boardBlock(activeLines: [PVLine]) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                EvalBarView(
                    analysis: viewModel.engineService.currentAnalysis,
                    perspective: viewModel.perspective,
                    isAnalyzing: viewModel.engineService.isAnalyzing
                )

                InteractiveChessBoardView(
                    boardState: viewModel.displayedBoardState,
                    perspective: viewModel.perspective,
                    selectedSquare: viewModel.previewPlyOffset == 0 ? viewModel.selectedSquare : nil,
                    legalTargets: viewModel.previewPlyOffset == 0 ? viewModel.legalTargetsForSelection : [],
                    lastMove: viewModel.displayedLastMove,
                    pvLines: viewModel.previewPlyOffset == 0 ? activeLines : [],
                    showAutoHintArrows: viewModel.previewPlyOffset == 0 && viewModel.engineService.autoHintEnabled && !viewModel.isWaitingForOpponentReply,
                    highlightedPVIndex: highlightedPVIndex,
                    coachPieceOnlyMode: viewModel.engineService.coachPieceOnlyHintMode,
                    isSafetyLocked: viewModel.isFairPlaySafetyLocked,
                    hangingSquares: viewModel.previewPlyOffset == 0 ? Set(viewModel.tacticalRadar.hangingFriendlySquares) : [],
                    showOpponentReplyArrow: viewModel.engineService.showOpponentReplyArrow,
                    boardTheme: viewModel.boardTheme,
                    onTapSquare: { square in
                        guard viewModel.previewPlyOffset == 0 else {
                            viewModel.resetPreviewToLive()
                            return
                        }
                        viewModel.tapSquare(square)
                    }
                )
            }

            if viewModel.previewMaxPlies > 0 && !viewModel.isFairPlaySafetyLocked && !viewModel.isWaitingForOpponentReply && !viewModel.engineService.coachPieceOnlyHintMode {
                HStack(spacing: 8) {
                    Button {
                        viewModel.stepPreviewBackward()
                    } label: {
                        Label("上一步", systemImage: "chevron.left")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(viewModel.previewPlyOffset > 0 ? 0.14 : 0.05))
                            .foregroundColor(viewModel.previewPlyOffset > 0 ? .white : Color(white: 0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(viewModel.previewPlyOffset == 0)

                    Spacer()

                    Text(viewModel.previewPlyOffset == 0
                         ? "續著推演 (共 \(viewModel.previewMaxPlies) 手)"
                         : "推演 \(viewModel.previewPlyOffset)/\(viewModel.previewMaxPlies): \(viewModel.previewStepMoveLabel)")
                        .font(.caption.bold().monospaced())
                        .foregroundColor(viewModel.previewPlyOffset == 0 ? Color(white: 0.78) : .yellow)

                    Spacer()

                    if viewModel.previewPlyOffset > 0 {
                        Button {
                            viewModel.resetPreviewToLive()
                        } label: {
                            Text("回實戰")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.cyan.opacity(0.22))
                                .foregroundColor(.cyan)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    Button {
                        viewModel.stepPreviewForward()
                    } label: {
                        HStack(spacing: 3) {
                            Text("下一步")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(viewModel.previewPlyOffset < viewModel.previewMaxPlies ? accentGreen.opacity(0.25) : Color.white.opacity(0.05))
                        .foregroundColor(viewModel.previewPlyOffset < viewModel.previewMaxPlies ? accentGreen : Color(white: 0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(viewModel.previewPlyOffset >= viewModel.previewMaxPlies)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func hudBlock(
        primary: PVLine?,
        winPct: Int,
        wdl: (win: Int, draw: Int, loss: Int),
        evalStr: String,
        winTint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("我方勝率")
                        .font(.caption.bold())
                        .foregroundColor(.cyan)
                    Text("\(winPct)%")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(winTint)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("評估 \(evalStr)")
                            .font(.headline.monospaced())
                            .foregroundColor(.white)

                        if let mate = primary?.mateInMoves {
                            let isMyMate = (viewModel.perspective == .white && mate > 0) || (viewModel.perspective == .black && mate < 0)
                            Text(isMyMate ? "[必殺M\(abs(mate))]" : "[敵殺M\(abs(mate))]")
                                .font(.caption2.bold().monospaced())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isMyMate ? Color(red: 1.0, green: 0.78, blue: 0.22) : Color(red: 0.92, green: 0.28, blue: 0.30))
                                .foregroundColor(isMyMate ? Color(red: 0.14, green: 0.08, blue: 0.0) : .white)
                                .clipShape(Capsule())
                        }

                        Spacer()
                        Text("勝\(wdl.win)% 和\(wdl.draw)% 負\(wdl.loss)%")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundColor(Color(white: 0.85))
                    }

                    GeometryReader { barGeo in
                        let w = max(1, barGeo.size.width)
                        let safeWin = max(0, min(100, wdl.win))
                        let safeDraw = max(0, min(100 - safeWin, wdl.draw))
                        let winW = w * CGFloat(safeWin) / 100.0
                        let drawW = w * CGFloat(safeDraw) / 100.0
                        let lossW = max(0, w - winW - drawW)
                        HStack(spacing: 1) {
                            Rectangle().fill(Color(red: 0.30, green: 0.86, blue: 0.44)).frame(width: winW)
                            Rectangle().fill(Color(white: 0.48)).frame(width: drawW)
                            Rectangle().fill(Color(red: 0.92, green: 0.34, blue: 0.38)).frame(width: lossW)
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 10)
                }
            }

            if viewModel.threatRadarEnabled, let threat = viewModel.tacticalRadar.immediateThreat {
                HStack(spacing: 6) {
                    Image(systemName: threat.severity >= 3 ? "bolt.shield.fill" : "exclamationmark.triangle.fill")
                        .font(.caption.bold())
                        .foregroundColor(threat.severity >= 2 ? Color(red: 1.0, green: 0.45, blue: 0.42) : .orange)
                    Text(threat.summary)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background((threat.severity >= 2 ? Color.red : Color.orange).opacity(0.20))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider().background(Color.white.opacity(0.10))

            if viewModel.isFairPlaySafetyLocked {
                Text("[安全鎖定] 疑似計時對局，已隱藏建議走法")
                    .font(.headline.bold())
                    .foregroundColor(.red)
            } else if viewModel.isWaitingForOpponentReply {
                Text("[等待對手落子] 畫面穩定後將立即計算最佳反擊")
                    .font(.headline.bold())
                    .foregroundColor(.cyan)
            } else if let primary, viewModel.engineService.autoHintEnabled {
                let movingPiece = viewModel.boardState.piece(at: primary.bestMove.from)
                let pieceFullName = movingPiece?.type.fullChineseName ?? "棋子"
                let posHint = "\(primary.bestMove.from.relativePositionHint(for: viewModel.perspective)) -> \(primary.bestMove.to.relativePositionHint(for: viewModel.perspective))"
                let reasonText = primary.tacticalReason.isEmpty
                    ? viewModel.boardState.explainMoveTactics(primary.bestMove)
                    : primary.tacticalReason
                let replyStr = (viewModel.engineService.showOpponentReplyArrow ? primary.predictedOpponentReply?.san : nil) ?? "-"
                let currentSearchMs = viewModel.engineService.currentAnalysis?.searchTimeMs ?? 0
                let msTag = currentSearchMs > 0 ? " · \(currentSearchMs)ms" : ""

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("#1 \(pieceFullName)  \(primary.bestMove.coordinateDisplay)  [\(primary.bestMove.san)]")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                        Spacer()
                        if !msTag.isEmpty {
                            Text("\(viewModel.engineService.currentAnalysis?.engineSource ?? "引擎")\(msTag)")
                                .font(.caption2.bold().monospaced())
                                .foregroundColor(.cyan)
                        }
                    }

                    HStack(spacing: 8) {
                        Text("螢幕位置：\(posHint)")
                            .font(.subheadline.bold().monospaced())
                            .foregroundColor(.cyan)
                        Spacer()
                        Text("[預測敵應] \(replyStr)")
                            .font(.caption.bold())
                            .foregroundColor(Color(white: 0.85))
                    }

                    Text("戰術目的：\(reasonText)")
                        .font(.subheadline.bold())
                        .foregroundColor(Color(red: 0.62, green: 0.96, blue: 0.72))
                }
            } else {
                Text("正在計算當前局面的最佳安全戰術...")
                    .font(.subheadline.bold())
                    .foregroundColor(Color(white: 0.80))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.11, green: 0.15, blue: 0.20))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(winTint.opacity(0.35), lineWidth: 1.5)
        )
    }
}
