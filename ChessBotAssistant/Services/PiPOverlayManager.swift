import AVFoundation
import AVKit
import CoreMedia
import CoreVideo
import Foundation
import SwiftUI
import UIKit

@MainActor
final class PiPOverlayManager: NSObject, ObservableObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    @Published private(set) var isPiPActive: Bool = false
    @Published private(set) var isPiPPossible: Bool = false
    @Published private(set) var isPiPSupported: Bool = AVPictureInPictureController.isPictureInPictureSupported()
    @Published private(set) var statusMessage: String = "子母畫面待機中"

    var onHeartbeatTick: (() -> Void)?
    var onPiPPlayPauseTapped: (() -> Void)?
    var onPiPSkipForwardTapped: (() -> Void)?
    var onPiPSkipBackwardTapped: (() -> Void)?

    let displayLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController?
    private var refreshTimer: Timer?
    private var silentAudioPlayer: AVAudioPlayer?
    private var pipBannerText: String?
    private var pipBannerClearTask: Task<Void, Never>?
    private var startTime = CACurrentMediaTime()

    private var latestBoard: ChessBoardState = .startingPosition
    private var latestLastMove: ChessMove?
    private var latestAnalysis: EngineAnalysisResult?
    private var latestPerspective: PieceColor = .white
    private var latestAutoHint: Bool = true
    private var latestAutoSyncActive: Bool = false
    private var latestCoachPieceOnlyMode: Bool = false
    private var latestIsSafetyLocked: Bool = false
    private var latestZeroNetworkMode: Bool = true
    private var latestShowOpponentReplyArrow: Bool = true
    private var latestCampReason: String = ""
    private var latestOpeningName: String = ""
    private var latestThinkRange: String = ""
    private var latestHangingCount: Int = 0
    private var latestBoardTheme: BoardTheme = .glacierBlue
    private var latestIsKingInCheck: Bool = false
    private var latestPinnedCount: Int = 0
    private var latestIsWaitingForOpponentReply: Bool = false
    private var latestIsBoardDetected: Bool = false
    private var latestBigScreenBoardMode: Bool = false
    private var latestIsAnalyzing: Bool = false
    private var latestPaceRemainingSeconds: Int = 0
    private var latestStealthSafetyScore: Int = 90
    private var latestPinnedSummary: String = ""
    private var latestLastKnownWinPct: Int = 50
    private var latestLastKnownWDL: (win: Int, draw: Int, loss: Int) = (38, 24, 38)
    private var latestLastKnownEvalStr: String = "0.00"
    private var latestThreatSummary: String = ""
    private var latestSearchTimeMs: Int = 0
    private var contentRevision: UInt64 = 0
    private var renderedRevision: UInt64 = 0
    private var cachedPixelBuffer: CVPixelBuffer?
    private var lastEnqueuedCanvasSize: CGSize = .zero

    override init() {
        super.init()
        setupDisplayLayer()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeRaw = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else {
            return
        }
        if type == .ended && (isPiPActive || latestAutoSyncActive) {
            startSilentAudioKeepAlive()
        }
    }

    func showPiPBanner(_ text: String) {
        pipBannerText = text
        contentRevision &+= 1
        pipBannerClearTask?.cancel()
        pipBannerClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.pipBannerText = nil
            self.contentRevision &+= 1
            self.pushCurrentFrame(forceRedraw: true)
        }
        pushCurrentFrame(forceRedraw: true)
    }

    private func setupDisplayLayer() {
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor(red: 0.07, green: 0.09, blue: 0.12, alpha: 1.0).cgColor

        if AVPictureInPictureController.isPictureInPictureSupported() {
            let contentSource = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: displayLayer,
                playbackDelegate: self
            )
            let controller = AVPictureInPictureController(contentSource: contentSource)
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            self.pipController = controller
            self.isPiPPossible = controller.isPictureInPicturePossible
        }
    }

    func updateContent(
        board: ChessBoardState,
        lastMove: ChessMove? = nil,
        analysis: EngineAnalysisResult?,
        perspective: PieceColor,
        autoHintEnabled: Bool,
        autoSyncActive: Bool,
        coachPieceOnlyMode: Bool,
        isSafetyLocked: Bool,
        zeroNetworkMode: Bool,
        showOpponentReplyArrow: Bool = true,
        campReason: String = "",
        openingName: String = "",
        thinkRange: String = "",
        hangingCount: Int = 0,
        boardTheme: BoardTheme = .glacierBlue,
        isKingInCheck: Bool = false,
        pinnedCount: Int = 0,
        isWaitingForOpponentReply: Bool = false,
        isBoardDetected: Bool = false,
        bigScreenBoardMode: Bool = false,
        isAnalyzing: Bool = false,
        paceRemainingSeconds: Int = 0,
        stealthSafetyScore: Int = 90,
        pinnedSummary: String = "",
        lastKnownWinPct: Int = 50,
        lastKnownWDL: (win: Int, draw: Int, loss: Int) = (38, 24, 38),
        lastKnownEvalStr: String = "0.00",
        threatSummary: String = "",
        searchTimeMs: Int = 0
    ) {
        self.latestBoard = board
        self.latestLastMove = lastMove
        self.latestAnalysis = analysis
        self.latestPerspective = perspective
        self.latestAutoHint = autoHintEnabled
        self.latestAutoSyncActive = autoSyncActive
        self.latestCoachPieceOnlyMode = coachPieceOnlyMode
        self.latestIsSafetyLocked = isSafetyLocked
        self.latestZeroNetworkMode = zeroNetworkMode
        self.latestShowOpponentReplyArrow = showOpponentReplyArrow
        self.latestCampReason = campReason
        self.latestOpeningName = openingName
        self.latestThinkRange = thinkRange
        self.latestHangingCount = hangingCount
        self.latestBoardTheme = boardTheme
        self.latestIsKingInCheck = isKingInCheck
        self.latestPinnedCount = pinnedCount
        self.latestIsWaitingForOpponentReply = isWaitingForOpponentReply
        self.latestIsBoardDetected = isBoardDetected
        self.latestBigScreenBoardMode = bigScreenBoardMode
        self.latestIsAnalyzing = isAnalyzing
        self.latestPaceRemainingSeconds = paceRemainingSeconds
        self.latestStealthSafetyScore = stealthSafetyScore
        self.latestPinnedSummary = pinnedSummary
        self.latestLastKnownWinPct = lastKnownWinPct
        self.latestLastKnownWDL = lastKnownWDL
        self.latestLastKnownEvalStr = lastKnownEvalStr
        self.latestThreatSummary = threatSummary
        self.latestSearchTimeMs = searchTimeMs
        contentRevision &+= 1
        pushCurrentFrame(forceRedraw: true)
    }

    func togglePiP() {
        guard let pipController else {
            statusMessage = "此裝置不支援系統子母畫面"
            return
        }

        if pipController.isPictureInPictureActive {
            pipController.stopPictureInPicture()
            return
        }

        configureAudioSession()
        startSilentAudioKeepAlive()
        pushCurrentFrame()
        startFrameHeartbeat()

        // Slight delay allows the freshly enqueued sample buffer to prime the PiP renderer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, let controller = self.pipController else { return }
            self.isPiPPossible = controller.isPictureInPicturePossible
            controller.startPictureInPicture()
        }
    }

    func startPiPIfNeeded() {
        guard let pipController, !pipController.isPictureInPictureActive else { return }
        togglePiP()
    }

    func startSilentAudioKeepAlive() {
        configureAudioSession()
        if let player = silentAudioPlayer, player.isPlaying {
            return
        }
        guard let wavData = Self.makeSilentWAVData(durationSeconds: 1.0, sampleRate: 8000) else {
            return
        }
        do {
            let player = try AVAudioPlayer(data: wavData, fileTypeHint: AVFileType.wav.rawValue)
            player.numberOfLoops = -1
            player.volume = 0.01
            player.prepareToPlay()
            player.play()
            silentAudioPlayer = player
        } catch {
            statusMessage = "背景保活音訊啟動失敗：\(error.localizedDescription)"
        }
    }

    func stopSilentAudioKeepAlive() {
        silentAudioPlayer?.stop()
        silentAudioPlayer = nil
    }

    private static func makeSilentWAVData(durationSeconds: Double, sampleRate: UInt32) -> Data? {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let frameCount = UInt32(max(1.0, Double(sampleRate) * durationSeconds))
        let dataSize = frameCount * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let riffSize = UInt32(36) + dataSize

        var data = Data(capacity: Int(44 + dataSize))
        func appendLE<T: FixedWidthInteger>(_ value: T) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        appendLE(riffSize)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        appendLE(UInt32(16)) // PCM chunk size
        appendLE(UInt16(1))  // PCM format
        appendLE(numChannels)
        appendLE(sampleRate)
        appendLE(byteRate)
        appendLE(blockAlign)
        appendLE(bitsPerSample)
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        appendLE(dataSize)
        data.append(Data(count: Int(dataSize)))
        return data
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            statusMessage = "音訊工作階段設定失敗：\(error.localizedDescription)"
        }
    }

    private func startFrameHeartbeat() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] t in
            guard let self else {
                t.invalidate()
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if (self.isPiPActive || self.latestAutoSyncActive),
                   (self.silentAudioPlayer?.isPlaying != true) {
                    self.startSilentAudioKeepAlive()
                }
                self.onHeartbeatTick?()
                self.pushCurrentFrame(forceRedraw: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopFrameHeartbeatIfIdle() {
        if !isPiPActive {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    func pushCurrentFrame(forceRedraw: Bool = false) {
        let pixelBuffer: CVPixelBuffer?
        if forceRedraw || cachedPixelBuffer == nil || renderedRevision != contentRevision {
            let hudImage = renderPiPHUDImage()
            pixelBuffer = makePixelBuffer(from: hudImage)
            if let pixelBuffer {
                cachedPixelBuffer = pixelBuffer
                renderedRevision = contentRevision
            }
        } else {
            pixelBuffer = cachedPixelBuffer
        }

        guard let buffer = pixelBuffer,
              let sampleBuffer = makeSampleBuffer(from: buffer) else { return }

        let currentSize = CGSize(
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer)
        )
        if lastEnqueuedCanvasSize != .zero && lastEnqueuedCanvasSize != currentSize {
            displayLayer.sampleBufferRenderer.flush()
        }
        lastEnqueuedCanvasSize = currentSize

        if displayLayer.sampleBufferRenderer.status == .failed {
            displayLayer.sampleBufferRenderer.flush()
        }
        displayLayer.sampleBufferRenderer.enqueue(sampleBuffer)

        if let controller = pipController {
            isPiPPossible = controller.isPictureInPicturePossible
        }
    }

    // MARK: - AVPictureInPictureControllerDelegate

    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.statusMessage = "正在開啟懸浮子母畫面..."
            self.pushCurrentFrame()
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.isPiPActive = true
            self.statusMessage = "懸浮窗已開啟，可切換至 Chess.com 對戰"
            self.startFrameHeartbeat()
            self.pushCurrentFrame()
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.isPiPActive = false
            self.statusMessage = "子母畫面已關閉"
            self.stopFrameHeartbeatIfIdle()
            if !self.latestAutoSyncActive {
                self.stopSilentAudioKeepAlive()
            }
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            self.isPiPActive = false
            self.statusMessage = "子母畫面啟動失敗：\(error.localizedDescription)"
            self.stopFrameHeartbeatIfIdle()
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }

    // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onPiPPlayPauseTapped?()
            self.pushCurrentFrame()
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        Task { @MainActor in
            self.pushCurrentFrame()
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        let isForward = skipInterval.seconds >= 0
        Task { @MainActor [weak self] in
            if isForward {
                self?.onPiPSkipForwardTapped?()
            } else {
                self?.onPiPSkipBackwardTapped?()
            }
        }
        completionHandler()
    }

    // MARK: - HUD Frame Renderer (Waiting / Dual-Split Board+HUD / Big-Screen Giant Board)

    private func renderPiPHUDImage() -> UIImage {
        let canvasSize: CGSize
        if !latestIsBoardDetected {
            canvasSize = CGSize(width: 760, height: 440)
        } else if latestBigScreenBoardMode {
            canvasSize = CGSize(width: 540, height: 620)
        } else {
            canvasSize = CGSize(width: 760, height: 440)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext

            UIColor(red: 0.075, green: 0.095, blue: 0.125, alpha: 1.0).setFill()
            cg.fill(CGRect(origin: .zero, size: canvasSize))

            let netLabel = latestZeroNetworkMode ? "[離線引擎 10MB]" : "[雲端混合]"
            let syncLabel = latestAutoSyncActive ? "[實時監聽中]" : "[手動掃描]"

            if !latestIsBoardDetected {
                renderWaitingDetectionHUD(in: cg, size: canvasSize, netLabel: netLabel, syncLabel: syncLabel)
            } else if latestBigScreenBoardMode {
                renderBigScreenGiantBoardHUD(in: cg, size: canvasSize, netLabel: netLabel, syncLabel: syncLabel)
            } else {
                renderDualSplitBoardHUD(in: cg, size: canvasSize, netLabel: netLabel, syncLabel: syncLabel)
            }
        }
    }

    private func renderWaitingDetectionHUD(in cg: CGContext, size: CGSize, netLabel: String, syncLabel: String) {
        let waitRect = CGRect(x: 24, y: 20, width: size.width - 48, height: size.height - 40)
        UIColor(red: 0.11, green: 0.145, blue: 0.195, alpha: 1.0).setFill()
        UIBezierPath(roundedRect: waitRect, cornerRadius: 16).fill()
        UIColor(red: 0.28, green: 0.72, blue: 0.92, alpha: 0.38).setStroke()
        let border = UIBezierPath(roundedRect: waitRect, cornerRadius: 16)
        border.lineWidth = 2.0
        border.stroke()

        NSString(string: "[CHESS BOT 輔助大師]").draw(
            at: CGPoint(x: 42, y: 38),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: .heavy),
                .foregroundColor: UIColor(red: 0.50, green: 0.88, blue: 0.45, alpha: 1.0)
            ]
        )

        let rightStyle = NSMutableParagraphStyle()
        rightStyle.alignment = .right
        NSString(string: "\(syncLabel) · \(netLabel) · 防封 \(latestStealthSafetyScore)%").draw(
            in: CGRect(x: 280, y: 38, width: size.width - 322, height: 22),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 13.5, weight: .bold),
                .foregroundColor: UIColor(red: 0.36, green: 0.84, blue: 0.98, alpha: 1.0),
                .paragraphStyle: rightStyle
            ]
        )

        let centerStyle = NSMutableParagraphStyle()
        centerStyle.alignment = .center

        NSString(string: "等待偵測棋盤").draw(
            in: CGRect(x: 40, y: 136, width: size.width - 80, height: 54),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 42, weight: .heavy),
                .foregroundColor: UIColor.white,
                .paragraphStyle: centerStyle
            ]
        )

        NSString(string: "請切換至 Chess.com 對局畫面（螢幕直播或截圖自動識別）").draw(
            in: CGRect(x: 44, y: 204, width: size.width - 88, height: 30),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor(red: 0.36, green: 0.84, blue: 0.98, alpha: 1.0),
                .paragraphStyle: centerStyle
            ]
        )

        NSString(string: "偵測到棋盤後立即顯示：8x8 戰術棋盤與箭頭 · 我方勝率 · 頂部大螢幕即時橫幅").draw(
            in: CGRect(x: 44, y: 254, width: size.width - 88, height: 28),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 14.5, weight: .medium),
                .foregroundColor: UIColor(white: 0.72, alpha: 1.0),
                .paragraphStyle: centerStyle
            ]
        )

        let bottomStrip = CGRect(x: 40, y: size.height - 64, width: size.width - 80, height: 30)
        drawFooterStrip(rect: bottomStrip, defaultText: "[播放鍵：立即讀取截圖]   [快轉鍵：換步/掃描]   [倒轉鍵：重置]")
    }

    private func renderDualSplitBoardHUD(in cg: CGContext, size: CGSize, netLabel: String, syncLabel: String) {
        // Left: 8x8 Tactical Chessboard with arrows (384 x 384)
        let boardRect = CGRect(x: 18, y: 16, width: 384, height: 384)
        drawDetectedChessBoard(in: boardRect, showCoordinateBadgesOnPrimary: false, in: cg)

        let primary = latestAnalysis?.primaryLine
        let winPct = primary.map { Int($0.winProbability(for: latestPerspective).rounded()) } ?? latestLastKnownWinPct
        let wdl = primary?.wdlBreakdown(for: latestPerspective) ?? latestLastKnownWDL
        let evalStr = primary?.formattedScore ?? latestLastKnownEvalStr
        let campShort = latestPerspective == .white ? "執白" : "執黑"
        let depthText = latestAnalysis.map { "D\($0.depthReached)" } ?? (latestIsAnalyzing ? "計算中" : "待機")

        // Right Column (x: 416, width: 326)
        let rightX: CGFloat = 416
        let rightW: CGFloat = 326

        // Card 1: Big Win-Rate + WDL Bar (y: 16, h: 118)
        let winCard = CGRect(x: rightX, y: 16, width: rightW, height: 118)
        drawCard(winCard, fill: UIColor(red: 0.115, green: 0.155, blue: 0.205, alpha: 1.0), border: UIColor(white: 1.0, alpha: 0.10))

        NSString(string: "我方(\(campShort))勝率").draw(
            at: CGPoint(x: rightX + 12, y: 24),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 12.5, weight: .bold),
                .foregroundColor: UIColor(red: 0.36, green: 0.84, blue: 0.98, alpha: 1.0)
            ]
        )

        let status = resolveCurrentStatusTuple()
        let pillRect = CGRect(x: rightX + rightW - 118, y: 22, width: 106, height: 22)
        drawStatusPill(rect: pillRect, text: status.title, color: status.color)

        let winColor = winRateColor(winPct)
        NSString(string: "\(winPct)%").draw(
            at: CGPoint(x: rightX + 12, y: 42),
            withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 34, weight: .heavy),
                .foregroundColor: winColor
            ]
        )

        NSString(string: "評估 \(evalStr)").draw(
            at: CGPoint(x: rightX + 126, y: 49),
            withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .heavy),
                .foregroundColor: UIColor.white
            ]
        )

        let rightAlign = NSMutableParagraphStyle()
        rightAlign.alignment = .right
        NSString(string: depthText).draw(
            in: CGRect(x: rightX + 230, y: 52, width: 84, height: 18),
            withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 12.5, weight: .bold),
                .foregroundColor: UIColor(red: 0.50, green: 0.88, blue: 0.48, alpha: 1.0),
                .paragraphStyle: rightAlign
            ]
        )

        NSString(string: "勝 \(wdl.win)%   和 \(wdl.draw)%   負 \(wdl.loss)%").draw(
            at: CGPoint(x: rightX + 12, y: 86),
            withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .bold),
                .foregroundColor: UIColor(white: 0.90, alpha: 1.0)
            ]
        )

        drawWDLBar(
            rect: CGRect(x: rightX + 12, y: 106, width: rightW - 24, height: 10),
            wdl: wdl,
            in: cg
        )

        // Card 2: Primary Move Command Card (y: 142, h: 144)
        let cmdCard = CGRect(x: rightX, y: 142, width: rightW, height: 144)
        drawPrimaryCommandCard(
            in: cmdCard,
            primary: primary,
            winPct: winPct,
            compactForSplitLayout: true
        )

        // Card 3 & 4: Candidate #2 and #3 Rows (y: 294 & y: 350, h: 50)
        let secondaryColors: [UIColor] = [
            UIColor(red: 0.22, green: 0.78, blue: 0.96, alpha: 1.0),
            UIColor(red: 0.98, green: 0.72, blue: 0.22, alpha: 1.0)
        ]
        let candidates = Array((latestAnalysis?.lines ?? []).dropFirst().prefix(2))
        for idx in 0..<2 {
            let rowY: CGFloat = idx == 0 ? 294 : 350
            let rowRect = CGRect(x: rightX, y: rowY, width: rightW, height: 50)
            drawCard(rowRect, fill: UIColor(red: 0.12, green: 0.15, blue: 0.20, alpha: 1.0), border: UIColor(white: 1.0, alpha: 0.08))

            if !latestIsSafetyLocked && !latestIsWaitingForOpponentReply && !latestCoachPieceOnlyMode && latestAutoHint,
               idx < candidates.count {
                let line = candidates[idx]
                let accent = secondaryColors[idx]
                accent.setFill()
                UIBezierPath(roundedRect: CGRect(x: rightX, y: rowY, width: 5, height: 50), cornerRadius: 2.5).fill()

                let pName = latestBoard.piece(at: line.bestMove.from)?.type.displayName ?? "子"
                let lineWin = Int(line.winProbability(for: latestPerspective).rounded())

                let leftPara = NSMutableParagraphStyle()
                leftPara.lineBreakMode = .byTruncatingTail
                NSString(string: "#\(idx + 2) \(pName) \(line.bestMove.san) \(line.bestMove.coordinateDisplay)").draw(
                    in: CGRect(x: rightX + 12, y: rowY + 6, width: 196, height: 18),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 13.5, weight: .heavy),
                        .foregroundColor: UIColor.white,
                        .paragraphStyle: leftPara
                    ]
                )

                NSString(string: "\(line.formattedScore) · \(lineWin)%").draw(
                    in: CGRect(x: rightX + 206, y: rowY + 7, width: 108, height: 18),
                    withAttributes: [
                        .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                        .foregroundColor: accent,
                        .paragraphStyle: rightAlign
                    ]
                )

                let subText = line.tacticalReason.isEmpty ? line.continuationPreview : line.tacticalReason
                NSString(string: subText).draw(
                    in: CGRect(x: rightX + 12, y: rowY + 27, width: rightW - 22, height: 16),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 11.5, weight: .medium),
                        .foregroundColor: UIColor(white: 0.72, alpha: 1.0),
                        .paragraphStyle: leftPara
                    ]
                )
            } else {
                let placeholderText = latestIsWaitingForOpponentReply
                    ? "等待對手回棋後自動更新備選線 #\(idx + 2)"
                    : "備選線 #\(idx + 2) 待分析"
                NSString(string: placeholderText).draw(
                    in: CGRect(x: rightX + 12, y: rowY + 16, width: rightW - 24, height: 18),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                        .foregroundColor: UIColor(white: 0.50, alpha: 1.0)
                    ]
                )
            }
        }

        // Bottom Footer
        let openShort = latestOpeningName.isEmpty ? "實戰同步" : latestOpeningName
        let defaultFooter = "[防封 \(latestStealthSafetyScore)%] · \(netLabel) · \(syncLabel) · \(openShort) · [播:掃描 | 快轉:換步]"
        drawFooterStrip(rect: CGRect(x: 18, y: 408, width: 724, height: 24), defaultText: defaultFooter)
    }

    private func renderBigScreenGiantBoardHUD(in cg: CGContext, size: CGSize, netLabel: String, syncLabel: String) {
        let primary = latestAnalysis?.primaryLine
        let winPct = primary.map { Int($0.winProbability(for: latestPerspective).rounded()) } ?? latestLastKnownWinPct
        let wdl = primary?.wdlBreakdown(for: latestPerspective) ?? latestLastKnownWDL
        let evalStr = primary?.formattedScore ?? latestLastKnownEvalStr
        let campShort = latestPerspective == .white ? "執白" : "執黑"

        // Top Giant HUD Banner (x: 16, y: 12, w: 508, h: 98)
        let headerRect = CGRect(x: 16, y: 12, width: size.width - 32, height: 98)
        drawCard(headerRect, fill: UIColor(red: 0.115, green: 0.155, blue: 0.205, alpha: 1.0), border: UIColor(red: 0.30, green: 0.86, blue: 0.48, alpha: 0.45))

        NSString(string: "我方(\(campShort))勝率").draw(
            at: CGPoint(x: 28, y: 20),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 11.5, weight: .bold),
                .foregroundColor: UIColor(red: 0.36, green: 0.84, blue: 0.98, alpha: 1.0)
            ]
        )

        NSString(string: "\(winPct)%").draw(
            at: CGPoint(x: 28, y: 35),
            withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 32, weight: .heavy),
                .foregroundColor: winRateColor(winPct)
            ]
        )

        NSString(string: "評估 \(evalStr)").draw(
            at: CGPoint(x: 28, y: 74),
            withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                .foregroundColor: UIColor(white: 0.85, alpha: 1.0)
            ]
        )

        drawWDLBar(rect: CGRect(x: 28, y: 92, width: 138, height: 8), wdl: wdl, in: cg)

        // Divider line
        UIColor(white: 1.0, alpha: 0.12).setFill()
        cg.fill(CGRect(x: 178, y: 20, width: 1, height: 82))

        // Right portion of Top Banner: #1 Move + Pos Hint + Reason
        let infoX: CGFloat = 190
        let infoW: CGFloat = headerRect.maxX - infoX - 12
        let truncPara = NSMutableParagraphStyle()
        truncPara.lineBreakMode = .byTruncatingTail

        if latestIsSafetyLocked {
            NSString(string: "[安全鎖定] 疑似計時對局").draw(
                in: CGRect(x: infoX, y: 24, width: infoW, height: 26),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 18, weight: .heavy),
                    .foregroundColor: UIColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1.0),
                    .paragraphStyle: truncPara
                ]
            )
            NSString(string: "請切回主程式解除 Bot 安全鎖定").draw(
                in: CGRect(x: infoX, y: 56, width: infoW, height: 22),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: UIColor.white
                ]
            )
        } else if latestIsWaitingForOpponentReply {
            NSString(string: "[等待對手落子] 穩定防跳幀鎖定中").draw(
                in: CGRect(x: infoX, y: 26, width: infoW, height: 26),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 17, weight: .heavy),
                    .foregroundColor: UIColor(red: 0.36, green: 0.84, blue: 0.98, alpha: 1.0),
                    .paragraphStyle: truncPara
                ]
            )
            NSString(string: "勝 \(wdl.win)% / 和 \(wdl.draw)% / 負 \(wdl.loss)% · 回子後立即更新箭頭").draw(
                in: CGRect(x: infoX, y: 58, width: infoW, height: 22),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 12.5, weight: .medium),
                    .foregroundColor: UIColor(white: 0.84, alpha: 1.0),
                    .paragraphStyle: truncPara
                ]
            )
        } else if let primary, latestAutoHint {
            let movingPiece = latestBoard.piece(at: primary.bestMove.from)
            let pieceFullName = movingPiece?.type.fullChineseName ?? "棋子"
            let posHint = "\(primary.bestMove.from.relativePositionHint(for: latestPerspective)) -> \(primary.bestMove.to.relativePositionHint(for: latestPerspective))"
            let reasonText = primary.tacticalReason.isEmpty
                ? latestBoard.explainMoveTactics(primary.bestMove)
                : primary.tacticalReason
            let replyStr = (latestShowOpponentReplyArrow ? primary.predictedOpponentReply?.san : nil) ?? "-"

            var mateTag = ""
            if let mate = primary.mateInMoves {
                let isMyMate = (latestPerspective == .white && mate > 0) || (latestPerspective == .black && mate < 0)
                mateTag = isMyMate ? " [必殺M\(abs(mate))]" : " [敵殺M\(abs(mate))]"
            }
            let headline = latestCoachPieceOnlyMode
                ? "動：\(pieceFullName) (\(primary.bestMove.from.algebraic))\(mateTag)"
                : "#1 \(pieceFullName) \(primary.bestMove.coordinateDisplay) [\(primary.bestMove.san)]\(mateTag)"
            let headlineColor: UIColor
            if let mate = primary.mateInMoves {
                let isMyMate = (latestPerspective == .white && mate > 0) || (latestPerspective == .black && mate < 0)
                headlineColor = isMyMate
                    ? UIColor(red: 1.0, green: 0.84, blue: 0.25, alpha: 1.0)
                    : UIColor(red: 1.0, green: 0.50, blue: 0.48, alpha: 1.0)
            } else {
                headlineColor = UIColor.white
            }
            NSString(string: headline).draw(
                in: CGRect(x: infoX, y: 19, width: infoW, height: 26),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 19, weight: .heavy),
                    .foregroundColor: headlineColor,
                    .paragraphStyle: truncPara
                ]
            )

            NSString(string: "螢幕位置：\(latestCoachPieceOnlyMode ? primary.bestMove.from.relativePositionHint(for: latestPerspective) : posHint)").draw(
                in: CGRect(x: infoX, y: 47, width: infoW, height: 20),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 13.5, weight: .bold),
                    .foregroundColor: UIColor(red: 0.42, green: 0.88, blue: 1.0, alpha: 1.0),
                    .paragraphStyle: truncPara
                ]
            )

            let thirdLineText: String
            let thirdLineColor: UIColor
            if !latestThreatSummary.isEmpty {
                thirdLineText = latestThreatSummary
                thirdLineColor = UIColor(red: 1.0, green: 0.66, blue: 0.34, alpha: 1.0)
            } else {
                thirdLineText = "目的：\(reasonText)｜敵應：\(replyStr)"
                thirdLineColor = UIColor(red: 0.64, green: 0.98, blue: 0.72, alpha: 1.0)
            }
            NSString(string: thirdLineText).draw(
                in: CGRect(x: infoX, y: 70, width: infoW, height: 20),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 12.5, weight: .bold),
                    .foregroundColor: thirdLineColor,
                    .paragraphStyle: truncPara
                ]
            )
        } else {
            NSString(string: latestIsAnalyzing ? "[穩定計算中] 正在分析最佳著法..." : "[大螢幕巨型棋盤] 待機同步中").draw(
                in: CGRect(x: infoX, y: 38, width: infoW, height: 26),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 16, weight: .heavy),
                    .foregroundColor: UIColor(red: 0.45, green: 0.92, blue: 0.55, alpha: 1.0),
                    .paragraphStyle: truncPara
                ]
            )
        }

        // Giant 8x8 Tactical Chessboard (464 x 464)
        let boardSide: CGFloat = 464
        let boardRect = CGRect(x: (size.width - boardSide) / 2.0, y: 118, width: boardSide, height: boardSide)
        drawDetectedChessBoard(in: boardRect, showCoordinateBadgesOnPrimary: true, in: cg)

        // Bottom Footer
        let openShort = latestOpeningName.isEmpty ? "實戰同步" : latestOpeningName
        let speedTag = latestSearchTimeMs > 0 ? " · \(latestSearchTimeMs)ms" : ""
        let defaultFooter = "[大螢幕巨型盤] · \(syncLabel) · \(netLabel)\(speedTag) · \(openShort) · [播:掃描 | 快轉:換步]"
        drawFooterStrip(rect: CGRect(x: 16, y: 589, width: size.width - 32, height: 22), defaultText: defaultFooter)
    }

    private func drawPrimaryCommandCard(
        in rect: CGRect,
        primary: PVLine?,
        winPct: Int,
        compactForSplitLayout: Bool
    ) {
        if latestIsSafetyLocked {
            drawCard(rect, fill: UIColor(red: 0.28, green: 0.10, blue: 0.11, alpha: 1.0), border: UIColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 0.85))
            NSString(string: "[安全鎖定] 疑似計時對局").draw(
                in: CGRect(x: rect.minX + 12, y: rect.minY + 14, width: rect.width - 24, height: 24),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 16, weight: .heavy),
                    .foregroundColor: UIColor(red: 1.0, green: 0.55, blue: 0.55, alpha: 1.0)
                ]
            )
            NSString(string: "已自動隱藏提示防止誤封。\n若確定為 Bot 練習賽，請回主程式點擊解鎖。").draw(
                in: CGRect(x: rect.minX + 12, y: rect.minY + 46, width: rect.width - 24, height: 68),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: UIColor.white
                ]
            )
            return
        }

        if latestIsWaitingForOpponentReply {
            drawCard(rect, fill: UIColor(red: 0.11, green: 0.16, blue: 0.22, alpha: 1.0), border: UIColor(red: 0.28, green: 0.72, blue: 0.92, alpha: 0.60))
            NSString(string: "[等待對手落子 · 防跳幀鎖定中]").draw(
                in: CGRect(x: rect.minX + 12, y: rect.minY + 14, width: rect.width - 24, height: 24),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 16, weight: .heavy),
                    .foregroundColor: UIColor(red: 0.36, green: 0.84, blue: 0.98, alpha: 1.0)
                ]
            )
            NSString(string: "目前我方勝率 \(winPct)%。\n待對手落子畫面穩定兩幀後，將立即更新箭頭與推薦步。").draw(
                in: CGRect(x: rect.minX + 12, y: rect.minY + 46, width: rect.width - 24, height: 68),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: UIColor(white: 0.88, alpha: 1.0)
                ]
            )
            return
        }

        if latestIsAnalyzing && primary == nil {
            drawCard(rect, fill: UIColor(red: 0.12, green: 0.15, blue: 0.20, alpha: 1.0), border: UIColor(red: 0.35, green: 0.88, blue: 0.48, alpha: 0.45))
            NSString(string: "[穩定計算中] 正在分析最佳步...").draw(
                in: CGRect(x: rect.minX + 12, y: rect.minY + 18, width: rect.width - 24, height: 24),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 16.5, weight: .heavy),
                    .foregroundColor: UIColor(red: 0.45, green: 0.92, blue: 0.55, alpha: 1.0)
                ]
            )
            NSString(string: "採用單次定案策略，避免多源切換跳幀；完成後將立即繪製箭頭與螢幕位置。").draw(
                in: CGRect(x: rect.minX + 12, y: rect.minY + 50, width: rect.width - 24, height: 64),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: UIColor(white: 0.84, alpha: 1.0)
                ]
            )
            return
        }

        if !latestAutoHint {
            drawCard(rect, fill: UIColor(red: 0.12, green: 0.15, blue: 0.19, alpha: 1.0), border: UIColor(white: 1.0, alpha: 0.10))
            NSString(string: "自動箭頭與走法提示已暫停\n（上方持續顯示我方勝率與 WDL 比例）").draw(
                in: CGRect(x: rect.minX + 12, y: rect.minY + 42, width: rect.width - 24, height: 50),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 14, weight: .bold),
                    .foregroundColor: UIColor(white: 0.80, alpha: 1.0)
                ]
            )
            return
        }

        guard let primary else {
            drawCard(rect, fill: UIColor(red: 0.12, green: 0.15, blue: 0.19, alpha: 1.0), border: UIColor(white: 1.0, alpha: 0.10))
            NSString(string: "目前無合法著法（對局可能已結束）").draw(
                in: CGRect(x: rect.minX + 12, y: rect.minY + 54, width: rect.width - 24, height: 24),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 14, weight: .bold),
                    .foregroundColor: UIColor(white: 0.80, alpha: 1.0)
                ]
            )
            return
        }

        drawCard(rect, fill: UIColor(red: 0.115, green: 0.175, blue: 0.155, alpha: 1.0), border: UIColor(red: 0.30, green: 0.88, blue: 0.48, alpha: 0.65))
        UIColor(red: 0.30, green: 0.88, blue: 0.48, alpha: 1.0).setFill()
        UIBezierPath(roundedRect: CGRect(x: rect.minX, y: rect.minY, width: 6, height: rect.height), cornerRadius: 3).fill()

        let movingPiece = latestBoard.piece(at: primary.bestMove.from)
        let pieceFullName = movingPiece?.type.fullChineseName ?? "棋子"
        let posHint = "\(primary.bestMove.from.relativePositionHint(for: latestPerspective)) -> \(primary.bestMove.to.relativePositionHint(for: latestPerspective))"
        let reasonText = primary.tacticalReason.isEmpty
            ? latestBoard.explainMoveTactics(primary.bestMove)
            : primary.tacticalReason
        let truncPara = NSMutableParagraphStyle()
        truncPara.lineBreakMode = .byTruncatingTail

        let padX = rect.minX + 14
        let innerW = rect.width - 22

        if latestCoachPieceOnlyMode {
            NSString(string: "動：\(pieceFullName) (\(primary.bestMove.from.algebraic))").draw(
                in: CGRect(x: padX, y: rect.minY + 12, width: innerW, height: 28),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 21, weight: .heavy),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: truncPara
                ]
            )
            NSString(string: "螢幕位置：\(primary.bestMove.from.relativePositionHint(for: latestPerspective))（教練半提示）").draw(
                in: CGRect(x: padX, y: rect.minY + 46, width: innerW, height: 22),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 13.5, weight: .bold),
                    .foregroundColor: UIColor(red: 0.42, green: 0.88, blue: 1.0, alpha: 1.0),
                    .paragraphStyle: truncPara
                ]
            )
        } else {
            var mateTag = ""
            if let mate = primary.mateInMoves {
                let isMyMate = (latestPerspective == .white && mate > 0) || (latestPerspective == .black && mate < 0)
                mateTag = isMyMate ? " [必殺M\(abs(mate))]" : " [敵殺M\(abs(mate))]"
            }
            let headColor: UIColor
            if let mate = primary.mateInMoves {
                let isMyMate = (latestPerspective == .white && mate > 0) || (latestPerspective == .black && mate < 0)
                headColor = isMyMate
                    ? UIColor(red: 1.0, green: 0.84, blue: 0.25, alpha: 1.0)
                    : UIColor(red: 1.0, green: 0.50, blue: 0.48, alpha: 1.0)
            } else {
                headColor = UIColor.white
            }
            NSString(string: "#1 \(pieceFullName) \(primary.bestMove.coordinateDisplay) [\(primary.bestMove.san)]\(mateTag)").draw(
                in: CGRect(x: padX, y: rect.minY + 10, width: innerW, height: 26),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: compactForSplitLayout ? 18.5 : 22, weight: .heavy),
                    .foregroundColor: headColor,
                    .paragraphStyle: truncPara
                ]
            )

            NSString(string: "螢幕位置：\(posHint)").draw(
                in: CGRect(x: padX, y: rect.minY + 40, width: innerW, height: 20),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 13.5, weight: .heavy),
                    .foregroundColor: UIColor(red: 0.42, green: 0.88, blue: 1.0, alpha: 1.0),
                    .paragraphStyle: truncPara
                ]
            )

            NSString(string: "目的：\(reasonText)").draw(
                in: CGRect(x: padX, y: rect.minY + 64, width: innerW, height: 20),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 13.5, weight: .bold),
                    .foregroundColor: UIColor(red: 0.64, green: 0.98, blue: 0.72, alpha: 1.0),
                    .paragraphStyle: truncPara
                ]
            )

            let replyStr = (latestShowOpponentReplyArrow ? primary.predictedOpponentReply?.san : nil) ?? "-"
            let contStr = primary.continuationPreview.isEmpty ? "-" : primary.continuationPreview
            NSString(string: "[敵應] \(replyStr) | 續著 \(contStr)").draw(
                in: CGRect(x: padX, y: rect.minY + 89, width: innerW, height: 18),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 12.5, weight: .semibold),
                    .foregroundColor: UIColor(white: 0.86, alpha: 1.0),
                    .paragraphStyle: truncPara
                ]
            )
        }

        let warnStr: String
        let warnColor: UIColor
        if latestIsKingInCheck {
            warnStr = "警示：國王被將軍中！受阻請按快轉換步"
            warnColor = UIColor(red: 1.0, green: 0.52, blue: 0.52, alpha: 1.0)
        } else if !latestThreatSummary.isEmpty {
            warnStr = latestThreatSummary
            warnColor = UIColor(red: 1.0, green: 0.65, blue: 0.32, alpha: 1.0)
        } else if !latestPinnedSummary.isEmpty {
            warnStr = "牽制：\(latestPinnedSummary)"
            warnColor = UIColor(red: 1.0, green: 0.76, blue: 0.36, alpha: 1.0)
        } else if latestHangingCount > 0 {
            warnStr = "警訊：目前 \(latestHangingCount) 枚友子受威脅"
            warnColor = UIColor(red: 1.0, green: 0.68, blue: 0.40, alpha: 1.0)
        } else {
            let speedStr = latestSearchTimeMs > 0 ? " · \(latestSearchTimeMs)ms" : ""
            warnStr = "防封思考 \(latestThinkRange.isEmpty ? "2-4秒" : latestThinkRange)\(speedStr) · \(latestAnalysis?.engineSource ?? "GM庫")"
            warnColor = UIColor(white: 0.70, alpha: 1.0)
        }
        NSString(string: warnStr).draw(
            in: CGRect(x: padX, y: rect.minY + 116, width: innerW, height: 18),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: warnColor,
                .paragraphStyle: truncPara
            ]
        )
    }

    // MARK: - Chessboard & Tactical Arrow Drawing

    private func drawDetectedChessBoard(
        in boardRect: CGRect,
        showCoordinateBadgesOnPrimary: Bool,
        in cg: CGContext
    ) {
        let cellSize = boardRect.width / 8.0
        let lightRGB = latestBoardTheme.lightRGB
        let darkRGB = latestBoardTheme.darkRGB
        let lightColor = UIColor(red: lightRGB.0, green: lightRGB.1, blue: lightRGB.2, alpha: 1.0)
        let darkColor = UIColor(red: darkRGB.0, green: darkRGB.1, blue: darkRGB.2, alpha: 1.0)
        let files = ["a", "b", "c", "d", "e", "f", "g", "h"]

        let primary = latestAnalysis?.primaryLine
        let showBestHighlights = !latestIsSafetyLocked && !latestIsWaitingForOpponentReply && latestAutoHint && primary != nil
        let checkedColor: PieceColor? = latestBoard.isKingInCheck(.white)
            ? .white
            : (latestBoard.isKingInCheck(.black) ? .black : nil)

        cg.saveGState()
        UIBezierPath(roundedRect: boardRect, cornerRadius: 8).addClip()

        for screenRow in 0..<8 {
            for screenCol in 0..<8 {
                let boardRow = latestPerspective == .white ? screenRow : (7 - screenRow)
                let boardCol = latestPerspective == .white ? screenCol : (7 - screenCol)
                let square = BoardSquare(row: boardRow, col: boardCol)
                let sqRect = CGRect(
                    x: boardRect.minX + CGFloat(screenCol) * cellSize,
                    y: boardRect.minY + CGFloat(screenRow) * cellSize,
                    width: cellSize,
                    height: cellSize
                )

                (square.isLightSquare ? lightColor : darkColor).setFill()
                cg.fill(sqRect)

                if let lm = latestLastMove, lm.from == square || lm.to == square {
                    UIColor(red: 0.96, green: 0.94, blue: 0.32, alpha: 0.34).setFill()
                    cg.fill(sqRect)
                }

                if showBestHighlights, let best = primary?.bestMove {
                    if best.from == square {
                        UIColor(red: 0.35, green: 0.88, blue: 0.42, alpha: 0.35).setFill()
                        cg.fill(sqRect)
                    } else if !latestCoachPieceOnlyMode && best.to == square {
                        UIColor(red: 0.35, green: 0.88, blue: 0.42, alpha: 0.48).setFill()
                        cg.fill(sqRect)
                    }
                }

                let piece = latestBoard.squares[boardRow][boardCol]
                let isCheckedKingSq = (piece?.type == .king && piece?.color == checkedColor)
                if isCheckedKingSq {
                    UIColor(red: 0.96, green: 0.22, blue: 0.24, alpha: 0.58).setFill()
                    cg.fill(sqRect)
                    UIColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 0.95).setStroke()
                    let checkBorder = UIBezierPath(rect: sqRect.insetBy(dx: 1.5, dy: 1.5))
                    checkBorder.lineWidth = 2.5
                    checkBorder.stroke()
                }

                let labelColor = square.isLightSquare ? darkColor : lightColor
                if screenCol == 0 {
                    NSString(string: "\(8 - boardRow)").draw(
                        at: CGPoint(x: sqRect.minX + 2.5, y: sqRect.minY + 1.5),
                        withAttributes: [
                            .font: UIFont.systemFont(ofSize: max(9, cellSize * 0.22), weight: .bold),
                            .foregroundColor: labelColor
                        ]
                    )
                }
                if screenRow == 7 {
                    let fileAttr: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: max(9, cellSize * 0.22), weight: .bold),
                        .foregroundColor: labelColor
                    ]
                    let fileText = NSString(string: files[boardCol])
                    let fSize = fileText.size(withAttributes: fileAttr)
                    fileText.draw(
                        at: CGPoint(x: sqRect.maxX - fSize.width - 2.5, y: sqRect.maxY - fSize.height - 1.0),
                        withAttributes: fileAttr
                    )
                }

                if let piece {
                    drawPieceGlyph(piece, in: sqRect)
                }

                if isCheckedKingSq {
                    let chkRect = CGRect(x: sqRect.maxX - 28, y: sqRect.minY + 1.5, width: 26.5, height: 12.5)
                    UIColor(red: 0.90, green: 0.14, blue: 0.18, alpha: 0.95).setFill()
                    UIBezierPath(roundedRect: chkRect, cornerRadius: 3).fill()
                    let chkStyle = NSMutableParagraphStyle()
                    chkStyle.alignment = .center
                    NSString(string: "將軍").draw(
                        in: CGRect(x: chkRect.minX, y: chkRect.minY + 0.5, width: chkRect.width, height: 11.5),
                        withAttributes: [
                            .font: UIFont.systemFont(ofSize: 8.5, weight: .heavy),
                            .foregroundColor: UIColor.white,
                            .paragraphStyle: chkStyle
                        ]
                    )
                }
            }
        }

        // Overlay Arrows when allowed
        if !latestIsSafetyLocked && !latestIsWaitingForOpponentReply && latestAutoHint,
           let lines = latestAnalysis?.lines, !lines.isEmpty {
            if latestCoachPieceOnlyMode, let first = lines.first {
                let pt = squareCenter(for: first.bestMove.from, boardOrigin: boardRect.origin, cellSize: cellSize)
                let ringRect = CGRect(
                    x: pt.x - cellSize * 0.42,
                    y: pt.y - cellSize * 0.42,
                    width: cellSize * 0.84,
                    height: cellSize * 0.84
                )
                UIColor(red: 0.35, green: 0.90, blue: 0.44, alpha: 0.95).setStroke()
                let ring = UIBezierPath(ovalIn: ringRect)
                ring.lineWidth = max(3.5, cellSize * 0.08)
                ring.stroke()
            } else {
                let arrowColors: [Int: UIColor] = [
                    1: UIColor(red: 0.30, green: 0.90, blue: 0.42, alpha: 0.92),
                    2: UIColor(red: 0.22, green: 0.78, blue: 0.96, alpha: 0.78),
                    3: UIColor(red: 0.98, green: 0.72, blue: 0.22, alpha: 0.74)
                ]
                for line in lines.prefix(3).reversed() {
                    let color = arrowColors[line.multipvIndex] ?? UIColor.systemOrange
                    let width: CGFloat = line.multipvIndex == 1 ? max(7.0, cellSize * 0.21) : max(4.5, cellSize * 0.13)
                    drawArrow(
                        from: line.bestMove.from,
                        to: line.bestMove.to,
                        boardOrigin: boardRect.origin,
                        cellSize: cellSize,
                        color: color,
                        lineWidth: width,
                        isDashed: false,
                        rankBadge: lines.count > 1 ? "\(line.multipvIndex)" : nil,
                        in: cg
                    )
                }

                if latestShowOpponentReplyArrow, let reply = lines.first?.predictedOpponentReply {
                    drawArrow(
                        from: reply.from,
                        to: reply.to,
                        boardOrigin: boardRect.origin,
                        cellSize: cellSize,
                        color: UIColor(red: 1.0, green: 0.32, blue: 0.36, alpha: 0.88),
                        lineWidth: max(4.5, cellSize * 0.13),
                        isDashed: true,
                        rankBadge: "敵",
                        in: cg
                    )
                }

                if showCoordinateBadgesOnPrimary, let first = lines.first {
                    drawSquareCoordinateBadge(
                        text: "起:\(first.bestMove.from.algebraic)",
                        square: first.bestMove.from,
                        boardOrigin: boardRect.origin,
                        cellSize: cellSize,
                        fillColor: UIColor(red: 0.12, green: 0.45, blue: 0.22, alpha: 0.92)
                    )
                    drawSquareCoordinateBadge(
                        text: "落:\(first.bestMove.to.algebraic)",
                        square: first.bestMove.to,
                        boardOrigin: boardRect.origin,
                        cellSize: cellSize,
                        fillColor: UIColor(red: 0.14, green: 0.60, blue: 0.28, alpha: 0.95)
                    )
                }
            }
        }

        cg.restoreGState()

        UIColor(white: 1.0, alpha: 0.18).setStroke()
        let boardOutline = UIBezierPath(roundedRect: boardRect, cornerRadius: 8)
        boardOutline.lineWidth = 1.5
        boardOutline.stroke()
    }

    private func squareCenter(for square: BoardSquare, boardOrigin: CGPoint, cellSize: CGFloat) -> CGPoint {
        let screenCol = latestPerspective == .white ? square.col : (7 - square.col)
        let screenRow = latestPerspective == .white ? square.row : (7 - square.row)
        return CGPoint(
            x: boardOrigin.x + (CGFloat(screenCol) + 0.5) * cellSize,
            y: boardOrigin.y + (CGFloat(screenRow) + 0.5) * cellSize
        )
    }

    private func drawPieceGlyph(_ piece: ChessPiece, in rect: CGRect) {
        let glyph = piece.solidUnicode as NSString
        let fontSize = rect.width * 0.78
        let font = UIFont.systemFont(ofSize: fontSize, weight: .regular)

        let textSize = glyph.size(withAttributes: [.font: font])
        let origin = CGPoint(
            x: rect.midX - textSize.width / 2.0,
            y: rect.midY - textSize.height / 2.0
        )

        if piece.color == .white {
            let strokeAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor(red: 0.99, green: 0.99, blue: 0.97, alpha: 1.0),
                .strokeColor: UIColor(white: 0.10, alpha: 1.0),
                .strokeWidth: -4.2
            ]
            glyph.draw(at: origin, withAttributes: strokeAttrs)
        } else {
            let rimAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1.0),
                .strokeColor: UIColor(white: 0.95, alpha: 0.45),
                .strokeWidth: -2.2
            ]
            glyph.draw(at: origin, withAttributes: rimAttrs)
        }
    }

    private func drawArrow(
        from: BoardSquare,
        to: BoardSquare,
        boardOrigin: CGPoint,
        cellSize: CGFloat,
        color: UIColor,
        lineWidth: CGFloat,
        isDashed: Bool,
        rankBadge: String?,
        in cg: CGContext
    ) {
        let p0 = squareCenter(for: from, boardOrigin: boardOrigin, cellSize: cellSize)
        let p1 = squareCenter(for: to, boardOrigin: boardOrigin, cellSize: cellSize)
        let dx = p1.x - p0.x
        let dy = p1.y - p0.y
        let length = hypot(dx, dy)
        guard length > 4 else { return }

        let ux = dx / length
        let uy = dy / length
        let headLength = lineWidth * 2.25
        let headHalfWidth = lineWidth * 1.28

        let shaftStart = CGPoint(x: p0.x + ux * (lineWidth * 0.55), y: p0.y + uy * (lineWidth * 0.55))
        let shaftEnd = CGPoint(x: p1.x - ux * (headLength * 0.70), y: p1.y - uy * (headLength * 0.70))

        cg.saveGState()
        color.setStroke()
        cg.setLineWidth(lineWidth)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        if isDashed {
            cg.setLineDash(phase: 0, lengths: [max(5, lineWidth * 1.15), max(4, lineWidth * 0.95)])
        }
        cg.move(to: shaftStart)
        cg.addLine(to: shaftEnd)
        cg.strokePath()
        cg.restoreGState()

        let perpX = -uy
        let perpY = ux
        let baseCenter = CGPoint(x: p1.x - ux * headLength, y: p1.y - uy * headLength)
        let leftWing = CGPoint(x: baseCenter.x + perpX * headHalfWidth, y: baseCenter.y + perpY * headHalfWidth)
        let rightWing = CGPoint(x: baseCenter.x - perpX * headHalfWidth, y: baseCenter.y - perpY * headHalfWidth)

        let headPath = UIBezierPath()
        headPath.move(to: p1)
        headPath.addLine(to: leftWing)
        headPath.addLine(to: rightWing)
        headPath.close()
        color.setFill()
        headPath.fill()

        if let rankBadge {
            let badgeCenter = CGPoint(x: p0.x + ux * (length * 0.36), y: p0.y + uy * (length * 0.36))
            let radius: CGFloat = max(8.0, lineWidth * 0.92)
            let circleRect = CGRect(
                x: badgeCenter.x - radius,
                y: badgeCenter.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            UIColor(red: 0.08, green: 0.10, blue: 0.12, alpha: 0.95).setFill()
            UIBezierPath(ovalIn: circleRect).fill()
            color.setStroke()
            let ring = UIBezierPath(ovalIn: circleRect)
            ring.lineWidth = 1.5
            ring.stroke()

            let centerStyle = NSMutableParagraphStyle()
            centerStyle.alignment = .center
            let badgeFont = UIFont.systemFont(ofSize: radius * 1.1, weight: .heavy)
            NSString(string: rankBadge).draw(
                in: CGRect(
                    x: circleRect.minX,
                    y: circleRect.midY - badgeFont.lineHeight / 2.0,
                    width: circleRect.width,
                    height: badgeFont.lineHeight
                ),
                withAttributes: [
                    .font: badgeFont,
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: centerStyle
                ]
            )
        }
    }

    private func drawSquareCoordinateBadge(
        text: String,
        square: BoardSquare,
        boardOrigin: CGPoint,
        cellSize: CGFloat,
        fillColor: UIColor
    ) {
        let screenCol = latestPerspective == .white ? square.col : (7 - square.col)
        let screenRow = latestPerspective == .white ? square.row : (7 - square.row)
        let sqOrigin = CGPoint(
            x: boardOrigin.x + CGFloat(screenCol) * cellSize,
            y: boardOrigin.y + CGFloat(screenRow) * cellSize
        )
        let badgeW = min(cellSize - 4, 42)
        let badgeRect = CGRect(x: sqOrigin.x + 2, y: sqOrigin.y + 2, width: badgeW, height: 15)
        fillColor.setFill()
        UIBezierPath(roundedRect: badgeRect, cornerRadius: 4).fill()

        let centerStyle = NSMutableParagraphStyle()
        centerStyle.alignment = .center
        NSString(string: text).draw(
            in: CGRect(x: badgeRect.minX + 1, y: badgeRect.minY + 1, width: badgeRect.width - 2, height: 13),
            withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 9.5, weight: .heavy),
                .foregroundColor: UIColor.white,
                .paragraphStyle: centerStyle
            ]
        )
    }

    // MARK: - HUD Drawing Helpers

    private func drawCard(_ rect: CGRect, fill: UIColor, border: UIColor) {
        fill.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
        border.setStroke()
        let outline = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        outline.lineWidth = 1.4
        outline.stroke()
    }

    private func drawStatusPill(rect: CGRect, text: String, color: UIColor) {
        color.withAlphaComponent(0.16).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 7).fill()
        color.withAlphaComponent(0.58).setStroke()
        let border = UIBezierPath(roundedRect: rect, cornerRadius: 7)
        border.lineWidth = 1.2
        border.stroke()

        let center = NSMutableParagraphStyle()
        center.alignment = .center
        NSString(string: text).draw(
            in: CGRect(x: rect.minX + 3, y: rect.minY + 3, width: rect.width - 6, height: 16),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 11.5, weight: .heavy),
                .foregroundColor: color,
                .paragraphStyle: center
            ]
        )
    }

    private func drawWDLBar(rect: CGRect, wdl: (win: Int, draw: Int, loss: Int), in cg: CGContext) {
        let winW = rect.width * CGFloat(wdl.win) / 100.0
        let drawW = rect.width * CGFloat(wdl.draw) / 100.0
        let lossW = max(0, rect.width - winW - drawW)
        cg.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2.0).addClip()
        UIColor(red: 0.30, green: 0.86, blue: 0.44, alpha: 1.0).setFill()
        cg.fill(CGRect(x: rect.minX, y: rect.minY, width: winW, height: rect.height))
        UIColor(white: 0.48, alpha: 1.0).setFill()
        cg.fill(CGRect(x: rect.minX + winW, y: rect.minY, width: drawW, height: rect.height))
        UIColor(red: 0.92, green: 0.34, blue: 0.38, alpha: 1.0).setFill()
        cg.fill(CGRect(x: rect.minX + winW + drawW, y: rect.minY, width: lossW, height: rect.height))
        cg.restoreGState()
    }

    private func drawFooterStrip(rect: CGRect, defaultText: String) {
        if pipBannerText != nil {
            UIColor(red: 0.16, green: 0.34, blue: 0.22, alpha: 0.95).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 7).fill()
        }
        let footerPara = NSMutableParagraphStyle()
        footerPara.alignment = .center
        footerPara.lineBreakMode = .byTruncatingTail
        NSString(string: pipBannerText ?? defaultText).draw(
            in: CGRect(x: rect.minX + 6, y: rect.minY + 3, width: rect.width - 12, height: 18),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 12.5, weight: .bold),
                .foregroundColor: pipBannerText != nil
                    ? UIColor(red: 0.62, green: 0.98, blue: 0.68, alpha: 1.0)
                    : UIColor(white: 0.74, alpha: 1.0),
                .paragraphStyle: footerPara
            ]
        )
    }

    private func winRateColor(_ winPct: Int) -> UIColor {
        if winPct >= 52 {
            return UIColor(red: 0.35, green: 0.92, blue: 0.48, alpha: 1.0)
        } else if winPct >= 44 {
            return UIColor(red: 0.98, green: 0.82, blue: 0.32, alpha: 1.0)
        } else {
            return UIColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1.0)
        }
    }

    private func resolveCurrentStatusTuple() -> (title: String, color: UIColor) {
        if latestIsSafetyLocked {
            return ("[安全鎖定]", UIColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1.0))
        } else if latestIsKingInCheck {
            return ("[國王將軍]", UIColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1.0))
        } else if latestPinnedCount > 0 {
            return ("[牽制×\(latestPinnedCount)]", UIColor(red: 1.0, green: 0.68, blue: 0.25, alpha: 1.0))
        } else if latestIsWaitingForOpponentReply {
            return ("[等待對手]", UIColor(red: 0.36, green: 0.84, blue: 0.98, alpha: 1.0))
        } else if latestPaceRemainingSeconds > 0 {
            return ("[停頓 \(latestPaceRemainingSeconds)s]", UIColor(red: 0.98, green: 0.82, blue: 0.34, alpha: 1.0))
        } else {
            return ("[輪到我方]", UIColor(red: 0.42, green: 0.92, blue: 0.54, alpha: 1.0))
        }
    }

    // MARK: - PixelBuffer & SampleBuffer Conversion

    private func makePixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height

        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        guard let ctx = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private func makeSampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDesc: CMVideoFormatDescription?
        let fmtStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc
        )
        guard fmtStatus == noErr, let videoFormat = formatDesc else { return nil }

        let elapsed = max(0.0, CACurrentMediaTime() - startTime)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 2),
            presentationTimeStamp: CMTime(seconds: elapsed, preferredTimescale: 600),
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let sbStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: videoFormat,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sbStatus == noErr, let buffer = sampleBuffer else { return nil }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: true) {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        return buffer
    }
}

struct PiPBufferHostView: UIViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> PiPLayerContainerView {
        let view = PiPLayerContainerView()
        view.attach(layer: displayLayer)
        return view
    }

    func updateUIView(_ uiView: PiPLayerContainerView, context: Context) {
        uiView.attach(layer: displayLayer)
    }
}

final class PiPLayerContainerView: UIView {
    private weak var attachedLayer: AVSampleBufferDisplayLayer?

    func attach(layer: AVSampleBufferDisplayLayer) {
        if attachedLayer !== layer {
            attachedLayer?.removeFromSuperlayer()
            layer.frame = bounds
            self.layer.addSublayer(layer)
            attachedLayer = layer
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachedLayer?.frame = bounds
    }
}
