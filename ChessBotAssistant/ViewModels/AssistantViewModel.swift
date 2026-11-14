import AVFoundation
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
    @Published var lastRecognizedCropImage: UIImage?
    @Published var scanCount: Int = 0
    @Published var lastSyncTimestamp: Date?
    @Published var isFairPlaySafetyLocked: Bool = false
    @Published var safetyLockReason: String?

    // 自動陣營識別、戰術雷達、語音播報與勝率走勢
    @Published var campDetectionMode: CampDetectionMode = .auto
    @Published var alwaysAnalyzeMyCampTurn: Bool = true
    @Published var detectedCampReason: String = "自動偵測：等待掃描"
    @Published var voiceAnnounceEnabled: Bool = false
    @Published var tacticalRadar: TacticalRadarReport = ChessBoardState.startingPosition.buildTacticalRadar(for: .white, moveHistorySAN: [])
    @Published var evalHistoryWhitePct: [Double] = [50.0]
    @Published var lastMoveQualityBadge: String? = nil

    @Published var showEngineSettingsSheet: Bool = false
    @Published var showScreenshotScannerSheet: Bool = false
    @Published var showBoardEditorSheet: Bool = false
    @Published var showFENInputAlert: Bool = false
    @Published var fenInputText: String = ""

    var engineService = ChessEngineService()
    var screenshotMonitor = PhotoLibraryScreenshotMonitor()
    var broadcastService = LiveScreenBroadcastService()
    var pipManager = PiPOverlayManager()

    private var cancellables = Set<AnyCancellable>()
    private var hasShownBroadcastSyncBanner: Bool = false
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastSpokenFEN: String?
    private var lastEvaluatedFEN: String?
    private var previousCampWinPct: Double?

    init() {
        setupBindings()
        triggerAnalysis()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let ok = await self.screenshotMonitor.requestPermissionAndStart()
            if ok {
                self.pipManager.startSilentAudioKeepAlive()
                self.syncPiPContent()
            }
        }
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

        broadcastService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        engineService.$currentAnalysis
            .receive(on: DispatchQueue.main)
            .sink { [weak self] analysis in
                guard let self else { return }
                if let analysis {
                    self.recordAnalysisTelemetry(analysis)
                    self.speakMoveAnnouncementIfNeeded(analysis)
                }
                self.syncPiPContent()
            }
            .store(in: &cancellables)

        engineService.$playStyleMode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if !self.engineService.reapplyPlayStyle(for: self.boardState) {
                    self.triggerAnalysis()
                }
            }
            .store(in: &cancellables)

        engineService.$showOpponentReplyArrow
            .dropFirst()
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
            guard let self else { return false }
            return await self.processScreenshotImage(image, isFromBackgroundMonitor: true)
        }

        broadcastService.$isBroadcastActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                if !active {
                    self?.hasShownBroadcastSyncBanner = false
                }
                self?.syncPiPContent()
            }
            .store(in: &cancellables)

        broadcastService.onPayloadReceived = { [weak self] payload in
            Task { @MainActor [weak self] in
                self?.handleBroadcastPayload(payload)
            }
        }

        pipManager.onHeartbeatTick = { [weak self] in
            self?.screenshotMonitor.checkForRecentScreenshotNow()
        }

        pipManager.onPiPPlayPauseTapped = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.forceScanFromPiP()
            }
        }

        pipManager.onPiPSkipForwardTapped = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handlePiPSkipForward()
            }
        }

        pipManager.onPiPSkipBackwardTapped = { [weak self] in
            self?.handlePiPSkipBackward()
        }

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.screenshotMonitor.checkForRecentScreenshotNow()
            }
            .store(in: &cancellables)
    }

    func syncPiPContent() {
        let radar = boardState.buildTacticalRadar(for: perspective, moveHistorySAN: moveHistorySAN)
        tacticalRadar = radar
        pipManager.updateContent(
            board: boardState,
            analysis: engineService.currentAnalysis,
            perspective: perspective,
            autoHintEnabled: engineService.autoHintEnabled,
            autoSyncActive: screenshotMonitor.isMonitoring || broadcastService.isBroadcastActive,
            coachPieceOnlyMode: engineService.coachPieceOnlyHintMode,
            isSafetyLocked: isFairPlaySafetyLocked,
            zeroNetworkMode: engineService.zeroNetworkIsolationMode,
            showOpponentReplyArrow: engineService.showOpponentReplyArrow,
            campReason: detectedCampReason,
            openingName: radar.openingName,
            thinkRange: radar.recommendedThinkRange,
            hangingCount: radar.hangingFriendlySquares.count
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
        evalHistoryWhitePct = [50.0]
        lastMoveQualityBadge = nil
        lastEvaluatedFEN = nil
        previousCampWinPct = nil
        lastSpokenFEN = nil
        clearSelection()
        showBanner("已重置為標準開局")
        triggerAnalysis()
    }

    func flipPerspective() {
        perspective = perspective.opposite
        campDetectionMode = perspective == .white ? .forceWhite : .forceBlack
        detectedCampReason = "手動切換：\(perspective.displayName)"
        previousCampWinPct = nil
        lastMoveQualityBadge = nil
        if alwaysAnalyzeMyCampTurn {
            boardState.sideToMove = perspective
            boardState.enPassantTarget = nil
        }
        syncPiPContent()
        if alwaysAnalyzeMyCampTurn {
            triggerAnalysis()
        }
    }

    func cycleCampDetectionMode() {
        switch campDetectionMode {
        case .auto: setCampDetectionMode(.forceWhite)
        case .forceWhite: setCampDetectionMode(.forceBlack)
        case .forceBlack: setCampDetectionMode(.auto)
        }
    }

    func setCampDetectionMode(_ mode: CampDetectionMode) {
        campDetectionMode = mode
        switch mode {
        case .auto:
            if let lastScan = lastScanResult {
                perspective = lastScan.detectedPerspective
                detectedCampReason = lastScan.campDetectionReason
            } else {
                detectedCampReason = "自動偵測：等待掃描"
            }
        case .forceWhite:
            perspective = .white
            detectedCampReason = "手動鎖定：固定我執白"
        case .forceBlack:
            perspective = .black
            detectedCampReason = "手動鎖定：固定我執黑"
        }
        previousCampWinPct = nil
        lastMoveQualityBadge = nil
        if mode == .auto, let lastImg = lastScannedFullImage {
            Task { [weak self] in
                await self?.processScreenshotImage(lastImg, isFromBackgroundMonitor: false)
            }
            showBanner("陣營模式：\(mode.displayName)")
            return
        }
        if alwaysAnalyzeMyCampTurn {
            boardState.sideToMove = perspective
            boardState.enPassantTarget = nil
        }
        showBanner("陣營模式：\(mode.displayName)")
        triggerAnalysis()
    }

    func toggleAlwaysAnalyzeMyCampTurn() {
        alwaysAnalyzeMyCampTurn.toggle()
        if alwaysAnalyzeMyCampTurn && boardState.sideToMove != perspective {
            boardState.sideToMove = perspective
            boardState.enPassantTarget = nil
            triggerAnalysis()
        } else {
            syncPiPContent()
        }
        showBanner(alwaysAnalyzeMyCampTurn ? "已鎖定：掃描後永遠分析我方回合" : "已關閉：保留原始輪次設定")
    }

    func cyclePlayStyleMode() {
        let all = PlayStyleMode.allCases
        if let idx = all.firstIndex(of: engineService.playStyleMode) {
            engineService.playStyleMode = all[(idx + 1) % all.count]
        } else {
            engineService.playStyleMode = .engineBest
        }
        showBanner("棋風切換：\(engineService.playStyleMode.displayName)")
    }

    private func recordAnalysisTelemetry(_ analysis: EngineAnalysisResult) {
        guard analysis.fen != lastEvaluatedFEN, let primary = analysis.primaryLine else { return }
        lastEvaluatedFEN = analysis.fen
        let whitePct = primary.winProbabilityWhite
        evalHistoryWhitePct.append(whitePct)
        if evalHistoryWhitePct.count > 24 {
            evalHistoryWhitePct.removeFirst(evalHistoryWhitePct.count - 24)
        }

        let currentCampPct = primary.winProbability(for: perspective)
        if let prevPct = previousCampWinPct {
            let delta = currentCampPct - prevPct
            if delta >= 3.0 {
                lastMoveQualityBadge = "💎 妙手 (+\(Int(delta.rounded()))%)"
            } else if delta >= -1.5 {
                lastMoveQualityBadge = "✅ 最佳"
            } else if delta >= -5.0 {
                lastMoveQualityBadge = "👍 不錯"
            } else if delta >= -12.0 {
                lastMoveQualityBadge = "⚠️ 不精確 (\(Int(delta.rounded()))%)"
            } else {
                lastMoveQualityBadge = "❌ 失誤 (\(Int(delta.rounded()))%)"
            }
        }
        previousCampWinPct = currentCampPct
    }

    private func speakMoveAnnouncementIfNeeded(_ analysis: EngineAnalysisResult) {
        guard voiceAnnounceEnabled else { return }
        guard analysis.fen != lastSpokenFEN, let bestMove = analysis.primaryLine?.bestMove else { return }
        lastSpokenFEN = analysis.fen

        let pieceText: String
        let san = bestMove.san
        if san == "O-O" {
            pieceText = "短易位"
        } else if san == "O-O-O" {
            pieceText = "長易位"
        } else {
            let roleName: String
            switch san.first {
            case "K": roleName = "國王"
            case "Q": roleName = "皇后"
            case "R": roleName = "城堡"
            case "B": roleName = "主教"
            case "N": roleName = "騎士"
            default: roleName = ""
            }
            let prefix = roleName.isEmpty ? "" : "\(roleName) "
            pieceText = "\(prefix)\(bestMove.from.algebraic) 到 \(bestMove.to.algebraic)"
        }

        let campName = perspective == .white ? "我方白棋" : "我方黑棋"
        let text = "\(campName)，推薦 \(pieceText)"

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-TW")
        utterance.rate = 0.52
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        speechSynthesizer.speak(utterance)
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
            if !pipManager.isPiPActive {
                pipManager.stopSilentAudioKeepAlive()
            }
            showBanner("已暫停背景截圖自動同步")
            syncPiPContent()
        } else {
            Task {
                let ok = await screenshotMonitor.requestPermissionAndStart()
                if ok {
                    pipManager.startSilentAudioKeepAlive()
                    showBanner("已開啟截圖自動同步！在 Chess.com 截圖即可更新")
                } else {
                    showBanner("需要「相簿讀取」權限才能自動偵測截圖")
                }
                syncPiPContent()
            }
        }
    }

    func togglePiPWithAutoSync() {
        if !pipManager.isPiPActive {
            Task {
                if !screenshotMonitor.isMonitoring {
                    _ = await screenshotMonitor.requestPermissionAndStart()
                }
                pipManager.startSilentAudioKeepAlive()
                syncPiPContent()
                pipManager.togglePiP()
            }
        } else {
            pipManager.togglePiP()
            syncPiPContent()
        }
    }

    private func handleBroadcastPayload(_ payload: LiveBroadcastPayload) {
        guard let parsedBoard = ChessBoardState(fen: payload.fen) else { return }
        let newPerspective: PieceColor
        switch campDetectionMode {
        case .auto:
            newPerspective = PieceColor(rawValue: payload.perspective) ?? perspective
            if let reason = payload.campDetectionReason, !reason.isEmpty {
                detectedCampReason = reason
            } else {
                detectedCampReason = "實時同步：\(newPerspective == .white ? "白方在下方" : "黑方在下方")"
            }
        case .forceWhite:
            newPerspective = .white
            detectedCampReason = "手動鎖定：固定我執白"
        case .forceBlack:
            newPerspective = .black
            detectedCampReason = "手動鎖定：固定我執黑"
        }

        var adjustedBoard = parsedBoard
        if alwaysAnalyzeMyCampTurn && adjustedBoard.sideToMove != newPerspective {
            adjustedBoard.sideToMove = newPerspective
            adjustedBoard.enPassantTarget = nil
        }

        let boardChanged = adjustedBoard.squares != boardState.squares || adjustedBoard.sideToMove != boardState.sideToMove
        let perspChanged = newPerspective != perspective

        lastSyncTimestamp = Date()
        scanCount += 1

        if !hasShownBroadcastSyncBanner {
            hasShownBroadcastSyncBanner = true
            pipManager.showPiPBanner("✅ 實時畫面同步中")
        }

        guard boardChanged || perspChanged else { return }

        if boardChanged {
            history.append(boardState)
            boardState = adjustedBoard
            lastMove = nil
            clearSelection()
        }
        perspective = newPerspective
        isFairPlaySafetyLocked = false
        safetyLockReason = nil
        triggerAnalysis()
    }

    func forceScanFromPiP() async {
        pipManager.showPiPBanner("🔄 掃描最新截圖...")
        if let image = await screenshotMonitor.forceFetchNewestImageIgnoringCache() {
            let ok = await processScreenshotImage(image, isFromBackgroundMonitor: true)
            pipManager.showPiPBanner(ok ? "✅ 已同步" : "⚠️ 未偵測到棋盤")
            return
        }
        if let clipImg = UIPasteboard.general.image {
            let ok = await processScreenshotImage(clipImg, isFromBackgroundMonitor: true)
            pipManager.showPiPBanner(ok ? "✅ 已同步剪貼簿" : "⚠️ 無新截圖")
            return
        }
        pipManager.showPiPBanner("⚠️ 無新截圖")
    }

    func handlePiPSkipForward() async {
        if screenshotMonitor.isMonitoring {
            let beforeCount = scanCount
            screenshotMonitor.checkForRecentScreenshotNow()
            try? await Task.sleep(nanoseconds: 250_000_000)
            if scanCount > beforeCount {
                pipManager.showPiPBanner("✅ 已掃描最新畫面")
                return
            }
        }

        guard !isFairPlaySafetyLocked else {
            pipManager.showPiPBanner("🔒 安全鎖定中")
            return
        }
        guard let best = engineService.currentAnalysis?.primaryLine?.bestMove else {
            pipManager.showPiPBanner("⚠️ 無可用最佳步")
            return
        }
        let moveLabel = best.san.isEmpty ? best.coordinateDisplay : best.san
        applyMove(best)
        pipManager.showPiPBanner("⏩ 已走 \(moveLabel)")
    }

    func handlePiPSkipBackward() {
        undoLastMove()
        pipManager.showPiPBanner("↩️ 已退回一步")
    }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "chessbot" else { return }
        let hostOrPath = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        guard hostOrPath.isEmpty || hostOrPath == "scan" else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.screenshotMonitor.isMonitoring {
                _ = await self.screenshotMonitor.requestPermissionAndStart()
            }
            self.pipManager.startSilentAudioKeepAlive()
            if !self.pipManager.isPiPActive {
                self.pipManager.startPiPIfNeeded()
            }

            if let latest = await self.screenshotMonitor.forceFetchNewestImageIgnoringCache(),
               await self.processScreenshotImage(latest, isFromBackgroundMonitor: false) {
                self.pipManager.showPiPBanner("✅ 已由捷徑掃描同步")
                return
            }

            if let clipImg = UIPasteboard.general.image,
               await self.processScreenshotImage(clipImg, isFromBackgroundMonitor: false) {
                self.pipManager.showPiPBanner("✅ 已由剪貼簿掃描")
                return
            }

            self.pipManager.showPiPBanner("⚠️ 無可掃描截圖")
            self.showBanner("找不到相簿截圖或剪貼簿圖片")
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

    @discardableResult
    func processScreenshotImage(_ image: UIImage, isFromBackgroundMonitor: Bool) async -> Bool {
        isScanningScreenshot = true
        lastScannedFullImage = image
        let fallbackPerspective = perspective
        let prevBoard = boardState
        let forcedPersp: PieceColor?
        switch campDetectionMode {
        case .auto: forcedPersp = nil
        case .forceWhite: forcedPersp = .white
        case .forceBlack: forcedPersp = .black
        }
        let forcedSide: PieceColor? = alwaysAnalyzeMyCampTurn ? forcedPersp : nil
        let checkHumanMatch = engineService.humanMatchSafetyLockEnabled
        let result = await Task.detached(priority: .userInitiated) {
            await ScreenshotBoardRecognizer.shared.recognizeBoard(
                from: image,
                fallbackPerspective: fallbackPerspective,
                sideToMove: forcedSide,
                previousBoard: prevBoard,
                forcedPerspective: forcedPersp,
                checkHumanTimedMatch: checkHumanMatch
            )
        }.value

        isScanningScreenshot = false

        guard let result else {
            if !isFromBackgroundMonitor {
                showBanner("未在圖片中偵測到 Chess.com 棋盤")
            }
            return false
        }

        lastScanResult = result
        if let pngData = result.croppedBoardPNGData {
            lastRecognizedCropImage = UIImage(data: pngData)
        }
        scanCount += 1
        lastSyncTimestamp = Date()

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
        return true
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

        let resolvedCamp: PieceColor
        switch campDetectionMode {
        case .auto:
            resolvedCamp = result.detectedPerspective
            detectedCampReason = result.campDetectionReason
        case .forceWhite:
            resolvedCamp = .white
            detectedCampReason = "手動鎖定：固定我執白"
        case .forceBlack:
            resolvedCamp = .black
            detectedCampReason = "手動鎖定：固定我執黑"
        }

        if alwaysAnalyzeMyCampTurn {
            newBoard.sideToMove = resolvedCamp
            newBoard.enPassantTarget = nil
        }

        let isIdentical = newBoard.squares == boardState.squares
            && newBoard.sideToMove == boardState.sideToMove
            && resolvedCamp == perspective
        if keepSideToMoveIfSameBoard && isIdentical && engineService.currentAnalysis != nil {
            syncPiPContent()
            return
        }

        history.append(boardState)
        boardState = newBoard
        perspective = resolvedCamp
        lastMove = nil
        clearSelection()
        if isFairPlaySafetyLocked {
            showBanner("⚠️ \(result.detectedMatchContextNote)")
        } else {
            showBanner("截圖辨識完成（\(detectedCampReason)）")
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
