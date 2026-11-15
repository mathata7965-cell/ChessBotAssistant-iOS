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
    private var latestBoardTheme: BoardTheme = .glacierBlue
    private var latestIsKingInCheck: Bool = false
    private var latestPinnedCount: Int = 0
    private var latestIsWaitingForOpponentReply: Bool = false
    private var latestIsBoardDetected: Bool = false
    private var latestIsAnalyzing: Bool = false
    private var latestPaceRemainingSeconds: Int = 0
    private var latestStealthSafetyScore: Int = 90
    private var latestPinnedSummary: String = ""
    private var latestLastKnownWinPct: Int = 50
    private var latestLastKnownWDL: (win: Int, draw: Int, loss: Int) = (38, 24, 38)
    private var latestLastKnownEvalStr: String = "0.00"
    private var contentRevision: UInt64 = 0
    private var renderedRevision: UInt64 = 0
    private var cachedPixelBuffer: CVPixelBuffer?

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
        isAnalyzing: Bool = false,
        paceRemainingSeconds: Int = 0,
        stealthSafetyScore: Int = 90,
        pinnedSummary: String = "",
        lastKnownWinPct: Int = 50,
        lastKnownWDL: (win: Int, draw: Int, loss: Int) = (38, 24, 38),
        lastKnownEvalStr: String = "0.00"
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
        self.latestBoardTheme = boardTheme
        self.latestIsKingInCheck = isKingInCheck
        self.latestPinnedCount = pinnedCount
        self.latestIsWaitingForOpponentReply = isWaitingForOpponentReply
        self.latestIsBoardDetected = isBoardDetected
        self.latestIsAnalyzing = isAnalyzing
        self.latestPaceRemainingSeconds = paceRemainingSeconds
        self.latestStealthSafetyScore = stealthSafetyScore
        self.latestPinnedSummary = pinnedSummary
        self.latestLastKnownWinPct = lastKnownWinPct
        self.latestLastKnownWDL = lastKnownWDL
        self.latestLastKnownEvalStr = lastKnownEvalStr
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

    // MARK: - HUD Frame Renderer (720 x 440 Board-Free Tactical & Win-Rate HUD)

    private func renderPiPHUDImage() -> UIImage {
        let canvasSize = CGSize(width: 720, height: 440)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext

            // Background
            UIColor(red: 0.075, green: 0.095, blue: 0.125, alpha: 1.0).setFill()
            cg.fill(CGRect(origin: .zero, size: canvasSize))

            let netLabel = latestZeroNetworkMode ? "[離線引擎 10MB]" : "[雲端混合]"
            let syncLabel = latestAutoSyncActive ? "[實時監聽中]" : "[手動掃描]"

            guard latestIsBoardDetected else {
                // Waiting for Board Detection Full-Screen HUD
                let waitRect = CGRect(x: 24, y: 20, width: 672, height: 400)
                UIColor(red: 0.11, green: 0.145, blue: 0.195, alpha: 1.0).setFill()
                UIBezierPath(roundedRect: waitRect, cornerRadius: 16).fill()
                UIColor(red: 0.28, green: 0.72, blue: 0.92, alpha: 0.38).setStroke()
                let border = UIBezierPath(roundedRect: waitRect, cornerRadius: 16)
                border.lineWidth = 2.0
                border.stroke()

                let brandAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 15, weight: .heavy),
                    .foregroundColor: UIColor(red: 0.50, green: 0.88, blue: 0.45, alpha: 1.0)
                ]
                NSString(string: "[CHESS BOT 輔助大師]").draw(
                    at: CGPoint(x: 42, y: 38),
                    withAttributes: brandAttr
                )

                let rightStyle = NSMutableParagraphStyle()
                rightStyle.alignment = .right
                let topRightAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13.5, weight: .bold),
                    .foregroundColor: UIColor(red: 0.36, green: 0.84, blue: 0.98, alpha: 1.0),
                    .paragraphStyle: rightStyle
                ]
                NSString(string: "\(syncLabel) · \(netLabel) · 防封 \(latestStealthSafetyScore)%").draw(
                    in: CGRect(x: 280, y: 38, width: 396, height: 22),
                    withAttributes: topRightAttr
                )

                let centerStyle = NSMutableParagraphStyle()
                centerStyle.alignment = .center

                let titleAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 42, weight: .heavy),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: centerStyle
                ]
                NSString(string: "等待偵測棋盤").draw(
                    in: CGRect(x: 40, y: 136, width: 640, height: 54),
                    withAttributes: titleAttr
                )

                let subAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                    .foregroundColor: UIColor(red: 0.36, green: 0.84, blue: 0.98, alpha: 1.0),
                    .paragraphStyle: centerStyle
                ]
                NSString(string: "請切換至 Chess.com 對局畫面（螢幕直播或截圖自動識別）").draw(
                    in: CGRect(x: 44, y: 204, width: 632, height: 30),
                    withAttributes: subAttr
                )

                let featAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14.5, weight: .medium),
                    .foregroundColor: UIColor(white: 0.72, alpha: 1.0),
                    .paragraphStyle: centerStyle
                ]
                NSString(string: "偵測到棋盤後將直接顯示：我方勝率 · 勝/和/負比例 · 最佳走法座標 · 戰術解析").draw(
                    in: CGRect(x: 44, y: 254, width: 632, height: 28),
                    withAttributes: featAttr
                )

                let bottomStrip = CGRect(x: 40, y: 376, width: 640, height: 30)
                if pipBannerText != nil {
                    UIColor(red: 0.16, green: 0.34, blue: 0.22, alpha: 0.95).setFill()
                    UIBezierPath(roundedRect: bottomStrip, cornerRadius: 8).fill()
                }
                let bottomAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13.5, weight: .bold),
                    .foregroundColor: pipBannerText != nil
                        ? UIColor(red: 0.62, green: 0.98, blue: 0.68, alpha: 1.0)
                        : UIColor(white: 0.76, alpha: 1.0),
                    .paragraphStyle: centerStyle
                ]
                NSString(string: pipBannerText ?? "[播放鍵：立即讀取截圖]   [快轉鍵：換步/掃描]   [倒轉鍵：重置]").draw(
                    in: CGRect(x: bottomStrip.minX + 6, y: bottomStrip.minY + 5, width: bottomStrip.width - 12, height: 22),
                    withAttributes: bottomAttr
                )
                return
            }

            // Tier 1: Full-Width Win-Rate & WDL Header (x: 24, y: 18, w: 672, h: 110)
            let headerRect = CGRect(x: 24, y: 18, width: 672, height: 110)
            UIColor(red: 0.115, green: 0.155, blue: 0.205, alpha: 1.0).setFill()
            UIBezierPath(roundedRect: headerRect, cornerRadius: 14).fill()
            UIColor(white: 1.0, alpha: 0.10).setStroke()
            let headerBorder = UIBezierPath(roundedRect: headerRect, cornerRadius: 14)
            headerBorder.lineWidth = 1.5
            headerBorder.stroke()

            let primary = latestAnalysis?.primaryLine
            let winPct = primary.map { Int($0.winProbability(for: latestPerspective).rounded()) } ?? latestLastKnownWinPct
            let wdl = primary?.wdlBreakdown(for: latestPerspective) ?? latestLastKnownWDL
            let evalStr = primary?.formattedScore ?? latestLastKnownEvalStr
            let campShort = latestPerspective == .white ? "執白" : "執黑"
            let depthText = latestAnalysis.map { "D\($0.depthReached)" } ?? (latestIsAnalyzing ? "計算中" : "待機")

            // Left block: Huge Win Rate %
            let winTitleAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13.5, weight: .bold),
                .foregroundColor: UIColor(red: 0.36, green: 0.84, blue: 0.98, alpha: 1.0)
            ]
            NSString(string: "我方(\(campShort))勝率").draw(at: CGPoint(x: 40, y: 27), withAttributes: winTitleAttr)

            let winColor: UIColor = winPct >= 52
                ? UIColor(red: 0.35, green: 0.92, blue: 0.48, alpha: 1.0)
                : (winPct >= 44 ? UIColor(red: 0.98, green: 0.82, blue: 0.32, alpha: 1.0) : UIColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1.0))
            let hugeWinAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 44, weight: .heavy),
                .foregroundColor: winColor
            ]
            NSString(string: "\(winPct)%").draw(at: CGPoint(x: 40, y: 50), withAttributes: hugeWinAttr)

            // Middle block: Eval + WDL % + 3-Color WDL Bar + Opening/Depth
            let evalTitleAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .heavy),
                .foregroundColor: UIColor.white
            ]
            NSString(string: "評估 \(evalStr)").draw(at: CGPoint(x: 218, y: 26), withAttributes: evalTitleAttr)

            let depthBadgeAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .bold),
                .foregroundColor: UIColor(red: 0.50, green: 0.88, blue: 0.48, alpha: 1.0)
            ]
            NSString(string: depthText).draw(at: CGPoint(x: 454, y: 31), withAttributes: depthBadgeAttr)

            let wdlTextAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold),
                .foregroundColor: UIColor(white: 0.92, alpha: 1.0)
            ]
            NSString(string: "勝 \(wdl.win)%   和 \(wdl.draw)%   負 \(wdl.loss)%").draw(at: CGPoint(x: 218, y: 57), withAttributes: wdlTextAttr)

            // 3-color WDL bar
            let barTotalW: CGFloat = 290
            let barX: CGFloat = 218
            let barY: CGFloat = 80
            let barH: CGFloat = 12
            let winW = barTotalW * CGFloat(wdl.win) / 100.0
            let drawW = barTotalW * CGFloat(wdl.draw) / 100.0
            let lossW = max(0, barTotalW - winW - drawW)
            cg.saveGState()
            UIBezierPath(roundedRect: CGRect(x: barX, y: barY, width: barTotalW, height: barH), cornerRadius: 6).addClip()
            UIColor(red: 0.30, green: 0.86, blue: 0.44, alpha: 1.0).setFill()
            cg.fill(CGRect(x: barX, y: barY, width: winW, height: barH))
            UIColor(white: 0.48, alpha: 1.0).setFill()
            cg.fill(CGRect(x: barX + winW, y: barY, width: drawW, height: barH))
            UIColor(red: 0.92, green: 0.34, blue: 0.38, alpha: 1.0).setFill()
            cg.fill(CGRect(x: barX + winW + drawW, y: barY, width: lossW, height: barH))
            cg.restoreGState()

            let openText = latestOpeningName.isEmpty ? "即時戰術分析中" : latestOpeningName
            let openAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12.5, weight: .semibold),
                .foregroundColor: UIColor(white: 0.72, alpha: 1.0)
            ]
            NSString(string: openText).draw(in: CGRect(x: 218, y: 98, width: 294, height: 18), withAttributes: openAttr)

            // Right Status Box (x: 526, y: 28, w: 156, h: 90)
            let statusBox = CGRect(x: 526, y: 28, width: 156, height: 90)
            let statusTitle: String
            let statusSub: String
            let statusColor: UIColor
            if latestIsSafetyLocked {
                statusTitle = "[安全鎖定]"
                statusSub = "疑似計時對局"
                statusColor = UIColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1.0)
            } else if latestIsKingInCheck {
                statusTitle = "[國王被將軍]"
                statusSub = "必須優先解將"
                statusColor = UIColor(red: 1.0, green: 0.42, blue: 0.42, alpha: 1.0)
            } else if latestPinnedCount > 0 {
                statusTitle = "[護王牽制×\(latestPinnedCount)]"
                statusSub = "勿動被牽制子"
                statusColor = UIColor(red: 1.0, green: 0.68, blue: 0.25, alpha: 1.0)
            } else if latestIsWaitingForOpponentReply {
                statusTitle = "[等待對手]"
                statusSub = "回子後自動算"
                statusColor = UIColor(red: 0.36, green: 0.84, blue: 0.98, alpha: 1.0)
            } else if latestPaceRemainingSeconds > 0 {
                statusTitle = "[防封節奏]"
                statusSub = "建議停頓 \(latestPaceRemainingSeconds)s"
                statusColor = UIColor(red: 0.98, green: 0.82, blue: 0.34, alpha: 1.0)
            } else {
                statusTitle = "[輪到我方]"
                statusSub = "安全節奏就緒"
                statusColor = UIColor(red: 0.42, green: 0.92, blue: 0.54, alpha: 1.0)
            }

            statusColor.withAlphaComponent(0.15).setFill()
            UIBezierPath(roundedRect: statusBox, cornerRadius: 11).fill()
            statusColor.withAlphaComponent(0.55).setStroke()
            let statusBorder = UIBezierPath(roundedRect: statusBox, cornerRadius: 11)
            statusBorder.lineWidth = 1.5
            statusBorder.stroke()

            let stCenter = NSMutableParagraphStyle()
            stCenter.alignment = .center
            NSString(string: statusTitle).draw(
                in: CGRect(x: statusBox.minX + 6, y: statusBox.minY + 18, width: statusBox.width - 12, height: 24),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 15, weight: .heavy),
                    .foregroundColor: statusColor,
                    .paragraphStyle: stCenter
                ]
            )
            NSString(string: statusSub).draw(
                in: CGRect(x: statusBox.minX + 6, y: statusBox.minY + 50, width: statusBox.width - 12, height: 22),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: stCenter
                ]
            )

            // Tier 2: Full-Width Primary Move Command Card (x: 24, y: 138, w: 672, h: 152)
            let mainCard = CGRect(x: 24, y: 138, width: 672, height: 152)
            if latestIsSafetyLocked {
                UIColor(red: 0.28, green: 0.10, blue: 0.11, alpha: 1.0).setFill()
                UIBezierPath(roundedRect: mainCard, cornerRadius: 14).fill()
                UIColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 0.85).setStroke()
                let b = UIBezierPath(roundedRect: mainCard, cornerRadius: 14)
                b.lineWidth = 2.0
                b.stroke()

                NSString(string: "[安全鎖定] 疑似計時對局 · 已自動隱藏提示防止誤封").draw(
                    in: CGRect(x: 42, y: 156, width: 636, height: 32),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 20, weight: .heavy),
                        .foregroundColor: UIColor(red: 1.0, green: 0.55, blue: 0.55, alpha: 1.0)
                    ]
                )
                NSString(string: "偵測到倒數計時器且無 Bot 標記。\n若確定為電腦練習賽，請切回主程式點擊「確認為 Bot 對局並解鎖」。").draw(
                    in: CGRect(x: 42, y: 198, width: 636, height: 76),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 15.5, weight: .semibold),
                        .foregroundColor: UIColor.white
                    ]
                )
            } else if latestIsWaitingForOpponentReply {
                UIColor(red: 0.11, green: 0.16, blue: 0.22, alpha: 1.0).setFill()
                UIBezierPath(roundedRect: mainCard, cornerRadius: 14).fill()
                UIColor(red: 0.28, green: 0.72, blue: 0.92, alpha: 0.60).setStroke()
                let b = UIBezierPath(roundedRect: mainCard, cornerRadius: 14)
                b.lineWidth = 1.8
                b.stroke()

                NSString(string: "[已偵測我方走子 · 等待對手落子中]").draw(
                    in: CGRect(x: 42, y: 158, width: 636, height: 32),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 22, weight: .heavy),
                        .foregroundColor: UIColor(red: 0.36, green: 0.84, blue: 0.98, alpha: 1.0)
                    ]
                )
                NSString(string: "畫面穩定鎖定中，避免因對手思考或動畫過渡產生跳幀誤判。\n上方已持續顯示目前我方勝率（\(winPct)%）與局面優勢評估，對手落子穩定後將立即算出最佳反擊。").draw(
                    in: CGRect(x: 42, y: 200, width: 636, height: 76),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 15, weight: .medium),
                        .foregroundColor: UIColor(white: 0.88, alpha: 1.0)
                    ]
                )
            } else if latestIsAnalyzing && primary == nil {
                UIColor(red: 0.12, green: 0.15, blue: 0.20, alpha: 1.0).setFill()
                UIBezierPath(roundedRect: mainCard, cornerRadius: 14).fill()
                UIColor(red: 0.35, green: 0.88, blue: 0.48, alpha: 0.45).setStroke()
                let b = UIBezierPath(roundedRect: mainCard, cornerRadius: 14)
                b.lineWidth = 1.5
                b.stroke()

                NSString(string: "[穩定計算中] 正在分析最佳安全著法...").draw(
                    in: CGRect(x: 42, y: 162, width: 636, height: 34),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 23, weight: .heavy),
                        .foregroundColor: UIColor(red: 0.45, green: 0.92, blue: 0.55, alpha: 1.0)
                    ]
                )
                NSString(string: "採用單次定案策略，避免本地與雲端結果切換造成跳幀；\n計算完成後將直接顯示棋子名稱、螢幕位置座標與戰術原因。").draw(
                    in: CGRect(x: 42, y: 206, width: 636, height: 68),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 15, weight: .medium),
                        .foregroundColor: UIColor(white: 0.84, alpha: 1.0)
                    ]
                )
            } else if !latestAutoHint {
                UIColor(red: 0.12, green: 0.15, blue: 0.19, alpha: 1.0).setFill()
                UIBezierPath(roundedRect: mainCard, cornerRadius: 14).fill()
                NSString(string: "自動建議提示已暫停（僅顯示勝率與局勢評估）").draw(
                    in: CGRect(x: 42, y: 196, width: 636, height: 34),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 19, weight: .bold),
                        .foregroundColor: UIColor(white: 0.80, alpha: 1.0)
                    ]
                )
            } else if let primary {
                UIColor(red: 0.115, green: 0.175, blue: 0.155, alpha: 1.0).setFill()
                UIBezierPath(roundedRect: mainCard, cornerRadius: 14).fill()
                UIColor(red: 0.30, green: 0.88, blue: 0.48, alpha: 0.65).setStroke()
                let b = UIBezierPath(roundedRect: mainCard, cornerRadius: 14)
                b.lineWidth = 2.0
                b.stroke()

                UIColor(red: 0.30, green: 0.88, blue: 0.48, alpha: 1.0).setFill()
                UIBezierPath(roundedRect: CGRect(x: 24, y: 138, width: 8, height: 152), cornerRadius: 4).fill()

                let movingPiece = latestBoard.piece(at: primary.bestMove.from)
                let pieceFullName = movingPiece?.type.fullChineseName ?? "棋子"
                let posHint = "\(primary.bestMove.from.relativePositionHint(for: latestPerspective)) -> \(primary.bestMove.to.relativePositionHint(for: latestPerspective))"
                let reasonText = primary.tacticalReason.isEmpty
                    ? latestBoard.explainMoveTactics(primary.bestMove)
                    : primary.tacticalReason

                // Location badge on right
                let locRect = CGRect(x: 500, y: 150, width: 178, height: 36)
                UIColor(red: 0.14, green: 0.24, blue: 0.30, alpha: 1.0).setFill()
                UIBezierPath(roundedRect: locRect, cornerRadius: 9).fill()
                UIColor(red: 0.32, green: 0.82, blue: 0.98, alpha: 0.50).setStroke()
                UIBezierPath(roundedRect: locRect, cornerRadius: 9).stroke()

                let locStyle = NSMutableParagraphStyle()
                locStyle.alignment = .center
                let locText = latestCoachPieceOnlyMode
                    ? primary.bestMove.from.relativePositionHint(for: latestPerspective)
                    : posHint
                NSString(string: locText).draw(
                    in: CGRect(x: locRect.minX + 6, y: locRect.minY + 8, width: locRect.width - 12, height: 24),
                    withAttributes: [
                        .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .heavy),
                        .foregroundColor: UIColor(red: 0.42, green: 0.88, blue: 1.0, alpha: 1.0),
                        .paragraphStyle: locStyle
                    ]
                )

                if latestCoachPieceOnlyMode {
                    NSString(string: "建議動：\(pieceFullName) (\(primary.bestMove.from.algebraic))").draw(
                        in: CGRect(x: 44, y: 150, width: 444, height: 38),
                        withAttributes: [
                            .font: UIFont.systemFont(ofSize: 28, weight: .heavy),
                            .foregroundColor: UIColor.white
                        ]
                    )
                    NSString(string: "教練半提示模式：僅提示起點位置與戰術方向").draw(
                        in: CGRect(x: 44, y: 202, width: 632, height: 24),
                        withAttributes: [
                            .font: UIFont.systemFont(ofSize: 16.5, weight: .bold),
                            .foregroundColor: UIColor(red: 0.62, green: 0.96, blue: 0.72, alpha: 1.0)
                        ]
                    )
                } else {
                    let movePara = NSMutableParagraphStyle()
                    movePara.lineBreakMode = .byTruncatingTail
                    NSString(string: "#1 \(pieceFullName)  \(primary.bestMove.coordinateDisplay)  [\(primary.bestMove.san)]").draw(
                        in: CGRect(x: 44, y: 150, width: 444, height: 38),
                        withAttributes: [
                            .font: UIFont.systemFont(ofSize: 26, weight: .heavy),
                            .foregroundColor: UIColor.white,
                            .paragraphStyle: movePara
                        ]
                    )

                    let reasonPara = NSMutableParagraphStyle()
                    reasonPara.lineBreakMode = .byTruncatingTail
                    NSString(string: "戰術目的：\(reasonText)").draw(
                        in: CGRect(x: 44, y: 196, width: 634, height: 24),
                        withAttributes: [
                            .font: UIFont.systemFont(ofSize: 16.5, weight: .bold),
                            .foregroundColor: UIColor(red: 0.64, green: 0.98, blue: 0.72, alpha: 1.0),
                            .paragraphStyle: reasonPara
                        ]
                    )

                    let replyStr = (latestShowOpponentReplyArrow ? primary.predictedOpponentReply?.san : nil) ?? "-"
                    let contStr = primary.continuationPreview.isEmpty ? "-" : primary.continuationPreview
                    let replyPara = NSMutableParagraphStyle()
                    replyPara.lineBreakMode = .byTruncatingTail
                    NSString(string: "[預測敵應] \(replyStr)   |   續著：\(contStr)").draw(
                        in: CGRect(x: 44, y: 226, width: 634, height: 22),
                        withAttributes: [
                            .font: UIFont.systemFont(ofSize: 14.5, weight: .semibold),
                            .foregroundColor: UIColor(white: 0.88, alpha: 1.0),
                            .paragraphStyle: replyPara
                        ]
                    )
                }

                let bottomWarn: String
                let bottomWarnColor: UIColor
                if latestIsKingInCheck {
                    bottomWarn = "警示：國王被將軍中！若該子受王受阻，請按「快轉鍵」一鍵換步"
                    bottomWarnColor = UIColor(red: 1.0, green: 0.52, blue: 0.52, alpha: 1.0)
                } else if !latestPinnedSummary.isEmpty {
                    bottomWarn = "護王牽制：\(latestPinnedSummary)（勿隨意移動；受阻按快轉換步）"
                    bottomWarnColor = UIColor(red: 1.0, green: 0.76, blue: 0.36, alpha: 1.0)
                } else if latestHangingCount > 0 {
                    bottomWarn = "提示：目前有 \(latestHangingCount) 枚友子處於威脅格，請注意防守"
                    bottomWarnColor = UIColor(red: 1.0, green: 0.68, blue: 0.40, alpha: 1.0)
                } else {
                    bottomWarn = "防封建議思考 \(latestThinkRange.isEmpty ? "2-4秒" : latestThinkRange) · 來源：\(latestAnalysis?.engineSource ?? "GM庫")"
                    bottomWarnColor = UIColor(white: 0.72, alpha: 1.0)
                }
                let warnPara = NSMutableParagraphStyle()
                warnPara.lineBreakMode = .byTruncatingTail
                NSString(string: bottomWarn).draw(
                    in: CGRect(x: 44, y: 256, width: 634, height: 20),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 13.5, weight: .bold),
                        .foregroundColor: bottomWarnColor,
                        .paragraphStyle: warnPara
                    ]
                )
            } else {
                UIColor(red: 0.12, green: 0.15, blue: 0.19, alpha: 1.0).setFill()
                UIBezierPath(roundedRect: mainCard, cornerRadius: 14).fill()
                NSString(string: "目前無合法著法（對局可能已結束）").draw(
                    in: CGRect(x: 42, y: 196, width: 636, height: 34),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 20, weight: .bold),
                        .foregroundColor: UIColor(white: 0.80, alpha: 1.0)
                    ]
                )
            }

            // Tier 3: Side-by-Side Candidate Moves #2 & #3 (x: 24 & 366, y: 300, w: 330, h: 78)
            let secondaryColors: [UIColor] = [
                UIColor(red: 0.22, green: 0.78, blue: 0.96, alpha: 1.0),
                UIColor(red: 0.98, green: 0.72, blue: 0.22, alpha: 1.0)
            ]
            let candidates = Array((latestAnalysis?.lines ?? []).dropFirst().prefix(2))
            for idx in 0..<2 {
                let cardX: CGFloat = idx == 0 ? 24 : 366
                let cardRect = CGRect(x: cardX, y: 300, width: 330, height: 78)
                UIColor(red: 0.12, green: 0.15, blue: 0.20, alpha: 1.0).setFill()
                UIBezierPath(roundedRect: cardRect, cornerRadius: 12).fill()

                if !latestIsSafetyLocked && !latestIsWaitingForOpponentReply && !latestCoachPieceOnlyMode && latestAutoHint,
                   idx < candidates.count {
                    let line = candidates[idx]
                    let accent = secondaryColors[idx]
                    accent.setFill()
                    UIBezierPath(roundedRect: CGRect(x: cardX, y: 300, width: 6, height: 78), cornerRadius: 3).fill()

                    let pName = latestBoard.piece(at: line.bestMove.from)?.type.displayName ?? "子"
                    let lineWin = Int(line.winProbability(for: latestPerspective).rounded())

                    let topPara = NSMutableParagraphStyle()
                    topPara.lineBreakMode = .byTruncatingTail
                    NSString(string: "#\(idx + 2) \(pName) \(line.bestMove.san)  \(line.bestMove.coordinateDisplay)").draw(
                        in: CGRect(x: cardX + 14, y: 309, width: 200, height: 22),
                        withAttributes: [
                            .font: UIFont.systemFont(ofSize: 15, weight: .heavy),
                            .foregroundColor: UIColor.white,
                            .paragraphStyle: topPara
                        ]
                    )

                    let rightSt = NSMutableParagraphStyle()
                    rightSt.alignment = .right
                    NSString(string: "\(line.formattedScore) · 勝\(lineWin)%").draw(
                        in: CGRect(x: cardX + 206, y: 310, width: 112, height: 20),
                        withAttributes: [
                            .font: UIFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .bold),
                            .foregroundColor: accent,
                            .paragraphStyle: rightSt
                        ]
                    )

                    let subText = line.tacticalReason.isEmpty ? line.continuationPreview : line.tacticalReason
                    let subPara = NSMutableParagraphStyle()
                    subPara.lineBreakMode = .byTruncatingTail
                    NSString(string: subText).draw(
                        in: CGRect(x: cardX + 14, y: 342, width: 304, height: 20),
                        withAttributes: [
                            .font: UIFont.systemFont(ofSize: 12.5, weight: .medium),
                            .foregroundColor: UIColor(white: 0.72, alpha: 1.0),
                            .paragraphStyle: subPara
                        ]
                    )
                } else {
                    let placeholderText = latestIsWaitingForOpponentReply
                        ? "等待對手回棋後自動補充備選線 #\(idx + 2)"
                        : "備選線 #\(idx + 2) 待分析"
                    NSString(string: placeholderText).draw(
                        in: CGRect(x: cardX + 16, y: 328, width: 298, height: 20),
                        withAttributes: [
                            .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                            .foregroundColor: UIColor(white: 0.50, alpha: 1.0)
                        ]
                    )
                }
            }

            // Bottom Footer Strip (y: 388, w: 672, h: 28)
            let footerRect = CGRect(x: 24, y: 388, width: 672, height: 28)
            if pipBannerText != nil {
                UIColor(red: 0.16, green: 0.34, blue: 0.22, alpha: 0.95).setFill()
                UIBezierPath(roundedRect: footerRect, cornerRadius: 7).fill()
            }
            let openShort = latestOpeningName.isEmpty ? "對局中" : latestOpeningName
            let defaultFooter = "[防封 \(latestStealthSafetyScore)%] · \(netLabel) · \(syncLabel) · \(openShort) · [播:掃描 | 快轉:換步]"
            let footerPara = NSMutableParagraphStyle()
            footerPara.lineBreakMode = .byTruncatingTail
            NSString(string: pipBannerText ?? defaultFooter).draw(
                in: CGRect(x: footerRect.minX + 8, y: footerRect.minY + 5, width: footerRect.width - 16, height: 20),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                    .foregroundColor: pipBannerText != nil
                        ? UIColor(red: 0.62, green: 0.98, blue: 0.68, alpha: 1.0)
                        : UIColor(white: 0.74, alpha: 1.0),
                    .paragraphStyle: footerPara
                ]
            )
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
