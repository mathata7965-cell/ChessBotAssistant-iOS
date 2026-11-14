import SwiftUI

struct EngineSettingsSheetView: View {
    @ObservedObject var viewModel: AssistantViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("引擎思考設定") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("思考深度 (Depth)")
                            Spacer()
                            Text("Depth \(viewModel.engineService.targetDepth)")
                                .font(.system(.body, design: .monospaced).bold())
                                .foregroundColor(Color(red: 0.50, green: 0.78, blue: 0.35))
                        }
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.engineService.targetDepth) },
                                set: { viewModel.engineService.targetDepth = Int($0.rounded()) }
                            ),
                            in: 4...18,
                            step: 1
                        )
                        .tint(Color(red: 0.50, green: 0.78, blue: 0.35))
                        Text("深度越高分析越精準（雲端 Stockfish NNUE 最高支援 D15+，離線本機為 D5 快速運算）。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Picker("候選走法數量 (Multi-PV)", selection: $viewModel.engineService.multiPVCount) {
                        Text("1 條 (最佳步)").tag(1)
                        Text("2 條推薦").tag(2)
                        Text("3 條推薦").tag(3)
                    }

                    Toggle("自動顯示最佳走法箭頭", isOn: $viewModel.engineService.autoHintEnabled)
                        .tint(Color(red: 0.50, green: 0.78, blue: 0.35))

                    Toggle("優先使用雲端 Stockfish 16 NNUE", isOn: $viewModel.engineService.useCloudStockfish)
                        .tint(Color(red: 0.50, green: 0.78, blue: 0.35))
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
