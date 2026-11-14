import Combine
import Foundation
import SwiftUI
import UIKit

@MainActor
final class AssistantViewModel: ObservableObject {
    @Published var boardState: ChessBoardState = .startingPosition
    @Published var history: [ChessBoardState] = []
    @Published var moveHistorySAN: [String] = []
    @Published var lastMove: ChessMove?

    @Published var perspective: PieceColor = .white
    @Published var selectedSquare: BoardSquare?
    @Published var legalTargetsForSelection: [ChessMove] = []
    @Published var pendingPromotionPair: (from: BoardSquare, to: BoardSquare)?

    @Published var statusBanner: String?
    @Published var isScanningScreenshot: Bool = false
    @Published var lastScanResult: RecognizedBoardResult?
    @Published var lastScannedFullImage: UIImage?
    @Published var isFairPlaySafetyLocked: Bool = false
    @Published var safetyLockReason: String?

    @Published var showEngineSettingsSheet: Bool = false
    @Published var showScreenshotScannerSheet: Bool = false
    @Published var showBoardEditorSheet: Bool = false
    @Published var showFENInputAlert: Bool = false
    @Published var fenInputText: String = ""

    var engineService = ChessEngineService()
    var screenshotMonitor = PhotoLibraryScreenshotMonitor()
    var pipManager = PiPOverlayManager()

    private var cancellables = Set<AnyCancellable>()

    init() {
        setupBindings()
        triggerAnalysis()
    }

    private func setupBindings() {
        engineService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        screenshotMonitor.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        pipManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        engineService.$currentAnalysis
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncPiPContent()
            }
            .store(in: &cancellables)

