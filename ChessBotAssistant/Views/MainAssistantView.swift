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

                ScrollView {
                    VStack(spacing: 12) {
                        // 1. PiP & Background Screenshot Auto-Sync Card
                        PiPPreviewCardView(
                            pipManager: viewModel.pipManager,
                            isAutoSyncEnabled: viewModel.screenshotMonitor.isMonitoring,
                            onToggleAutoSync: {
                                viewModel.toggleAutoScreenshotSync()
                            }
                        )

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

                                Toggle("箭頭提示", isOn: $viewModel.engineService.autoHintEnabled)
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
