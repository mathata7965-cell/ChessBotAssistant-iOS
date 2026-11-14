import SwiftUI

struct MainAssistantView: View {
    @StateObject private var viewModel = AssistantViewModel()
    @State private var highlightedPVIndex: Int? = 1

    private let accentGreen = Color(red: 0.506, green: 0.714, blue: 0.298) // #81B64C

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.082, green: 0.094, blue: 0.110)
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    Picker("運作模式", selection: $viewModel.isLiveWebMode) {
                        Text("📸 官方 App 雙開同步").tag(false)
                        Text("⚡ 內建實時直連 (免截圖)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                    if viewModel.isLiveWebMode {
                        liveWebAssistantWorkspace
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                // 1. PiP & Background Screenshot Auto-Sync Card
                                PiPPreviewCardView(
                                    pipManager: viewModel.pipManager,
                                    isAutoSyncEnabled: viewModel.screenshotMonitor.isMonitoring,
                                    onTogglePiP: {
                                        viewModel.togglePiPWithAutoSync()
                                    },
                                    onToggleAutoSync: {
                                        viewModel.toggleAutoScreenshotSync()
                                    }
                                )

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
                            onSelectPV: { line in
                                highlightedPVIndex = line.multipvIndex
                            },
                            onPlayPV: { line in
                                viewModel.playPVLine(line)
                            }
                        )

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
                    } // end if/else isLiveWebMode
                } // end outer VStack
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
    private var liveWebAssistantWorkspace: some View {
        let primary = viewModel.engineService.currentAnalysis?.primaryLine
        let lines = Array((viewModel.engineService.currentAnalysis?.lines ?? []).prefix(3))
        let evalText = primary?.formattedScore ?? "0.00"
        let winPct = Int((primary?.winProbability(for: viewModel.perspective) ?? 50.0).rounded())
        let depthStr = viewModel.engineService.currentAnalysis.map { "D\($0.depthReached)" } ?? "..."

        VStack(spacing: 8) {
            // Compact Live Multi-PV Strip
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(evalText)
                        .font(.system(size: 20, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("輪到 \(viewModel.boardState.sideToMove.displayName) • 勝率 \(winPct)%")
                            .font(.caption.bold())
                            .foregroundColor(Color(white: 0.85))
                        Text("\(depthStr) • 實時 DOM 同步中 (免截圖)")
                            .font(.caption2)
                            .foregroundColor(accentGreen)
                    }

                    Spacer()

                    Button {
                        viewModel.engineService.coachPieceOnlyHintMode.toggle()
                    } label: {
                        Text(viewModel.engineService.coachPieceOnlyHintMode ? "🎓 半提示" : "全箭頭")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(viewModel.engineService.coachPieceOnlyHintMode ? Color.orange.opacity(0.25) : accentGreen.opacity(0.22))
                            .foregroundColor(viewModel.engineService.coachPieceOnlyHintMode ? .orange : accentGreen)
                            .clipShape(Capsule())
                    }

                    Button {
                        viewModel.reloadLiveWebBoard()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.bold())
                            .padding(6)
                            .background(Color.white.opacity(0.10))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                            let rankColors: [Color] = [accentGreen, .cyan, .orange]
                            let pillColor = rankColors[min(idx, rankColors.count - 1)]
                            let labelText: String = {
                                if viewModel.isFairPlaySafetyLocked {
                                    return "#\(idx + 1) 已鎖定"
                                } else if viewModel.engineService.coachPieceOnlyHintMode {
                                    let pName = viewModel.boardState.piece(at: line.bestMove.from)?.type.displayName ?? "棋子"
                                    return "#\(idx + 1) 動\(pName) \(line.bestMove.from.algebraic) (\(line.formattedScore))"
                                } else {
                                    return "#\(idx + 1) \(line.bestMove.san) (\(line.formattedScore))"
                                }
                            }()

                            Text(labelText)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(pillColor.opacity(0.16))
                                .foregroundColor(.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(pillColor.opacity(0.65), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.11, green: 0.14, blue: 0.18))
            )

            // Side-by-side Eval Bar + Built-in Live Chess.com Computer Board WebView
            HStack(spacing: 6) {
                EvalBarView(
                    analysis: viewModel.engineService.currentAnalysis,
                    perspective: viewModel.perspective,
                    isAnalyzing: viewModel.engineService.isAnalyzing
                )

                LiveChessWebView(
                    lines: viewModel.engineService.currentAnalysis?.lines ?? [],
                    showArrows: viewModel.engineService.autoHintEnabled
                        && !viewModel.isFairPlaySafetyLocked
                        && !viewModel.engineService.coachPieceOnlyHintMode,
                    coachPieceOnly: viewModel.engineService.coachPieceOnlyHintMode
                        && viewModel.engineService.autoHintEnabled
                        && !viewModel.isFairPlaySafetyLocked,
                    reloadToken: viewModel.liveWebReloadToken,
                    onBoardSync: { fenBoardPart, isFlipped, turnHint in
                        viewModel.handleLiveWebBoardUpdate(
                            fenBoardPart: fenBoardPart,
                            isFlipped: isFlipped,
                            turnHint: turnHint
                        )
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
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
