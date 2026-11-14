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
        pipBannerClearTask?.cancel()
        pipBannerClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.pipBannerText = nil
            self.pushCurrentFrame()
        }
        pushCurrentFrame()
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
        hangingCount: Int = 0
    ) {
        self.latestBoard = board
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
        pushCurrentFrame()
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
                self.pushCurrentFrame()
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

    func pushCurrentFrame() {
        let hudImage = renderPiPHUDImage()
        guard let pixelBuffer = makePixelBuffer(from: hudImage) else { return }
        guard let sampleBuffer = makeSampleBuffer(from: pixelBuffer) else { return }

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

    // MARK: - HUD Frame Renderer (720 x 480)

    private func renderPiPHUDImage() -> UIImage {
        let canvasSize = CGSize(width: 720, height: 480)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext

            // Background
            UIColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1.0).setFill()
            cg.fill(CGRect(origin: .zero, size: canvasSize))

            // 1. Eval bar on far left with PiP safe margin (16 x 420)
            let evalRect = CGRect(x: 24, y: 30, width: 16, height: 420)
            let whiteFrac = CGFloat(latestAnalysis?.evalBarFractionWhite ?? 0.5)
            UIColor(white: 0.15, alpha: 1.0).setFill()
            cg.fill(evalRect)

            let whiteHeight = evalRect.height * whiteFrac
            let whiteFillRect: CGRect
            if latestPerspective == .white {
                whiteFillRect = CGRect(x: evalRect.minX, y: evalRect.maxY - whiteHeight, width: evalRect.width, height: whiteHeight)
            } else {
                whiteFillRect = CGRect(x: evalRect.minX, y: evalRect.minY, width: evalRect.width, height: whiteHeight)
            }
            UIColor(white: 0.94, alpha: 1.0).setFill()
            cg.fill(whiteFillRect)
            UIColor(white: 0.35, alpha: 0.8).setStroke()
            cg.setLineWidth(1.5)
            cg.stroke(evalRect)

            // 2. Mini 8x8 Board with PiP corner-safe margins (420 x 420)
            let boardOrigin = CGPoint(x: 48, y: 30)
            let boardSize: CGFloat = 420
            let cellSize = boardSize / 8.0

            let lightSquareColor = UIColor(red: 0.92, green: 0.93, blue: 0.82, alpha: 1.0)
            let darkSquareColor = UIColor(red: 0.46, green: 0.59, blue: 0.34, alpha: 1.0)
            let bestFromHighlight = UIColor(red: 0.97, green: 0.92, blue: 0.36, alpha: 0.48)
            let bestToHighlight = UIColor(red: 0.35, green: 0.88, blue: 0.45, alpha: 0.45)

            let bestMove = (!latestIsSafetyLocked && latestAutoHint) ? latestAnalysis?.primaryLine?.bestMove : nil

            for screenRow in 0..<8 {
                for screenCol in 0..<8 {
                    let boardRow = latestPerspective == .white ? screenRow : (7 - screenRow)
                    let boardCol = latestPerspective == .white ? screenCol : (7 - screenCol)
                    let sqRect = CGRect(
                        x: boardOrigin.x + CGFloat(screenCol) * cellSize,
                        y: boardOrigin.y + CGFloat(screenRow) * cellSize,
                        width: cellSize,
                        height: cellSize
                    )

                    let isLight = (boardRow + boardCol) % 2 == 0
                    (isLight ? lightSquareColor : darkSquareColor).setFill()
                    cg.fill(sqRect)

                    if let bm = bestMove {
                        if bm.from.row == boardRow && bm.from.col == boardCol {
                            bestFromHighlight.setFill()
                            cg.fill(sqRect)
                        } else if !latestCoachPieceOnlyMode && bm.to.row == boardRow && bm.to.col == boardCol {
                            bestToHighlight.setFill()
                            cg.fill(sqRect)
                        }
                    }

                    if let piece = latestBoard.squares[boardRow][boardCol] {
                        drawPieceGlyph(piece, in: sqRect)
                    }
                }
            }

            // 3. Multi-PV Arrows on Mini Board (suppressed when safety locked or in coach piece-only mode)
            if !latestIsSafetyLocked && !latestCoachPieceOnlyMode && latestAutoHint, let lines = latestAnalysis?.lines {
                let arrowColors: [UIColor] = [
                    UIColor(red: 0.25, green: 0.88, blue: 0.48, alpha: 0.92),
                    UIColor(red: 0.22, green: 0.78, blue: 0.96, alpha: 0.78),
                    UIColor(red: 0.98, green: 0.72, blue: 0.22, alpha: 0.72)
                ]
                for (origIndex, line) in lines.prefix(3).enumerated().reversed() {
                    let color = arrowColors[origIndex]
                    let strokeW: CGFloat = origIndex == 0 ? 8.5 : 5.5
                    drawArrow(
                        from: line.bestMove.from,
                        to: line.bestMove.to,
                        boardOrigin: boardOrigin,
                        cellSize: cellSize,
                        color: color,
                        lineWidth: strokeW,
                        isDashed: false,
                        in: cg
                    )
                }

                if latestShowOpponentReplyArrow,
                   let reply = lines.first?.predictedOpponentReply {
                    drawArrow(
                        from: reply.from,
                        to: reply.to,
                        boardOrigin: boardOrigin,
                        cellSize: cellSize,
                        color: UIColor(red: 1.0, green: 0.34, blue: 0.38, alpha: 0.90),
                        lineWidth: 5.5,
                        isDashed: true,
                        in: cg
                    )
                }
            }

            // 4. Right Info Panel (x: 484..696)
            let panelX: CGFloat = 484
            let panelW: CGFloat = 212

            if latestIsSafetyLocked {
                let warnBox = CGRect(x: panelX, y: 30, width: panelW, height: 390)
                UIColor(red: 0.28, green: 0.10, blue: 0.11, alpha: 1.0).setFill()
                UIBezierPath(roundedRect: warnBox, cornerRadius: 12).fill()
                UIColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 0.9).setStroke()
                let border = UIBezierPath(roundedRect: warnBox, cornerRadius: 12)
                border.lineWidth = 2
                border.stroke()

                let titleAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 18, weight: .heavy),
                    .foregroundColor: UIColor(red: 1.0, green: 0.55, blue: 0.55, alpha: 1.0)
                ]
                NSString(string: "⚠️ 疑似真人計時賽").draw(in: CGRect(x: panelX + 12, y: 52, width: panelW - 24, height: 32), withAttributes: titleAttr)

                let bodyAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                    .foregroundColor: UIColor.white
                ]
                NSString(string: "已自動鎖定提示防誤封\n\n偵測到倒數計時器且無 Bot 標記。\n\n若確定為電腦練習，請回主視窗點擊「確認為 Bot 對局並解鎖」。").draw(
                    in: CGRect(x: panelX + 12, y: 96, width: panelW - 24, height: 280),
                    withAttributes: bodyAttr
                )
            } else {
                // Header badge
                let badgeRect = CGRect(x: panelX, y: 30, width: panelW, height: 32)
                UIColor(red: 0.16, green: 0.22, blue: 0.28, alpha: 1.0).setFill()
                UIBezierPath(roundedRect: badgeRect, cornerRadius: 8).fill()

                let headerAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13.5, weight: .bold),
                    .foregroundColor: UIColor(red: 0.52, green: 0.88, blue: 0.48, alpha: 1.0)
                ]
                let depthText = latestAnalysis.map { "D\($0.depthReached)" } ?? "..."
                let modeBadge = latestCoachPieceOnlyMode ? "教練模式" : "BOT 輔助"
                NSString(string: "\(modeBadge) • \(depthText)").draw(
                    in: badgeRect.insetBy(dx: 10, dy: 6),
                    withAttributes: headerAttr
                )

                // Camp badge + turn indicator
                let campShort = latestPerspective == .white ? "我執白" : "我執黑"
                let turnText = "\(campShort) • 輪到\(latestBoard.sideToMove.displayName)"
                let turnAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13.5, weight: .bold),
                    .foregroundColor: latestPerspective == .white
                        ? UIColor.white
                        : UIColor(red: 0.56, green: 0.85, blue: 1.0, alpha: 1.0)
                ]
                NSString(string: turnText).draw(at: CGPoint(x: panelX, y: 72), withAttributes: turnAttr)

                let primary = latestAnalysis?.primaryLine
                let evalStr = primary?.formattedScore ?? "0.00"
                let winPct = Int((primary?.winProbability(for: latestPerspective) ?? 50.0).rounded())
                let evalAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: 27, weight: .heavy),
                    .foregroundColor: UIColor.white
                ]
                NSString(string: evalStr).draw(at: CGPoint(x: panelX, y: 94), withAttributes: evalAttr)

                let winAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: UIColor(white: 0.72, alpha: 1.0)
                ]
                NSString(string: "我方勝率 \(winPct)%").draw(at: CGPoint(x: panelX, y: 128), withAttributes: winAttr)

                // Top 3 PV Cards
                let cardColors: [UIColor] = [
                    UIColor(red: 0.25, green: 0.88, blue: 0.48, alpha: 1.0),
                    UIColor(red: 0.22, green: 0.78, blue: 0.96, alpha: 1.0),
                    UIColor(red: 0.98, green: 0.72, blue: 0.22, alpha: 1.0)
                ]

                let lines = Array((latestAnalysis?.lines ?? []).prefix(3))
                for (idx, line) in lines.enumerated() {
                    let cardY = 162 + CGFloat(idx) * 80
                    let cardRect = CGRect(x: panelX, y: cardY, width: panelW, height: 72)
                    UIColor(red: 0.13, green: 0.17, blue: 0.22, alpha: 1.0).setFill()
                    UIBezierPath(roundedRect: cardRect, cornerRadius: 10).fill()

                    cardColors[idx].withAlphaComponent(0.9).setFill()
                    UIBezierPath(roundedRect: CGRect(x: panelX, y: cardY, width: 6, height: 72), cornerRadius: 3).fill()

                    let rankAttr: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 12.5, weight: .bold),
                        .foregroundColor: cardColors[idx]
                    ]
                    NSString(string: "#\(idx + 1) \(line.formattedScore)").draw(
                        at: CGPoint(x: panelX + 14, y: cardY + 7),
                        withAttributes: rankAttr
                    )

                    if latestCoachPieceOnlyMode {
                        let pieceName = latestBoard.piece(at: line.bestMove.from)?.type.displayName ?? "棋子"
                        let hintAttr: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 15.5, weight: .heavy),
                            .foregroundColor: UIColor.white
                        ]
                        NSString(string: "建議動 \(pieceName)").draw(
                            at: CGPoint(x: panelX + 14, y: cardY + 25),
                            withAttributes: hintAttr
                        )

                        let coordAttr: [NSAttributedString.Key: Any] = [
                            .font: UIFont.monospacedSystemFont(ofSize: 12.5, weight: .medium),
                            .foregroundColor: UIColor(white: 0.78, alpha: 1.0)
                        ]
                        NSString(string: "提示起點: \(line.bestMove.from.algebraic)").draw(
                            at: CGPoint(x: panelX + 14, y: cardY + 48),
                            withAttributes: coordAttr
                        )
                    } else {
                        let sanAttr: [NSAttributedString.Key: Any] = [
                            .font: UIFont.monospacedSystemFont(ofSize: 19, weight: .heavy),
                            .foregroundColor: UIColor.white
                        ]
                        NSString(string: line.bestMove.san).draw(
                            at: CGPoint(x: panelX + 14, y: cardY + 24),
                            withAttributes: sanAttr
                        )

                        let coordAttr: [NSAttributedString.Key: Any] = [
                            .font: UIFont.monospacedSystemFont(ofSize: 12.5, weight: .medium),
                            .foregroundColor: UIColor(white: 0.76, alpha: 1.0)
                        ]
                        NSString(string: line.bestMove.coordinateDisplay).draw(
                            at: CGPoint(x: panelX + 14, y: cardY + 48),
                            withAttributes: coordAttr
                        )
                    }
                }
            }

            // Footer
            let netLabel = latestZeroNetworkMode ? "🔒離線" : "🛡️保護"
            let syncLabel = latestAutoSyncActive ? "📸同步" : "⏸手動"
            let extraLabel = latestHangingCount > 0
                ? "⚠️懸子\(latestHangingCount)"
                : (latestThinkRange.isEmpty ? "" : "⏱\(latestThinkRange)")
            let footerText = extraLabel.isEmpty ? "\(netLabel) • \(syncLabel)" : "\(netLabel) • \(syncLabel) • \(extraLabel)"
            let footerAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11.5, weight: .semibold),
                .foregroundColor: latestIsSafetyLocked || latestHangingCount > 0
                    ? UIColor(red: 1.0, green: 0.55, blue: 0.55, alpha: 1.0)
                    : (latestAutoSyncActive
                        ? UIColor(red: 0.45, green: 0.90, blue: 0.58, alpha: 1.0)
                        : UIColor(white: 0.65, alpha: 1.0))
            ]
            NSString(string: footerText).draw(at: CGPoint(x: panelX, y: 422), withAttributes: footerAttr)

            // Bottom status strip / PiP button legend / opening name
            let openingBadge = latestOpeningName.isEmpty ? "⏯掃描 ⏩走步 ⏪悔步" : "📖 \(latestOpeningName) • ⏯掃描"
            let bottomStatusText = pipBannerText ?? openingBadge
            let statusStripRect = CGRect(x: 48, y: 454, width: 648, height: 22)
            if pipBannerText != nil {
                UIColor(red: 0.16, green: 0.34, blue: 0.22, alpha: 0.95).setFill()
                UIBezierPath(roundedRect: statusStripRect, cornerRadius: 6).fill()
            }
            let statusAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13.5, weight: .bold),
                .foregroundColor: pipBannerText != nil
                    ? UIColor(red: 0.62, green: 0.98, blue: 0.68, alpha: 1.0)
                    : UIColor(white: 0.72, alpha: 1.0)
            ]
            NSString(string: bottomStatusText).draw(
                at: CGPoint(x: statusStripRect.minX + 6, y: statusStripRect.minY + 2),
                withAttributes: statusAttr
            )
        }
    }

    private func drawPieceGlyph(_ piece: ChessPiece, in rect: CGRect) {
        let fontSize = rect.height * 0.78
        let fillColor: UIColor = piece.color == .white ? .white : UIColor(white: 0.11, alpha: 1.0)
        let strokeColor: UIColor = piece.color == .white ? UIColor(white: 0.12, alpha: 1.0) : UIColor(white: 0.92, alpha: 0.65)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: fillColor,
            .strokeColor: strokeColor,
            .strokeWidth: piece.color == .white ? -3.0 : -1.5,
            .paragraphStyle: paragraph
        ]
        let textRect = CGRect(x: rect.minX, y: rect.minY + (rect.height - fontSize) * 0.35, width: rect.width, height: fontSize * 1.15)
        NSString(string: piece.solidUnicode).draw(in: textRect, withAttributes: attrs)
    }

    private func drawArrow(
        from: BoardSquare,
        to: BoardSquare,
        boardOrigin: CGPoint,
        cellSize: CGFloat,
        color: UIColor,
        lineWidth: CGFloat,
        isDashed: Bool = false,
        in cg: CGContext
    ) {
        let startScreenCol = latestPerspective == .white ? from.col : (7 - from.col)
        let startScreenRow = latestPerspective == .white ? from.row : (7 - from.row)
        let endScreenCol = latestPerspective == .white ? to.col : (7 - to.col)
        let endScreenRow = latestPerspective == .white ? to.row : (7 - to.row)

        let p0 = CGPoint(
            x: boardOrigin.x + (CGFloat(startScreenCol) + 0.5) * cellSize,
            y: boardOrigin.y + (CGFloat(startScreenRow) + 0.5) * cellSize
        )
        let p1 = CGPoint(
            x: boardOrigin.x + (CGFloat(endScreenCol) + 0.5) * cellSize,
            y: boardOrigin.y + (CGFloat(endScreenRow) + 0.5) * cellSize
        )

        let dx = p1.x - p0.x
        let dy = p1.y - p0.y
        let len = hypot(dx, dy)
        guard len > 1 else { return }

        let ux = dx / len
        let uy = dy / len
        let headLen = lineWidth * 2.5
        let shaftEnd = CGPoint(x: p1.x - ux * headLen * 0.72, y: p1.y - uy * headLen * 0.72)

        cg.saveGState()
        color.setStroke()
        color.setFill()
        cg.setLineWidth(lineWidth)
        cg.setLineCap(.round)
        if isDashed {
            cg.setLineDash(phase: 0, lengths: [lineWidth * 1.4, lineWidth * 1.2])
        }
        cg.move(to: p0)
        cg.addLine(to: shaftEnd)
        cg.strokePath()
        if isDashed {
            cg.setLineDash(phase: 0, lengths: [])
        }

        let perpX = -uy
        let perpY = ux
        let halfHeadW = lineWidth * 1.35

        let headBase = CGPoint(x: p1.x - ux * headLen, y: p1.y - uy * headLen)
        let leftPt = CGPoint(x: headBase.x + perpX * halfHeadW, y: headBase.y + perpY * halfHeadW)
        let rightPt = CGPoint(x: headBase.x - perpX * halfHeadW, y: headBase.y - perpY * halfHeadW)

        cg.move(to: p1)
        cg.addLine(to: leftPt)
        cg.addLine(to: rightPt)
        cg.closePath()
        cg.fillPath()
        cg.restoreGState()
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
