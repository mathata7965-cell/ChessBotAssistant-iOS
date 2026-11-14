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
                    VStack(spacing: 12) {
                        // 1. PiP & Background Screenshot Auto-Sync Card
                        PiPPreviewCardView(
                            pipManager: viewModel.pipManager,
                            isAutoSyncEnabled: viewModel.screenshotMonitor.isMonitoring || viewModel.broadcastService.isBroadcastActive,
                            onTogglePiP: {
                                viewModel.togglePiPWithAutoSync()
                            },
                            onToggleAutoSync: {
                                viewModel.toggleAutoScreenshotSync()
                            }
                        )

                        // Chess.com App 實時識別控制台
                        liveRecognitionControlCard

                        // 防誤封與隱私保護狀態列
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                protectionPill(
                                    title: viewModel.engineService.zeroNetworkIsolationMode ? "🔒 零連網隔離:開" : "🌐 雲端連線:開",
                                    isActive: viewModel.engineService.zeroNetworkIsolationMode,
                                    activeColor: accentGreen
                                ) {
                                    viewModel.engineService.zeroNetworkIsolationMode.toggle()
                                    viewModel.triggerAnalysis()
                                }

                                protectionPill(
                                    title: viewModel.engineService.humanMatchSafetyLockEnabled ? "🛡️ 真人局防誤觸:開" : "⚠️ 真人局鎖:關",
                                    isActive: viewModel.engineService.humanMatchSafetyLockEnabled,
                                    activeColor: .cyan
                                ) {
                                    viewModel.engineService.humanMatchSafetyLockEnabled.toggle()
                                }

                                protectionPill(
                                    title: viewModel.engineService.coachPieceOnlyHintMode ? "🎓 教練半提示:開" : "🎓 教練半提示:關",
                                    isActive: viewModel.engineService.coachPieceOnlyHintMode,
                                    activeColor: .orange
                                ) {
                                    viewModel.engineService.coachPieceOnlyHintMode.toggle()
                                }

                                protectionPill(
                                    title: "🧭 \(viewModel.campDetectionMode.displayName)(\(viewModel.perspective == .white ? "白" : "黑"))",
                                    isActive: true,
                                    activeColor: .teal
                                ) {
                                    viewModel.cycleCampDetectionMode()
                                }

                                protectionPill(
                                    title: viewModel.alwaysAnalyzeMyCampTurn ? "♟ 鎖我方回合" : "♟ 依畫面輪次",
                                    isActive: viewModel.alwaysAnalyzeMyCampTurn,
                                    activeColor: .indigo
                                ) {
                                    viewModel.toggleAlwaysAnalyzeMyCampTurn()
                                }

                                protectionPill(
                                    title: "🎭 \(viewModel.engineService.playStyleMode.displayName)",
                                    isActive: viewModel.engineService.playStyleMode != .engineBest,
                                    activeColor: .purple
                                ) {
                                    viewModel.cyclePlayStyleMode()
                                }

                                protectionPill(
                                    title: viewModel.engineService.showOpponentReplyArrow ? "🔮 敵步預測:開" : "🔮 敵步預測:關",
                                    isActive: viewModel.engineService.showOpponentReplyArrow,
                                    activeColor: .red
                                ) {
                                    viewModel.engineService.showOpponentReplyArrow.toggle()
                                }

                                protectionPill(
                                    title: viewModel.voiceAnnounceEnabled ? "🔊 語音播報:開" : "🔊 語音播報:關",
                                    isActive: viewModel.voiceAnnounceEnabled,
                                    activeColor: .mint
                                ) {
                                    viewModel.voiceAnnounceEnabled.toggle()
                                }

                                if viewModel.screenshotMonitor.hasDeletableScreenshot {
                                    protectionPill(
                                        title: "🧹 刪暫存截圖",
                                        isActive: true,
                                        activeColor: .pink
                                    ) {
                                        viewModel.deleteLastScreenshot()
                                    }
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

                        // 3. Quick Action Strip
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                actionChip(
                                    title: "我執\(viewModel.perspective.displayName)",
                                    icon: "arrow.up.arrow.down",
                                    tint: .white
                                ) {
                                    viewModel.flipPerspective()
                                }

                                actionChip(
                                    title: "輪到\(viewModel.boardState.sideToMove.displayName)",
                                    icon: "circle.lefthalf.filled",
                                    tint: viewModel.boardState.sideToMove == .white ? .white : Color(white: 0.75)
                                ) {
                                    viewModel.toggleSideToMove()
                                }

                                actionChip(
                                    title: "走最佳步",
                                    icon: "bolt.fill",
                                    tint: accentGreen,
                                    highlighted: true
                                ) {
                                    viewModel.playBestMove()
                                }

                                actionChip(
                                    title: "掃描截圖",
                                    icon: "camera.viewfinder",
                                    tint: .cyan
                                ) {
                                    viewModel.showScreenshotScannerSheet = true
                                }

                                actionChip(
                                    title: "悔棋",
                                    icon: "arrow.uturn.backward",
                                    tint: .white
                                ) {
                                    viewModel.undoLastMove()
                                }

                                actionChip(
                                    title: "貼上FEN/PGN",
                                    icon: "doc.on.clipboard",
                                    tint: .white
                                ) {
                                    viewModel.pasteFENOrPGNFromClipboard()
                                }

                                actionChip(
                                    title: "擺盤編輯",
                                    icon: "square.grid.3x3",
                                    tint: .white
                                ) {
                                    viewModel.showBoardEditorSheet = true
                                }

                                actionChip(
                                    title: "重置開局",
                                    icon: "arrow.counterclockwise",
                                    tint: .orange
                                ) {
                                    viewModel.resetBoard()
                                }
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
                            onSelectPV: { line in
                                highlightedPVIndex = line.multipvIndex
                            },
                            onPlayPV: { line in
                                viewModel.playPVLine(line)
                            }
                        )

                        // 4.5 Opening Detection, Tactical Radar & Eval Sparkline
                        tacticalRadarAndSparklineCard

                        // 5. Inline Depth, Multi-PV & Auto-Hint Controls
                        VStack(spacing: 10) {
                            HStack(spacing: 12) {
                                Text("深度 D\(viewModel.engineService.targetDepth)")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(accentGreen)
                                    .frame(width: 66, alignment: .leading)

                                Slider(
                                    value: Binding(
                                        get: { Double(viewModel.engineService.targetDepth) },
                                        set: { newVal in
                                            viewModel.engineService.targetDepth = Int(newVal.rounded())
                                        }
                                    ),
                                    in: 4...18,
                                    step: 1,
                                    onEditingChanged: { editing in
                                        if !editing {
                                            viewModel.triggerAnalysis()
                                        }
                                    }
                                )
                                .tint(accentGreen)
                            }

                            HStack(spacing: 10) {
                                Text("候選線")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)

                                Picker("候選線", selection: Binding(
                                    get: { viewModel.engineService.multiPVCount },
                                    set: { newVal in
                                        viewModel.engineService.multiPVCount = newVal
                                        viewModel.triggerAnalysis()
                                    }
                                )) {
                                    Text("1條").tag(1)
                                    Text("2條").tag(2)
                                    Text("3條").tag(3)
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 165)

                                Spacer()

                                Toggle("箭頭提示", isOn: Binding(
                                    get: { viewModel.engineService.autoHintEnabled },
                                    set: { viewModel.engineService.autoHintEnabled = $0 }
                                ))
                                    .labelsHidden()
                                    .tint(accentGreen)
                                Text("箭頭")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(red: 0.11, green: 0.13, blue: 0.15))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

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

    @ViewBuilder
    private var liveRecognitionControlCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.subheadline.bold())
                    .foregroundColor(.cyan)

                Text("Chess.com App 實時識別控制台")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)

                Spacer()

                Text(viewModel.broadcastService.isBroadcastActive ? "直播同步中" : (viewModel.screenshotMonitor.isMonitoring ? "截圖監控中" : "待機"))
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        (viewModel.broadcastService.isBroadcastActive ? Color.green : Color.cyan).opacity(0.20)
                    )
                    .foregroundColor(viewModel.broadcastService.isBroadcastActive ? .green : .cyan)
                    .clipShape(Capsule())
            }

            // 方法 1（免外掛最穩）：懸浮窗 + 截圖 / PiP 控制鈕 / 背面輕點兩下捷徑
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("方法 1（免外掛最穩）")
                        .font(.caption.bold())
                        .foregroundColor(accentGreen)
                    Spacer()
                    Text("支援懸浮窗 ⏯掃描 • ⏩走步 • ⏪悔步")
                        .font(.caption2)
                        .foregroundColor(Color(white: 0.72))
                }

                Button {
                    viewModel.scanLatestScreenshot()
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isScanningScreenshot {
                            ProgressView()
                                .scaleEffect(0.75)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text("⚡ 立即讀取最新 Chess.com 截圖")
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.cyan.opacity(0.20))
                    .foregroundColor(.cyan)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Text("開啟上方「啟動懸浮窗 (PiP)」後，在 Chess.com 截圖約 1 秒自動更新；或直接點懸浮窗上的「⏯」立即重掃，亦可在 iPhone 捷徑設定背面輕點兩下呼叫 chessbot://scan。")
                    .font(.caption2)
                    .foregroundColor(Color(white: 0.68))
            }

            // 方法 2（免截圖螢幕直播實時識別）
            VStack(alignment: .leading, spacing: 4) {
                SystemBroadcastPickerButton(
                    isActive: viewModel.broadcastService.isBroadcastActive,
                    onUnavailableExtension: {
                        viewModel.showBanner("目前安裝的是免外掛單一版 IPA，請使用「方法 1（懸浮窗 + 截圖 / ⏯鍵）」")
                    }
                )
                Text("方法 2（螢幕直播 Extension）：需保留 ChessBroadcastExtension 安裝。已自動對齊重簽名 Bundle ID，點按鈕開啟錄製後切回 Chess.com 即自動推播盤面。")
                    .font(.caption2)
                    .foregroundColor(Color(white: 0.68))
            }

            if viewModel.scanCount > 0 || viewModel.lastRecognizedCropImage != nil {
                HStack(spacing: 10) {
                    if let cropImg = viewModel.lastRecognizedCropImage {
                        Image(uiImage: cropImg)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(accentGreen.opacity(0.6), lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text("已成功識別 \(viewModel.scanCount) 次")
                                .font(.caption.bold())
                                .foregroundColor(accentGreen)
                            if let syncDate = viewModel.lastSyncTimestamp {
                                Text("• \(syncDate, style: .time)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(Color(white: 0.72))
                            }
                        }

                        if let notes = viewModel.lastScanResult?.notes {
                            Text(notes)
                                .font(.caption2)
                                .foregroundColor(Color(white: 0.80))
                                .lineLimit(2)
                        } else if let primary = viewModel.engineService.currentAnalysis?.primaryLine {
                            Text("推薦著法：\(primary.bestMove.san)（\(primary.formattedScore)）")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.11, green: 0.14, blue: 0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.cyan.opacity(0.22), lineWidth: 1)
        )
    }

    private var tacticalRadarAndSparklineCard: some View {
        let radar = viewModel.tacticalRadar
        let diff = radar.materialDiffForPerspective
        let diffText = diff == 0 ? "均勢 ±0" : (diff > 0 ? "子力 +\(diff)" : "子力 \(diff)")
        let diffColor: Color = diff > 0 ? accentGreen : (diff < 0 ? .orange : Color(white: 0.78))
        let points = viewModel.evalHistoryWhitePct
        let latestWhitePct = points.last ?? 50.0

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(radar.openingName, systemImage: "book.closed.fill")
                    .font(.caption.bold())
                    .foregroundColor(.cyan)
                    .lineLimit(1)

                Spacer()

                if let quality = viewModel.lastMoveQualityBadge {
                    Text(quality)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(qualityColor(for: quality))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(qualityColor(for: quality).opacity(0.16))
                        .clipShape(Capsule())
                }

                Text(diffText)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(diffColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(diffColor.opacity(0.16))
                    .clipShape(Capsule())
            }

            HStack(spacing: 6) {
                Text("🧭 \(viewModel.detectedCampReason)")
                    .font(.caption2)
                    .foregroundColor(Color(white: 0.78))
                    .lineLimit(1)
                Spacer()
                Text("⏱ 建議思考 \(radar.recommendedThinkRange)")
                    .font(.caption2.bold())
                    .foregroundColor(.yellow.opacity(0.92))
            }

            if !radar.capturedByUser.isEmpty || !radar.capturedByOpponent.isEmpty {
                HStack(spacing: 12) {
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
                Text("⚠️ 懸空危險：\(radar.hangingDescriptions.joined(separator: "、"))")
                    .font(.caption2.bold())
                    .foregroundColor(.red.opacity(0.95))
            }

            if !radar.freeTargetDescriptions.isEmpty {
                Text("🎯 白吃目標：\(radar.freeTargetDescriptions.joined(separator: "、"))")
                    .font(.caption2.bold())
                    .foregroundColor(accentGreen)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("📊 白方勝率走勢（近 \(points.count) 步）")
                        .font(.caption2)
                        .foregroundColor(Color(white: 0.70))
                    Spacer()
                    Text("白 \(Int(latestWhitePct.rounded()))% / 黑 \(100 - Int(latestWhitePct.rounded()))%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }

                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    ZStack {
                        // 50% baseline
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
                                .frame(width: 6, height: 6)
                                .position(x: w * 0.5, y: y)
                        }
                    }
                }
                .frame(height: 30)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(11)
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
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.bold())
                Text(title)
                    .font(.caption.bold())
            }
            .padding(.horizontal, 11)
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
}
