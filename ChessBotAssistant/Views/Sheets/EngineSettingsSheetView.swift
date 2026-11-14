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
                Section("🛡️ 防誤封與隱私安全防護") {
                    Toggle("🔒 100% 純本機零連網隔離模式", isOn: $engineService.zeroNetworkIsolationMode)
                        .tint(Color(red: 0.50, green: 0.78, blue: 0.35))

                    Text("開啟時所有分析皆於本機完成，不發送任何棋局至外部伺服器（無網路請求足跡）。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("🛡️ 偵測到真人計時局自動鎖定提示", isOn: $engineService.humanMatchSafetyLockEnabled)
                        .tint(.cyan)

                    Text("辨識截圖時若發現倒數計時器且無 Bot/電腦標記，自動隱藏箭頭與走法防止誤封。")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("🎓 教練半提示模式（僅高亮起點格、不畫終點箭頭）", isOn: $engineService.coachPieceOnlyHintMode)
                        .tint(.orange)

                    Button(role: .destructive) {
                        viewModel.deleteLastScreenshot()
                    } label: {
                        Label("🧹 刪除最近一張辨識截圖", systemImage: "trash")
                    }
                    .disabled(!viewModel.screenshotMonitor.hasDeletableScreenshot)
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
