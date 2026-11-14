import PhotosUI
import SwiftUI

struct ScreenshotScannerSheetView: View {
    @ObservedObject var viewModel: AssistantViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var previewBoard: ChessBoardState?
    @State private var croppedPreviewImage: UIImage?
    @State private var detectedPerspective: PieceColor = .white
    @State private var selectedTurn: PieceColor = .white
    @State private var scanNotes: String = "請選擇或讀取 Chess.com 對局截圖"
    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 10) {
                        Button {
                            Task {
                                await loadLatestFromPhotos()
                            }
                        } label: {
                            Label("讀取最新截圖", systemImage: "bolt.circle.fill")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(red: 0.50, green: 0.72, blue: 0.30))
                                .foregroundColor(Color(red: 0.06, green: 0.10, blue: 0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label("從相簿挑選", systemImage: "photo.on.rectangle")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.12))
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    if isProcessing {
                        ProgressView("正在辨識棋盤與棋子...")
                            .padding(.vertical, 28)
                    } else if let board = previewBoard {
                        VStack(spacing: 12) {
                            HStack {
                                Text(scanNotes)
                                    .font(.caption.bold())
                                    .foregroundColor(Color(red: 0.52, green: 0.88, blue: 0.48))
                                Spacer()
                            }

                            HStack(spacing: 12) {
                                if let croppedPreviewImage {
                                    VStack(spacing: 4) {
                                        Text("截圖擷取區")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Image(uiImage: croppedPreviewImage)
                                            .resizable()
                                            .scaledToFit()
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .frame(maxWidth: .infinity)
                                }

                                VStack(spacing: 4) {
                                    Text("辨識結果")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    InteractiveChessBoardView(
                                        boardState: board,
                                        perspective: detectedPerspective,
                                        selectedSquare: nil,
                                        legalTargets: [],
                                        lastMove: nil,
                                        pvLines: [],
                                        showAutoHintArrows: false,
                                        highlightedPVIndex: nil,
                                        onTapSquare: { _ in }
                                    )
                                }
                                .frame(maxWidth: .infinity)
                            }

                            Picker("目前輪到誰走？", selection: $selectedTurn) {
                                Text("輪到白方").tag(PieceColor.white)
                                Text("輪到黑方").tag(PieceColor.black)
                            }
                            .pickerStyle(.segmented)

                            HStack(spacing: 10) {
                                Button {
                                    var updated = board
                                    updated.sideToMove = selectedTurn
                                    viewModel.boardState = updated
                                    viewModel.perspective = detectedPerspective
                                    viewModel.history.append(board)
                                    viewModel.clearSelection()
                                    viewModel.triggerAnalysis()
                                    viewModel.showBanner("已套用截圖棋盤並開始分析")
                                    dismiss()
                                } label: {
                                    Text("套用到主分析棋盤")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color(red: 0.50, green: 0.72, blue: 0.30))
                                        .foregroundColor(Color(red: 0.06, green: 0.10, blue: 0.05))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }

                                Button {
                                    var updated = board
                                    updated.sideToMove = selectedTurn
                                    viewModel.boardState = updated
                                    viewModel.perspective = detectedPerspective
                                    dismiss()
                                    viewModel.showBoardEditorSheet = true
                                } label: {
                                    Text("微調棋子")
                                        .font(.subheadline.bold())
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .background(Color.white.opacity(0.12))
                                        .foregroundColor(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "viewfinder")
                                .font(.system(size: 44))
                                .foregroundColor(.secondary)
                            Text(scanNotes)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 40)
                    }
                }
                .padding()
            }
            .navigationTitle("Chess.com 截圖辨識")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") { dismiss() }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        await runRecognition(on: uiImage)
                    }
                }
            }
            .onAppear {
                if let last = viewModel.lastScanResult {
                    previewBoard = last.boardState
                    detectedPerspective = last.detectedPerspective
                    selectedTurn = last.detectedPerspective
                    scanNotes = last.notes
                    if let png = last.croppedBoardPNGData {
                        croppedPreviewImage = UIImage(data: png)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func loadLatestFromPhotos() async {
        isProcessing = true
        guard let img = await viewModel.screenshotMonitor.fetchLatestScreenshot() else {
            isProcessing = false
            scanNotes = "找不到最新截圖或尚未允許存取相簿"
            return
        }
        await runRecognition(on: img)
    }

    private func runRecognition(on image: UIImage) async {
        isProcessing = true
        let fallback = viewModel.perspective
        let result = await Task.detached(priority: .userInitiated) {
            await ScreenshotBoardRecognizer.shared.recognizeBoard(
                from: image,
                fallbackPerspective: fallback,
                sideToMove: nil
            )
        }.value

        isProcessing = false
        guard let result else {
            scanNotes = "未能識別圖片中的棋盤，請確認包含完整的 8×8 棋盤"
            return
        }
        previewBoard = result.boardState
        detectedPerspective = result.detectedPerspective
        selectedTurn = result.detectedPerspective
        scanNotes = result.notes
        if let png = result.croppedBoardPNGData {
            croppedPreviewImage = UIImage(data: png)
        }
    }
}
