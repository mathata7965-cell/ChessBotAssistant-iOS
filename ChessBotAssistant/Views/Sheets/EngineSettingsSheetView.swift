import SwiftUI

struct EngineSettingsSheetView: View {
    @ObservedObject var viewModel: AssistantViewModel
    @ObservedObject var engineService: ChessEngineService
    @Environment(\.dismiss) private var dismiss

    init(viewModel: AssistantViewModel) {
        self.viewModel = viewModel
        self._engineService = ObservedObject(wrappedValue: viewModel.engineService)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $engineService.zeroNetworkIsolationMode) {
                        Label("100% 純本機零連網隔離模式", systemImage: "lock.shield.fill")
                    }
                    .tint(Color(red: 0.50, green: 0.78, blue: 0.35))

                    Text("開啟時所有分析皆於本機完成，不發送任何棋局至外部伺服器（無網路請求足跡）。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle(isOn: $engineService.humanMatchSafetyLockEnabled) {
                        Label("偵測到真人計時局自動鎖定提示", systemImage: "checkmark.shield.fill")
                    }
                    .tint(.cyan)

                    Text("辨識截圖時若發現倒數計時器且無 Bot/電腦標記，自動隱藏箭頭與走法防止誤封。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle(isOn: $engineService.coachPieceOnlyHintMode) {
                        Label("教練半提示模式（僅高亮起點格）", systemImage: "graduationcap.fill")
                    }
                    .tint(.orange)

                    Picker("擬人實力目標 (自然防封)", selection: $engineService.humanTargetElo) {
                        Text("1200 (休閒娛樂)").tag(1200)
                        Text("1500 (中階玩家)").tag(1500)
                        Text("1650 (自然均衡)").tag(1650)
                        Text("1900 (俱樂部高手)").tag(1900)
                        Text("2200 (準大師水準)").tag(2200)
                        Text("最強引擎不讓分").tag(0)
                    }

