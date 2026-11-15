import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit
import UserNotifications

final class TacticalBannerNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TacticalBannerNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}

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
    @Published var boardTheme: BoardTheme = .glacierBlue
    @Published var moveAccuracyScores: [Double] = []
    @Published var isBoardDetected: Bool = false
    @Published var bigScreenBannerPromptEnabled: Bool = true
    @Published var pipBigScreenBoardMode: Bool = false
    @Published var showFullScreenBigBoard: Bool = false
    @Published var lastKnownWinPct: Int = 50
    @Published var lastKnownWDL: (win: Int, draw: Int, loss: Int) = (38, 24, 38)
    @Published var lastKnownEvalStr: String = "0.00"
    @Published var isWaitingForOpponentReply: Bool = false
    @Published var paceRecommendedSeconds: Int = 3
    @Published var paceElapsedSeconds: Int = 0

    var paceRemainingSeconds: Int {
        max(0, paceRecommendedSeconds - paceElapsedSeconds)
    }

    var stealthSafetyScore: Int {
        var score = 76
        if engineService.humanMatchSafetyLockEnabled { score += 7 }
        if engineService.zeroNetworkIsolationMode { score += 6 }
        if engineService.playStyleMode == .humanSafe {
            score += 5
        } else if engineService.playStyleMode == .defensive {
            score += 2
        }
        if engineService.coachPieceOnlyHintMode { score += 3 }
        if alwaysAnalyzeMyCampTurn { score += 2 }
        return min(99, max(75, score))
    }

    var stealthProtectionBadges: [String] {
        var tags: [String] = []
        if engineService.humanMatchSafetyLockEnabled { tags.append("計時賽保護") }
        if engineService.zeroNetworkIsolationMode { tags.append("零連網隔離") }
        if engineService.playStyleMode == .humanSafe {
            let eloText = engineService.humanTargetElo > 0 ? "\(engineService.humanTargetElo)" : "自然"
            tags.append("擬人\(eloText)")
        }
        if engineService.coachPieceOnlyHintMode { tags.append("半提示") }
        if paceRemainingSeconds > 0 {
            tags.append("建議停頓 \(paceRemainingSeconds)s")
        } else {
            tags.append("節奏就緒")
        }
        return tags
    }

    var sessionAccuracyText: String {
        guard !moveAccuracyScores.isEmpty else {
            return "離線庫 \(OfflineEnginePack.shared.packSizeMBString)"
        }
        let avg = moveAccuracyScores.reduce(0, +) / Double(moveAccuracyScores.count)
        return "精準 \(Int(avg.rounded()))%"
    }

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
    private var lastNotifiedBannerKey: String = ""
    private var previousCampWinPct: Double?
    private var pendingBroadcastKey: String?
    private var pendingBroadcastCount: Int = 0
    private var previousAcceptedSquares: [[ChessPiece?]]?
    private var lastAcceptedMoveTime: CFTimeInterval = 0
    private var paceTimer: Timer?

    init() {
        UNUserNotificationCenter.current().delegate = TacticalBannerNotificationDelegate.shared
        requestBannerNotificationPermissionIfNeeded()
        setupBindings()
        syncPiPContent()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let ok = await self.screenshotMonitor.requestPermissionAndStart()
            if ok {
                self.pipManager.startSilentAudioKeepAlive()
                self.syncPiPContent()
            }
        }
    }

    private func requestBannerNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) { _, _ in }
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
                    self.postBigScreenTacticalBannerIfNeeded(analysis)
                }
                self.syncPiPContent()
            }
            .store(in: &cancellables)

        engineService.$playStyleMode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isBoardDetected else {
                    self.syncPiPContent()
                    return
                }
                if !self.engineService.reapplyPlayStyle(for: self.boardState) {
                    self.triggerAnalysis()
                }
            }
            .store(in: &cancellables)

        engineService.$botTargetProfile
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isBoardDetected else {
                    self.syncPiPContent()
                    return
                }
                if !self.engineService.reapplyPlayStyle(for: self.boardState) {
                    self.triggerAnalysis()
                }
            }
            .store(in: &cancellables)

        engineService.$humanTargetElo
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isBoardDetected else {
                    self.syncPiPContent()
                    return
                }
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
            lastMove: lastMove,
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
            hangingCount: radar.hangingFriendlySquares.count,
            boardTheme: boardTheme,
            isKingInCheck: radar.isKingInCheck,
            pinnedCount: radar.pinnedPieces.count,
            isWaitingForOpponentReply: isWaitingForOpponentReply,
            isBoardDetected: isBoardDetected,
            bigScreenBoardMode: pipBigScreenBoardMode,
            isAnalyzing: engineService.isAnalyzing,
            paceRemainingSeconds: paceRemainingSeconds,
            stealthSafetyScore: stealthSafetyScore,
            pinnedSummary: radar.pinnedPieces.map(\.summaryText).joined(separator: "、"),
            lastKnownWinPct: lastKnownWinPct,
            lastKnownWDL: lastKnownWDL,
            lastKnownEvalStr: lastKnownEvalStr
        )
    }

    func triggerAnalysis(preserveExcludedMoves: Bool = false) {
        guard isBoardDetected else {
            syncPiPContent()
            return
        }
        isWaitingForOpponentReply = false
        syncPiPContent()
        startPaceCountdown()
        engineService.analyze(board: boardState, preserveExcludedMoves: preserveExcludedMoves)
    }

    func forceAnalyzeNow() {
        isWaitingForOpponentReply = false
        triggerAnalysis()
    }

    func skipBlockedMoveAndReanalyze() {
        guard let bestMove = engineService.currentAnalysis?.primaryLine?.bestMove else {
            showBanner("目前無可切換的推薦步，已重新計算最佳解")
            triggerAnalysis()
            return
        }

        if bestMove.isCastling {
            if perspective == .white {
                boardState.castlingRights.whiteKingside = false
                boardState.castlingRights.whiteQueenside = false
            } else {
                boardState.castlingRights.blackKingside = false
                boardState.castlingRights.blackQueenside = false
            }
            engineService.excludedUCIMoves.insert(bestMove.uci)
            showBanner("已排除易位，改推薦可直接走動的安全步")
            triggerAnalysis(preserveExcludedMoves: true)
            return
        }

        engineService.excludedUCIMoves.insert(bestMove.uci)
        showBanner("已跳過受阻步 \(bestMove.san)，切換至最佳備選步")
        triggerAnalysis(preserveExcludedMoves: true)
    }

    private func startPaceCountdown() {
        paceTimer?.invalidate()
        let isTense = tacticalRadar.isKingInCheck || tacticalRadar.hangingFriendlySquares.count >= 2
        let pieceCount = boardState.squares.flatMap { $0 }.compactMap { $0 }.count
        if isTense {
            paceRecommendedSeconds = 5
        } else if pieceCount <= 10 {
            paceRecommendedSeconds = 4
        } else {
            paceRecommendedSeconds = 3
        }
        paceElapsedSeconds = 0

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self else {
                t.invalidate()
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.paceElapsedSeconds < self.paceRecommendedSeconds {
                    self.paceElapsedSeconds += 1
                    if self.pipManager.isPiPActive {
                        self.syncPiPContent()
                    }
                } else {
                    t.invalidate()
                    if self.paceTimer === t {
                        self.paceTimer = nil
                    }
                    if self.pipManager.isPiPActive {
                        self.syncPiPContent()
                    }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        paceTimer = timer
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
        isBoardDetected = true
        applyMove(best)
    }

    func playPVLine(_ line: PVLine) {
        isBoardDetected = true
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
        isBoardDetected = false
        isWaitingForOpponentReply = false
        isFairPlaySafetyLocked = false
        safetyLockReason = nil
        lastScanResult = nil
        lastRecognizedCropImage = nil
        detectedCampReason = "自動偵測：等待掃描"
        evalHistoryWhitePct = [50.0]
        lastKnownWinPct = 50
        lastKnownWDL = (38, 24, 38)
        lastKnownEvalStr = "0.00"
        lastMoveQualityBadge = nil
        moveAccuracyScores.removeAll()
        lastEvaluatedFEN = nil
        lastNotifiedBannerKey = ""
        previousCampWinPct = nil
        lastSpokenFEN = nil
        pendingBroadcastKey = nil
        pendingBroadcastCount = 0
        previousAcceptedSquares = nil
        lastAcceptedMoveTime = 0
        clearSelection()
        engineService.clearAnalysis()
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["chess.tactical.live.banner"])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["chess.tactical.live.banner"])
        syncPiPContent()
        showBanner("已重置並等待偵測棋盤")
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

    func cycleBotTargetProfile() {
        let all = BotTargetProfile.allCases
        if let idx = all.firstIndex(of: engineService.botTargetProfile) {
            engineService.botTargetProfile = all[(idx + 1) % all.count]
        } else {
            engineService.botTargetProfile = .universal
        }
        showBanner("Bot 克制模式：\(engineService.botTargetProfile.displayName)")
    }

    func cycleBoardTheme() {
        let all = BoardTheme.allCases
        if let idx = all.firstIndex(of: boardTheme) {
            boardTheme = all[(idx + 1) % all.count]
        } else {
            boardTheme = .glacierBlue
        }
        syncPiPContent()
        showBanner("棋盤配色：\(boardTheme.displayName)")
    }

    func copyGamePGNAndReviewReport() {
        var pgnMoves: [String] = []
        for idx in stride(from: 0, to: moveHistorySAN.count, by: 2) {
            let num = (idx / 2) + 1
            let whiteSAN = moveHistorySAN[idx]
            if idx + 1 < moveHistorySAN.count {
                pgnMoves.append("\(num). \(whiteSAN) \(moveHistorySAN[idx + 1])")
            } else {
                pgnMoves.append("\(num). \(whiteSAN)")
            }
        }
        let moveText = pgnMoves.isEmpty ? "(從截圖或 FEN 載入局面)" : pgnMoves.joined(separator: " ")
        let scoreText = engineService.currentAnalysis?.primaryLine?.formattedScore ?? "0.00"
        let report = """
        [Event "Chess.com Bot Match Review"]
        [Opening "\(tacticalRadar.openingName)"]
        [Perspective "\(perspective.displayName)"]
        [Accuracy "\(sessionAccuracyText)"]
        [Eval "\(scoreText)"]
        [FEN "\(boardState.toFEN())"]

        \(moveText)
        """
        UIPasteboard.general.string = report
        showBanner("[已複製] PGN 與對局複盤報告已存至剪貼簿")
    }

    private func recordAnalysisTelemetry(_ analysis: EngineAnalysisResult) {
        guard let primary = analysis.primaryLine else { return }
        let gamePly = max(1, (boardState.fullMoveNumber - 1) * 2 + (boardState.sideToMove == .white ? 0 : 1))
        lastKnownWinPct = Int(primary.winProbability(for: perspective).rounded())
        lastKnownWDL = primary.wdlBreakdown(for: perspective, gamePhasePly: gamePly)
        lastKnownEvalStr = primary.formattedScore

        guard analysis.fen != lastEvaluatedFEN else { return }
        lastEvaluatedFEN = analysis.fen
        let whitePct = primary.winProbabilityWhite
        evalHistoryWhitePct.append(whitePct)
        if evalHistoryWhitePct.count > 24 {
            evalHistoryWhitePct.removeFirst(evalHistoryWhitePct.count - 24)
        }

        let currentCampPct = primary.winProbability(for: perspective)
        if let prevPct = previousCampWinPct {
            let delta = currentCampPct - prevPct
            let moveAcc = max(0.0, min(100.0, 100.0 + min(0.0, delta * 2.2)))
            moveAccuracyScores.append(moveAcc)
            if delta >= 3.0 {
                lastMoveQualityBadge = "[妙手] +\(Int(delta.rounded()))%"
            } else if delta >= -1.5 {
                lastMoveQualityBadge = "[最佳]"
            } else if delta >= -5.0 {
                lastMoveQualityBadge = "[良好]"
            } else if delta >= -12.0 {
                lastMoveQualityBadge = "[偏差] \(Int(delta.rounded()))%"
            } else {
                lastMoveQualityBadge = "[失誤] \(Int(delta.rounded()))%"
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

    func toggleBigScreenBannerPrompt() {
        bigScreenBannerPromptEnabled.toggle()
        if !bigScreenBannerPromptEnabled {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["chess.tactical.live.banner"])
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["chess.tactical.live.banner"])
            showBanner("已關閉大螢幕頂部即時橫幅通知")
        } else {
            requestBannerNotificationPermissionIfNeeded()
            lastNotifiedBannerKey = ""
            if let analysis = engineService.currentAnalysis {
                postBigScreenTacticalBannerIfNeeded(analysis)
            }
            showBanner("已開啟大螢幕頂部即時戰術橫幅")
        }
        syncPiPContent()
    }

    func togglePiPBigScreenBoardMode() {
        pipBigScreenBoardMode.toggle()
        showBanner(pipBigScreenBoardMode ? "懸浮窗切換：大螢幕巨型棋盤模式" : "懸浮窗切換：左棋盤 + 右勝率雙顯模式")
        syncPiPContent()
    }

    private func postBigScreenTacticalBannerIfNeeded(_ analysis: EngineAnalysisResult) {
        guard bigScreenBannerPromptEnabled,
              isBoardDetected,
              !isFairPlaySafetyLocked,
              !isWaitingForOpponentReply,
              engineService.autoHintEnabled,
              let primary = analysis.primaryLine else {
            return
        }

        let key = "\(analysis.fen)|\(primary.bestMove.uci)|\(engineService.coachPieceOnlyHintMode)"
        guard key != lastNotifiedBannerKey else { return }
        lastNotifiedBannerKey = key

        let gamePly = max(1, (boardState.fullMoveNumber - 1) * 2 + (boardState.sideToMove == .white ? 0 : 1))
        let winPct = Int(primary.winProbability(for: perspective).rounded())
        let wdl = primary.wdlBreakdown(for: perspective, gamePhasePly: gamePly)
        let movingPiece = boardState.piece(at: primary.bestMove.from)
        let pieceName = movingPiece?.type.fullChineseName ?? "棋子"

        let posHint = engineService.coachPieceOnlyHintMode
            ? primary.bestMove.from.relativePositionHint(for: perspective)
            : "\(primary.bestMove.from.relativePositionHint(for: perspective)) -> \(primary.bestMove.to.relativePositionHint(for: perspective))"

        let reasonText = primary.tacticalReason.isEmpty
            ? boardState.explainMoveTactics(primary.bestMove)
            : primary.tacticalReason
        let replySAN = (engineService.showOpponentReplyArrow ? primary.predictedOpponentReply?.san : nil) ?? "-"

        let content = UNMutableNotificationContent()
        if engineService.coachPieceOnlyHintMode {
            content.title = "勝率 \(winPct)% (\(primary.formattedScore))｜建議動：\(pieceName) (\(primary.bestMove.from.algebraic))"
        } else {
            content.title = "勝率 \(winPct)% (\(primary.formattedScore))｜\(pieceName) \(primary.bestMove.coordinateDisplay) [\(primary.bestMove.san)]"
        }
        content.subtitle = "螢幕位置：\(posHint)｜勝\(wdl.win)% 和\(wdl.draw)% 負\(wdl.loss)%"
        content.body = "戰術目的：\(reasonText)｜預計敵應：\(replySAN)"
        content.interruptionLevel = .active

        let request = UNNotificationRequest(
            identifier: "chess.tactical.live.banner",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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
        isBoardDetected = true
        lastMove = nil
        clearSelection()
        showBanner("已成功載入局面（輪到\(boardState.sideToMove.displayName)）")
        triggerAnalysis()
        return true
    }

    func applyCustomBoard(_ editedBoard: ChessBoardState) {
        history.append(boardState)
        boardState = editedBoard
        isBoardDetected = true
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
        if payload.boardDetected == false || payload.fen.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingBroadcastKey = nil
            pendingBroadcastCount = 0
            if isBoardDetected {
                isBoardDetected = false
                isWaitingForOpponentReply = false
                engineService.clearAnalysis()
                syncPiPContent()
            }
            return
        }

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

        lastSyncTimestamp = Date()
        scanCount += 1

        if !hasShownBroadcastSyncBanner {
            hasShownBroadcastSyncBanner = true
            pipManager.showPiPBanner("[實時] 畫面同步運作中")
        }

        let placementKey = String(parsedBoard.toFEN().split(separator: " ").first ?? "")

        if !isBoardDetected {
            if pendingBroadcastKey == placementKey {
                pendingBroadcastCount += 1
            } else {
                pendingBroadcastKey = placementKey
                pendingBroadcastCount = 1
            }
            guard pendingBroadcastCount >= 2 else { return }
            pendingBroadcastKey = nil
            pendingBroadcastCount = 0
            isBoardDetected = true
            previousAcceptedSquares = nil
            boardState = adjustedBoard
            perspective = newPerspective
            isFairPlaySafetyLocked = false
            safetyLockReason = nil
            isWaitingForOpponentReply = false
            clearSelection()
            triggerAnalysis()
            return
        }

        let boardChanged = adjustedBoard.squares != boardState.squares || adjustedBoard.sideToMove != boardState.sideToMove
        let perspChanged = newPerspective != perspective

        guard boardChanged || perspChanged else {
            pendingBroadcastKey = nil
            pendingBroadcastCount = 0
            return
        }

        if adjustedBoard.squares != boardState.squares {
            if let prevSq = previousAcceptedSquares,
               adjustedBoard.squares == prevSq,
               CACurrentMediaTime() - lastAcceptedMoveTime < 1.2 {
                return
            }
        }
        pendingBroadcastKey = nil
        pendingBroadcastCount = 0

        if adjustedBoard.squares != boardState.squares {
            previousAcceptedSquares = boardState.squares
            lastAcceptedMoveTime = CACurrentMediaTime()

            var ownProbe = boardState
            ownProbe.sideToMove = newPerspective
            let matchingOwnMove = ownProbe.legalMoves(includeFormattedSAN: false)
                .first { ownProbe.applyingRaw($0).squares == parsedBoard.squares }

            var oppProbe = boardState
            oppProbe.sideToMove = newPerspective.opposite
            let matchingOppMove = oppProbe.legalMoves(includeFormattedSAN: false)
                .first { oppProbe.applyingRaw($0).squares == parsedBoard.squares }

            history.append(boardState)
            boardState = adjustedBoard
            perspective = newPerspective
            isFairPlaySafetyLocked = false
            safetyLockReason = nil
            clearSelection()

            if let ownMove = matchingOwnMove, matchingOppMove == nil {
                lastMove = ownMove
                isWaitingForOpponentReply = true
                engineService.clearAnalysis()
                syncPiPContent()
                let boardAfterOurMove = ownProbe.applyingRaw(ownMove)
                engineService.ponderWhileWaitingForOpponent(boardAfterOurMove: boardAfterOurMove)
                return
            } else {
                lastMove = matchingOppMove
                isWaitingForOpponentReply = false
            }
        } else {
            perspective = newPerspective
            isFairPlaySafetyLocked = false
            safetyLockReason = nil
            isWaitingForOpponentReply = false
        }
        triggerAnalysis()
    }

    func forceScanFromPiP() async {
        pipManager.showPiPBanner("[掃描] 讀取最新截圖...")
        if let image = await screenshotMonitor.forceFetchNewestImageIgnoringCache() {
            let ok = await processScreenshotImage(image, isFromBackgroundMonitor: true)
            pipManager.showPiPBanner(ok ? "[成功] 已同步最新局面" : "[警示] 未偵測到棋盤")
            return
        }
        if let clipImg = UIPasteboard.general.image {
            let ok = await processScreenshotImage(clipImg, isFromBackgroundMonitor: true)
            pipManager.showPiPBanner(ok ? "[成功] 已同步剪貼簿" : "[警示] 無新截圖")
            return
        }
        pipManager.showPiPBanner("[警示] 無新截圖")
    }

    func handlePiPSkipForward() async {
        if screenshotMonitor.isMonitoring {
            let beforeCount = scanCount
            screenshotMonitor.checkForRecentScreenshotNow()
            try? await Task.sleep(nanoseconds: 250_000_000)
            if scanCount > beforeCount {
                pipManager.showPiPBanner("[成功] 已掃描最新畫面")
                return
            }
        }

        guard isBoardDetected else {
            pipManager.showPiPBanner("[待機] 等待偵測棋盤中")
            return
        }
        guard !isFairPlaySafetyLocked else {
            pipManager.showPiPBanner("[安全鎖] 已隱藏提示")
            return
        }
        skipBlockedMoveAndReanalyze()
        pipManager.showPiPBanner("[換步] 已切換備選安全步")
    }

    func handlePiPSkipBackward() {
        resetBoard()
        pipManager.showPiPBanner("[重置] 等待偵測棋盤")
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
                self.pipManager.showPiPBanner("[成功] 已由捷徑掃描同步")
                return
            }

            if let clipImg = UIPasteboard.general.image,
               await self.processScreenshotImage(clipImg, isFromBackgroundMonitor: false) {
                self.pipManager.showPiPBanner("[成功] 已由剪貼簿掃描")
                return
            }

            self.pipManager.showPiPBanner("[警示] 無可掃描截圖")
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
                showBanner("已從相簿刪除最近一張暫存截圖")
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

        let isIdentical = isBoardDetected
            && newBoard.squares == boardState.squares
            && newBoard.sideToMove == boardState.sideToMove
            && resolvedCamp == perspective
        if keepSideToMoveIfSameBoard && isIdentical && engineService.currentAnalysis != nil {
            syncPiPContent()
            return
        }

        history.append(boardState)
        boardState = newBoard
        perspective = resolvedCamp
        isBoardDetected = true
        previousAcceptedSquares = nil
        lastMove = nil
        clearSelection()
        if isFairPlaySafetyLocked {
            showBanner("[安全鎖定] \(result.detectedMatchContextNote)")
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