        engineService.$autoHintEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncPiPContent()
            }
            .store(in: &cancellables)

        engineService.$coachPieceOnlyHintMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncPiPContent()
            }
            .store(in: &cancellables)

        engineService.$zeroNetworkIsolationMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncPiPContent()
            }
            .store(in: &cancellables)

        engineService.$humanMatchSafetyLockEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled {
                    self?.isFairPlaySafetyLocked = false
                    self?.safetyLockReason = nil
                }
                self?.syncPiPContent()
            }
            .store(in: &cancellables)

        screenshotMonitor.onNewScreenshot = { [weak self] image in
            Task { @MainActor [weak self] in
                await self?.processScreenshotImage(image, isFromBackgroundMonitor: true)
            }
        }
    }

    func syncPiPContent() {
        pipManager.updateContent(
            board: boardState,
            analysis: engineService.currentAnalysis,
            perspective: perspective,
            autoHintEnabled: engineService.autoHintEnabled,
            autoSyncActive: screenshotMonitor.isMonitoring,
            coachPieceOnlyMode: engineService.coachPieceOnlyHintMode,
            isSafetyLocked: isFairPlaySafetyLocked,
            zeroNetworkMode: engineService.zeroNetworkIsolationMode
        )
    }

    func triggerAnalysis() {
        syncPiPContent()
        engineService.analyze(board: boardState)
    }

    // MARK: - Board Interaction

    func tapSquare(_ square: BoardSquare) {
        if let selected = selectedSquare {
            if selected == square {
                clearSelection()
                return
            }

            let matchingMoves = legalTargetsForSelection.filter { $0.to == square }
            if let firstMatch = matchingMoves.first {
                if matchingMoves.count > 1 && firstMatch.promotion != nil {
                    pendingPromotionPair = (selected, square)
                } else {
                    applyMove(firstMatch)
                }
                return
            }
        }

        if let piece = boardState.piece(at: square), piece.color == boardState.sideToMove {
            selectedSquare = square
            legalTargetsForSelection = boardState.legalMoves().filter { $0.from == square }
        } else {
            clearSelection()
        }
    }

    func completePendingPromotion(with pieceType: PieceType) {
        guard let pair = pendingPromotionPair else { return }
        pendingPromotionPair = nil
        let moves = boardState.legalMoves()
        if let move = moves.first(where: { $0.from == pair.from && $0.to == pair.to && $0.promotion == pieceType }) {
            applyMove(move)
        }
    }

    func clearSelection() {
        selectedSquare = nil
        legalTargetsForSelection = []
    }

    func applyMove(_ move: ChessMove) {
        history.append(boardState)
        let san = move.san.isEmpty ? boardState.formatSAN(for: move) : move.san
        moveHistorySAN.append(san)
        boardState = boardState.applying(move)
        lastMove = move
        clearSelection()
        triggerAnalysis()
    }

    func playBestMove() {
        guard !isFairPlaySafetyLocked else {
            showBanner("安全鎖定中，請先確認為 Bot 對局再使用提示")
            return
        }
        guard let best = engineService.currentAnalysis?.primaryLine?.bestMove else {
            showBanner("目前沒有可走的最佳步")
            return
        }
        applyMove(best)
    }

    func playPVLine(_ line: PVLine) {
        applyMove(line.bestMove)
    }

    func undoLastMove() {
        guard let previous = history.popLast() else {
            showBanner("已經回到初始步數")
            return
        }
        if !moveHistorySAN.isEmpty {
            moveHistorySAN.removeLast()
        }
        boardState = previous
        lastMove = nil
        clearSelection()
        triggerAnalysis()
    }

    func resetBoard() {
        history.removeAll()
        moveHistorySAN.removeAll()
        boardState = .startingPosition
        lastMove = nil
        isFairPlaySafetyLocked = false
        safetyLockReason = nil
        clearSelection()
        showBanner("已重置為標準開局")
        triggerAnalysis()
    }

    func flipPerspective() {
        perspective = perspective.opposite
        syncPiPContent()
    }

    func toggleSideToMove() {
        history.append(boardState)
        boardState.sideToMove = boardState.sideToMove.opposite
        boardState.enPassantTarget = nil
        clearSelection()
        showBanner("目前輪到：\(boardState.sideToMove.displayName)")
        triggerAnalysis()
    }

    // MARK: - FEN / PGN Import & Export

    func copyCurrentFEN() {
        UIPasteboard.general.string = boardState.toFEN()
        showBanner("已複製當前 FEN 至剪貼簿")
    }

    func pasteFENOrPGNFromClipboard() {
        guard let text = UIPasteboard.general.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showFENInputAlert = true
            return
        }
        if !importPositionText(text) {
            fenInputText = text
            showFENInputAlert = true
        }
    }

    @discardableResult
    func importPositionText(_ text: String) -> Bool {
        guard let parsed = ChessBoardState.parseFromInput(text) else {
            showBanner("無法解析 FEN 或 PGN 格式")
            return false
        }
        history = parsed.history
        moveHistorySAN = parsed.moveSANs
        boardState = parsed.state
        lastMove = nil
        clearSelection()
        showBanner("已成功載入局面（輪到\(boardState.sideToMove.displayName)）")
        triggerAnalysis()
        return true
    }

    func applyCustomBoard(_ editedBoard: ChessBoardState) {
        history.append(boardState)
        boardState = editedBoard
        lastMove = nil
        clearSelection()
        showBanner("已套用自訂棋盤局面")
        triggerAnalysis()
    }

    // MARK: - Screenshot Sync & Scanning

    func toggleAutoScreenshotSync() {
        if screenshotMonitor.isMonitoring {
            screenshotMonitor.stopMonitoring()
            showBanner("已暫停背景截圖自動同步")
            syncPiPContent()
        } else {
            Task {
                let ok = await screenshotMonitor.requestPermissionAndStart()
                if ok {
                    showBanner("已開啟截圖自動同步！在 Chess.com 截圖即可更新")
                } else {
                    showBanner("需要「相簿讀取」權限才能自動偵測截圖")
                }
                syncPiPContent()
            }
        }
    }

    func scanLatestScreenshot() {
        Task {
            isScanningScreenshot = true
            defer { isScanningScreenshot = false }
            guard let image = await screenshotMonitor.fetchLatestScreenshot() else {
                showBanner("找不到相簿截圖或未授權存取相簿")
                return
            }
            await processScreenshotImage(image, isFromBackgroundMonitor: false)
        }
    }

    func processScreenshotImage(_ image: UIImage, isFromBackgroundMonitor: Bool) async {
        isScanningScreenshot = true
        lastScannedFullImage = image
        let fallbackPerspective = perspective
        let result = await Task.detached(priority: .userInitiated) {
            await ScreenshotBoardRecognizer.shared.recognizeBoard(
                from: image,
                fallbackPerspective: fallbackPerspective,
                sideToMove: nil
            )
        }.value

        isScanningScreenshot = false

        guard let result else {
            if !isFromBackgroundMonitor {
                showBanner("未在圖片中偵測到 Chess.com 棋盤")
            }
            return
        }

        lastScanResult = result

        if engineService.humanMatchSafetyLockEnabled && result.isLikelyHumanTimedGame && !result.isConfirmedBotMatch {
            isFairPlaySafetyLocked = true
            safetyLockReason = result.detectedMatchContextNote
        } else {
            isFairPlaySafetyLocked = false
            safetyLockReason = nil
        }

        if isFromBackgroundMonitor {
            // Auto-apply directly when triggered from background screenshot while in Chess.com
            applyRecognizedBoard(result, keepSideToMoveIfSameBoard: true)
        } else {
            applyRecognizedBoard(result, keepSideToMoveIfSameBoard: false)
        }
    }

    func unlockSafetyLockForBotMatch() {
        isFairPlaySafetyLocked = false
        safetyLockReason = nil
        showBanner("已確認為 Bot 練習對局，恢復顯示輔助提示")
        syncPiPContent()
    }

    func deleteLastScreenshot() {
        Task {
            let deleted = await screenshotMonitor.deleteLastDetectedScreenshot()
            if deleted {
                showBanner("🧹 已從相簿刪除最近一張暫存截圖")
            } else {
                showBanner("沒有可刪除的暫存截圖或使用者取消了刪除")
            }
        }
    }

    func applyRecognizedBoard(_ result: RecognizedBoardResult, keepSideToMoveIfSameBoard: Bool = false) {
        var newBoard = result.boardState
        if keepSideToMoveIfSameBoard {
            // Default to the player's own perspective side so the assistant immediately advises the user's move
            newBoard.sideToMove = result.detectedPerspective
        } else {
            newBoard.sideToMove = perspective
        }
        history.append(boardState)
        boardState = newBoard
        perspective = result.detectedPerspective
        lastMove = nil
        clearSelection()
        if isFairPlaySafetyLocked {
            showBanner("⚠️ \(result.detectedMatchContextNote)")
        } else {
            showBanner("截圖辨識完成：\(result.notes)")
        }
        triggerAnalysis()
    }

    func showBanner(_ message: String) {
        statusBanner = message
        Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if self.statusBanner == message {
                self.statusBanner = nil
            }
        }
    }
}