                    Button(role: .destructive) {
                        viewModel.deleteLastScreenshot()
                    } label: {
                        Label("刪除最近一張辨識截圖", systemImage: "trash")
                    }
                    .disabled(!viewModel.screenshotMonitor.hasDeletableScreenshot)
                } header: {
                    Label("防誤封與隱私安全防護", systemImage: "shield.lefthalf.filled")
                }

                Section {
                    Picker("我方陣營偵測", selection: Binding(
                        get: { viewModel.campDetectionMode },
                        set: { newMode in
                            if viewModel.campDetectionMode != newMode {
                                viewModel.setCampDetectionMode(newMode)
                            }
                        }
                    )) {
                        ForEach(CampDetectionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Text("判定依據：\(viewModel.detectedCampReason)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("掃描後永遠分析我方回合", isOn: Binding(
                        get: { viewModel.alwaysAnalyzeMyCampTurn },
                        set: { newVal in
                            if viewModel.alwaysAnalyzeMyCampTurn != newVal {
                                viewModel.toggleAlwaysAnalyzeMyCampTurn()
                            }
                        }
                    ))
                    .tint(Color(red: 0.50, green: 0.78, blue: 0.35))

                    Picker("下棋風格 (防封擬人化)", selection: $engineService.playStyleMode) {
                        ForEach(PlayStyleMode.allCases) { style in
                            Label(style.displayName, systemImage: style.icon).tag(style)
                        }
                    }

                    Picker("對手 Bot 針對克制", selection: $engineService.botTargetProfile) {
                        ForEach(BotTargetProfile.allCases) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }

                    Text(engineService.botTargetProfile.tacticTip)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("棋盤配色主題 (含 PiP 同步)", selection: $viewModel.boardTheme) {
                        ForEach(BoardTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }

                    Toggle(isOn: $engineService.showOpponentReplyArrow) {
                        Label("顯示對手回應預測箭頭（紅色虛線）", systemImage: "arrow.uturn.down.circle.fill")
                    }
                    .tint(.red)

                    Toggle(isOn: $viewModel.voiceAnnounceEnabled) {
                        Label("掃描後中文語音播報最佳步", systemImage: "speaker.wave.2.fill")
                    }
                    .tint(.cyan)
                } header: {
                    Label("陣營判斷、風格與進階戰術設定", systemImage: "safari.fill")
                }

                Section("引擎思考設定") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("思考深度 (Depth)")
                            Spacer()
                            Text("Depth \(engineService.targetDepth)")
                                .font(.system(.body, design: .monospaced).bold())
                                .foregroundColor(Color(red: 0.50, green: 0.78, blue: 0.35))
                        }
                        Slider(
                            value: Binding(
                                get: { Double(engineService.targetDepth) },
                                set: { engineService.targetDepth = Int($0.rounded()) }
                            ),
                            in: 4...18,
                            step: 1
                        )
                        .tint(Color(red: 0.50, green: 0.78, blue: 0.35))
                        Text("深度越高分析越精準（雲端 Stockfish NNUE 最高支援 D15+，離線本機為 D5 快速運算）。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Picker("候選走法數量 (Multi-PV)", selection: $engineService.multiPVCount) {
                        Text("1 條 (最佳步)").tag(1)
                        Text("2 條推薦").tag(2)
                        Text("3 條推薦").tag(3)
                    }

                    Toggle("自動顯示最佳走法箭頭", isOn: $engineService.autoHintEnabled)
                        .tint(Color(red: 0.50, green: 0.78, blue: 0.35))

                    Toggle("優先使用雲端 Stockfish 16 NNUE", isOn: $engineService.useCloudStockfish)
                        .tint(Color(red: 0.50, green: 0.78, blue: 0.35))
                        .disabled(engineService.zeroNetworkIsolationMode)

                    if engineService.zeroNetworkIsolationMode {
                        Text("目前處於「零連網隔離模式」，若要啟用雲端 Stockfish 請先關閉上方隔離模式。")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Section("Chess.com App 雙開使用說明") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("1. 先在本 App 點擊「啟動懸浮窗 (PiP)」與「開啟截圖同步」", systemImage: "1.circle.fill")
                        Label("2. 切換回官方 Chess.com App 開始跟機器人對戰", systemImage: "2.circle.fill")
                        Label("3. 輪到您時按下手機側邊鍵+音量鍵截圖，懸浮窗會於 1 秒內自動辨識並畫出最佳走法箭頭", systemImage: "3.circle.fill")
                        Label("4. 也可於懸浮窗旁邊看盤，或利用「手動同步棋盤」直接點兩步同步局面", systemImage: "4.circle.fill")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                }

                Section {
                    let pack = OfflineEnginePack.shared
                    HStack {
                        Text("離線引擎包狀態")
                        Spacer()
                        Text(pack.isLoaded ? "已載入 (\(pack.packSizeMBString))" : "待載入")
                            .font(.caption.bold())
                            .foregroundColor(pack.isLoaded ? Color(red: 0.50, green: 0.78, blue: 0.35) : .orange)
                    }

                    HStack {
                        Text("收錄 GM 開局與陷阱定式")
                        Spacer()
                        Text("\(pack.bookPositionCount) 個局面")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }

                    ForEach(pack.botGuides) { guide in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("\(guide.name) (Elo \(guide.rating))")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                Spacer()
                                Text(guide.style)
                                    .font(.caption2)
                                    .foregroundColor(.cyan)
                            }
                            Text("弱點：\(guide.weakness)")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("反制：\(guide.counterTip)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Label("10MB 離線大師引擎包 & Bot 弱點百科", systemImage: "shippingbox.fill")
                }

                Section("當前 FEN 資訊") {
                    Text(viewModel.boardState.toFEN())
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                    Button("複製 FEN") {
                        viewModel.copyCurrentFEN()
                    }
                }
            }
            .navigationTitle("引擎與輔助設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("套用並重新分析") {
                        viewModel.triggerAnalysis()
                        dismiss()
                    }
                    .bold()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
