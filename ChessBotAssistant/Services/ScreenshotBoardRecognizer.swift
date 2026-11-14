import Foundation
import UIKit
import Vision

struct RecognizedBoardResult: Sendable {
    let boardState: ChessBoardState
    let croppedBoardPNGData: Data?
    let boardRectNormalized: CGRect
    let detectedPerspective: PieceColor
    let confidence: Double
    let notes: String
    let isLikelyHumanTimedGame: Bool
    let isConfirmedBotMatch: Bool
    let detectedMatchContextNote: String
    let campConfidence: Double
    let campDetectionReason: String
}

final class ScreenshotBoardRecognizer: Sendable {
    static let shared = ScreenshotBoardRecognizer()

    private init() {}

    func recognizeBoard(
        from image: UIImage,
        fallbackPerspective: PieceColor = .white,
        sideToMove: PieceColor? = nil,
        previousBoard: ChessBoardState = .startingPosition,
        forcedPerspective: PieceColor? = nil
    ) async -> RecognizedBoardResult? {
        guard let uprightCG = normalizedCGImage(from: image) else { return nil }
        guard let syncResult = recognizeBoardSync(
            from: uprightCG,
            fallbackPerspective: fallbackPerspective,
            sideToMove: sideToMove,
            previousBoard: previousBoard,
            includePNGCrop: true,
            forcedPerspective: forcedPerspective
        ) else {
            return nil
        }

        let imgW = CGFloat(uprightCG.width)
        let imgH = CGFloat(uprightCG.height)
        let pixelRect = CGRect(
            x: syncResult.boardRectNormalized.minX * imgW,
            y: syncResult.boardRectNormalized.minY * imgH,
            width: syncResult.boardRectNormalized.width * imgW,
            height: syncResult.boardRectNormalized.height * imgH
        ).integral

        var resolvedSync = syncResult
        let clampedCropRect = pixelRect.intersection(CGRect(x: 0, y: 0, width: uprightCG.width, height: uprightCG.height))
        if forcedPerspective == nil,
           let cropped = uprightCG.cropping(to: clampedCropRect),
           let ocrPerspective = await detectBoardPerspective(boardCGImage: cropped) {
            if ocrPerspective != syncResult.detectedPerspective,
               syncResult.campConfidence < 0.78,
               let correctedSync = recognizeBoardSync(
                   from: uprightCG,
                   fallbackPerspective: fallbackPerspective,
                   sideToMove: sideToMove,
                   previousBoard: previousBoard,
                   includePNGCrop: true,
                   forcedPerspective: ocrPerspective
               ) {
                resolvedSync = RecognizedBoardResult(
                    boardState: correctedSync.boardState,
                    croppedBoardPNGData: correctedSync.croppedBoardPNGData,
                    boardRectNormalized: correctedSync.boardRectNormalized,
                    detectedPerspective: correctedSync.detectedPerspective,
                    confidence: correctedSync.confidence,
                    notes: correctedSync.notes,
                    isLikelyHumanTimedGame: correctedSync.isLikelyHumanTimedGame,
                    isConfirmedBotMatch: correctedSync.isConfirmedBotMatch,
                    detectedMatchContextNote: correctedSync.detectedMatchContextNote,
                    campConfidence: 0.92,
                    campDetectionReason: "自動識別（角標 OCR 校驗）：我方執\(ocrPerspective.displayName)"
                )
            } else if ocrPerspective == syncResult.detectedPerspective {
                resolvedSync = RecognizedBoardResult(
                    boardState: syncResult.boardState,
                    croppedBoardPNGData: syncResult.croppedBoardPNGData,
                    boardRectNormalized: syncResult.boardRectNormalized,
                    detectedPerspective: syncResult.detectedPerspective,
                    confidence: syncResult.confidence,
                    notes: syncResult.notes,
                    isLikelyHumanTimedGame: syncResult.isLikelyHumanTimedGame,
                    isConfirmedBotMatch: syncResult.isConfirmedBotMatch,
                    detectedMatchContextNote: syncResult.detectedMatchContextNote,
                    campConfidence: max(syncResult.campConfidence, 0.95),
                    campDetectionReason: "自動識別（棋子分群+角標一致）：我方執\(ocrPerspective.displayName)（信心 \(Int(max(syncResult.campConfidence, 0.95) * 100))%）"
                )
            }
        }

        // Analyze surrounding header/footer for Fair-Play human timed match detection (CPU-only Vision)
        let matchContext = await analyzeMatchContext(
            fullCGImage: uprightCG,
            boardPixelRect: pixelRect
        )

        return RecognizedBoardResult(
            boardState: resolvedSync.boardState,
            croppedBoardPNGData: resolvedSync.croppedBoardPNGData,
            boardRectNormalized: resolvedSync.boardRectNormalized,
            detectedPerspective: resolvedSync.detectedPerspective,
            confidence: resolvedSync.confidence,
            notes: resolvedSync.notes,
            isLikelyHumanTimedGame: matchContext.isHumanTimed,
            isConfirmedBotMatch: matchContext.isBot,
            detectedMatchContextNote: matchContext.note,
            campConfidence: resolvedSync.campConfidence,
            campDetectionReason: resolvedSync.campDetectionReason
        )
    }

    func recognizeBoardSync(
        from uprightCG: CGImage,
        fallbackPerspective: PieceColor = .white,
        sideToMove: PieceColor? = nil,
        previousBoard: ChessBoardState = .startingPosition,
        includePNGCrop: Bool = true,
        forcedPerspective: PieceColor? = nil
    ) -> RecognizedBoardResult? {
        let imgW = uprightCG.width
        let imgH = uprightCG.height
        guard imgW >= 120 && imgH >= 120 else { return nil }

        // 1. Locate 8x8 board rectangle in pixel coordinates
        guard let boardPixelRect = locateChessboardRect(in: uprightCG) else {
            return nil
        }

        // Crop board CGImage
        let clampedRect = boardPixelRect.intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))
        guard clampedRect.width >= 80,
              clampedRect.height >= 80,
              let croppedBoard = uprightCG.cropping(to: clampedRect) else {
            return nil
        }

        // 2. Adaptive Two-Cluster Color + Multi-Signal Perspective Detection + 64-cell classification
        let classification = classify64Squares(
            boardCGImage: croppedBoard,
            fallbackPerspective: fallbackPerspective,
            preferredSideToMove: sideToMove,
            previousBoard: previousBoard,
            forcedPerspective: forcedPerspective
        )

        let pngData: Data? = includePNGCrop ? UIImage(cgImage: croppedBoard).pngData() : nil

        let normalizedRect = CGRect(
            x: clampedRect.minX / CGFloat(imgW),
            y: clampedRect.minY / CGFloat(imgH),
            width: clampedRect.width / CGFloat(imgW),
            height: clampedRect.height / CGFloat(imgH)
        )

        return RecognizedBoardResult(
            boardState: classification.board,
            croppedBoardPNGData: pngData,
            boardRectNormalized: normalizedRect,
            detectedPerspective: classification.perspective,
            confidence: classification.confidence,
            notes: classification.notes,
            isLikelyHumanTimedGame: false,
            isConfirmedBotMatch: false,
            detectedMatchContextNote: "純像素即時同步",
            campConfidence: classification.campConfidence,
            campDetectionReason: classification.campReason
        )
    }

    // MARK: - Normalize UIImage to Upright CGImage

    private func normalizedCGImage(from image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage {
            return cg
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let size = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage
    }

    // MARK: - Board Localization (Checkerboard Period-8 Contrast Search)

    private func locateChessboardRect(in cgImage: CGImage) -> CGRect? {
        let origW = cgImage.width
        let origH = cgImage.height

        let targetW = 240
        let scale = Double(targetW) / Double(origW)
        let targetH = max(120, Int((Double(origH) * scale).rounded()))

        guard let rgba = renderRGBABuffer(cgImage: cgImage, width: targetW, height: targetH) else {
            return nil
        }

        let minDim = min(targetW, targetH)
        var candidateSizes: [Int] = []
        if targetW <= targetH {
            // Portrait (typical iPhone screenshot: board width is 92%..100% of screen width)
            candidateSizes = [
                targetW,
                Int(Double(targetW) * 0.96),
                Int(Double(targetW) * 0.92),
                Int(Double(targetW) * 0.88)
            ]
        } else {
            // Landscape / iPad split-screen
            candidateSizes = [
                Int(Double(minDim) * 0.92),
                Int(Double(minDim) * 0.82),
                Int(Double(minDim) * 0.72),
                Int(Double(minDim) * 0.60)
            ]
        }

        var bestScore: Double = -1.0
        var bestX: Int = 0
        var bestY: Int = Int(Double(targetH) * 0.25)
        var bestSize: Int = minDim

        // Prefer lower 84% of vertical screen first so floating PiP overlay at top isn't matched as the main board
        let preferredYMin = max(0, Int(Double(targetH) * 0.16))
        let fallbackYMin = max(0, Int(Double(targetH) * 0.04))

        func scanYRange(size: Int, xCandidates: Set<Int>, yStart: Int, yEnd: Int, step: Int) {
            for x in xCandidates {
                var y = yStart
                while y <= yEnd {
                    let score = evaluateCheckerboardScore(
                        rgba: rgba,
                        bufW: targetW,
                        bufH: targetH,
                        x: x,
                        y: y,
                        size: size
                    )
                    if score > bestScore {
                        bestScore = score
                        bestX = x
                        bestY = y
                        bestSize = size
                    }
                    y += step
                }
            }
        }

        for size in candidateSizes where size >= 80 && size <= targetW && size <= targetH {
            let maxX = max(0, targetW - size)
            let xStep = max(2, maxX / 8)
            var xCandidates: [Int] = []
            if maxX == 0 {
                xCandidates = [0]
            } else {
                xCandidates.append(maxX / 2)
                var x = 0
                while x <= maxX {
                    xCandidates.append(x)
                    x += xStep
                }
            }

            let yMax = max(preferredYMin, targetH - size - Int(Double(targetH) * 0.03))
            scanYRange(size: size, xCandidates: Set(xCandidates), yStart: preferredYMin, yEnd: yMax, step: 2)
        }

        if bestScore < 20.0 {
            for size in candidateSizes where size >= 80 && size <= targetW && size <= targetH {
                let maxX = max(0, targetW - size)
                let xStep = max(2, maxX / 8)
                var xCandidates: [Int] = maxX == 0 ? [0] : [maxX / 2]
                if maxX > 0 {
                    var x = 0
                    while x <= maxX {
                        xCandidates.append(x)
                        x += xStep
                    }
                }
                let upperEnd = min(preferredYMin, max(fallbackYMin, targetH - size))
                scanYRange(size: size, xCandidates: Set(xCandidates), yStart: fallbackYMin, yEnd: upperEnd, step: 2)
            }
        }

        // 1px vertical refinement around best candidate
        let refineMinY = max(fallbackYMin, bestY - 3)
        let refineMaxY = min(max(fallbackYMin, targetH - bestSize), bestY + 3)
        if refineMinY <= refineMaxY {
            for y in refineMinY...refineMaxY {
                let score = evaluateCheckerboardScore(
                    rgba: rgba,
                    bufW: targetW,
                    bufH: targetH,
                    x: bestX,
                    y: y,
                    size: bestSize
                )
                if score > bestScore {
                    bestScore = score
                    bestY = y
                }
            }
        }

        let bestBox = CGRect(x: bestX, y: bestY, width: bestSize, height: bestSize)

        guard bestScore > 12.0 else {
            // Fallback center square if screenshot is heavily obscured
            let s = Double(min(origW, origH))
            let fy = max(0, (Double(origH) - s) * 0.45)
            return CGRect(x: (Double(origW) - s) / 2.0, y: fy, width: s, height: s)
        }

        // Convert back to original image pixels
        let invScale = 1.0 / scale
        return CGRect(
            x: bestBox.minX * invScale,
            y: bestBox.minY * invScale,
            width: bestBox.width * invScale,
            height: bestBox.height * invScale
        ).integral
    }

    private func evaluateCheckerboardScore(
        rgba: [UInt8],
        bufW: Int,
        bufH: Int,
        x: Int,
        y: Int,
        size: Int
    ) -> Double {
        let cell = Double(size) / 8.0
        var lightLums: [Double] = []
        var darkLums: [Double] = []
        lightLums.reserveCapacity(32)
        darkLums.reserveCapacity(32)

        for r in 0..<8 {
            for c in 0..<8 {
                // Sample upper-right area of cell (less likely to be covered by a piece or rank/file coordinate)
                let px = min(bufW - 1, max(0, x + Int((Double(c) + 0.84) * cell)))
                let py = min(bufH - 1, max(0, y + Int((Double(r) + 0.12) * cell)))
                let idx = (py * bufW + px) * 4
                let lum = 0.299 * Double(rgba[idx]) + 0.587 * Double(rgba[idx + 1]) + 0.114 * Double(rgba[idx + 2])
                if (r + c) % 2 == 0 {
                    lightLums.append(lum)
                } else {
                    darkLums.append(lum)
                }
            }
        }

        let lightMed = median(lightLums)
        let darkMed = median(darkLums)
        let contrast = lightMed - darkMed
        guard contrast > 12.0 else { return -1.0 }

        // Count how many squares closely match their expected parity background
        var parityMatches = 0
        for l in lightLums where abs(l - lightMed) < 22.0 { parityMatches += 1 }
        for d in darkLums where abs(d - darkMed) < 22.0 { parityMatches += 1 }

        // Check sharp transitions along internal vertical boundaries (7 lines)
        var verticalBoundaryContrast = 0.0
        for r in 0..<8 {
            let py = min(bufH - 1, max(0, y + Int((Double(r) + 0.12) * cell)))
            for c in 1..<8 {
                let bxLeft = min(bufW - 1, max(0, x + Int(Double(c) * cell) - 2))
                let bxRight = min(bufW - 1, max(0, x + Int(Double(c) * cell) + 2))
                let iL = (py * bufW + bxLeft) * 4
                let iR = (py * bufW + bxRight) * 4
                let diff = abs(Double(rgba[iL]) - Double(rgba[iR]))
                    + abs(Double(rgba[iL + 1]) - Double(rgba[iR + 1]))
                    + abs(Double(rgba[iL + 2]) - Double(rgba[iR + 2]))
                verticalBoundaryContrast += min(diff, 150.0)
            }
        }
        verticalBoundaryContrast /= 56.0

        // Check sharp transitions along internal horizontal boundaries (7 lines) with +/-1px tight stride
        var horizontalBoundaryContrast = 0.0
        for c in 0..<8 {
            let px = min(bufW - 1, max(0, x + Int((Double(c) + 0.84) * cell)))
            for r in 1..<8 {
                let byTop = min(bufH - 1, max(0, y + Int(Double(r) * cell) - 1))
                let byBottom = min(bufH - 1, max(0, y + Int(Double(r) * cell) + 1))
                let iT = (byTop * bufW + px) * 4
                let iB = (byBottom * bufW + px) * 4
                let diff = abs(Double(rgba[iT]) - Double(rgba[iB]))
                    + abs(Double(rgba[iT + 1]) - Double(rgba[iB + 1]))
                    + abs(Double(rgba[iT + 2]) - Double(rgba[iB + 2]))
                horizontalBoundaryContrast += min(diff, 150.0)
            }
        }
        horizontalBoundaryContrast /= 56.0

        return contrast * 0.4 + Double(parityMatches) * 2.0 + verticalBoundaryContrast * 0.4 + horizontalBoundaryContrast * 0.9
    }

    // MARK: - Orientation Detection via Vision OCR

    private func detectBoardPerspective(boardCGImage: CGImage) async -> PieceColor? {
        let w = boardCGImage.width
        let h = boardCGImage.height
        let cellW = w / 8
        let cellH = h / 8

        // Bottom-left corner cell contains 'a' (White perspective) or 'h' (Black perspective)
        let bottomLeftRect = CGRect(x: 0, y: h - cellH, width: cellW, height: cellH)
        let bottomRightRect = CGRect(x: w - cellW, y: h - cellH, width: cellW, height: cellH)

        let leftText = await recognizeSingleCharLabel(in: boardCGImage.cropping(to: bottomLeftRect))
        if let ch = leftText {
            if ch == "a" || ch == "1" { return .white }
            if ch == "h" || ch == "8" { return .black }
        }

        let rightText = await recognizeSingleCharLabel(in: boardCGImage.cropping(to: bottomRightRect))
        if let ch = rightText {
            if ch == "h" { return .white }
            if ch == "a" { return .black }
        }

        return nil
    }

    private func recognizeSingleCharLabel(in cgImage: CGImage?) async -> String? {
        guard let cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            var didResume = false
            let request = VNRecognizeTextRequest { req, _ in
                guard !didResume else { return }
                let observations = req.results as? [VNRecognizedTextObservation] ?? []
                let allText = observations
                    .compactMap { $0.topCandidates(1).first?.string.lowercased() }
                    .joined()
                for target in ["a", "h", "1", "8"] {
                    if allText.contains(target) {
                        didResume = true
                        continuation.resume(returning: target)
                        return
                    }
                }
                didResume = true
                continuation.resume(returning: nil)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.usesCPUOnly = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                if !didResume {
                    didResume = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Fair-Play Match Context Detection (Bot vs Human Timed Match)

    private func analyzeMatchContext(
        fullCGImage: CGImage,
        boardPixelRect: CGRect
    ) async -> (isHumanTimed: Bool, isBot: Bool, note: String) {
        let imgW = CGFloat(fullCGImage.width)
        let imgH = CGFloat(fullCGImage.height)

        // Exclude top ~6.5% iOS status bar and floating PiP region by only inspecting strip immediately above the board
        let topStripMinY = max(imgH * 0.065, boardPixelRect.minY - imgH * 0.075)
        let topStripHeight = max(0, boardPixelRect.minY - topStripMinY)
        let topRect = CGRect(x: 0, y: topStripMinY, width: imgW, height: topStripHeight)

        let bottomStripMaxY = min(imgH, boardPixelRect.maxY + imgH * 0.16)
        let bottomStripHeight = max(0, bottomStripMaxY - boardPixelRect.maxY)
        let bottomRect = CGRect(x: 0, y: boardPixelRect.maxY, width: imgW, height: bottomStripHeight)

        var texts: [String] = []
        if topRect.height >= 24, let topCrop = fullCGImage.cropping(to: topRect) {
            texts.append(await recognizeAllText(in: topCrop))
        }
        if bottomRect.height >= 24, let bottomCrop = fullCGImage.cropping(to: bottomRect) {
            texts.append(await recognizeAllText(in: bottomCrop))
        }

        let combined = texts.joined(separator: " ")
        let lower = combined.lowercased()

        let botKeywords = ["bot", "computer", "coach", "電腦", "機器人", "練習", "挑戰", "adaptive"]
        let hasBotIndicator = botKeywords.contains { lower.contains($0) }

        let hasCountdownClock = combined.range(of: #"\b\d{1,2}:\d{2}\b"#, options: .regularExpression) != nil

        if hasBotIndicator {
            return (false, true, "已確認為電腦/Bot 練習對局")
        }
        if hasCountdownClock {
            return (true, false, "偵測到倒數計時器且無 Bot 標記，疑似真人計時賽，已自動鎖定提示")
        }
        return (false, false, "未偵測到計時器，維持安全輔助模式")
    }

    private func recognizeAllText(in cgImage: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            var didResume = false
            let request = VNRecognizeTextRequest { req, _ in
                guard !didResume else { return }
                didResume = true
                let observations = req.results as? [VNRecognizedTextObservation] ?? []
                let joined = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                continuation.resume(returning: joined)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.usesCPUOnly = true
            request.recognitionLanguages = ["zh-Hant", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                if !didResume {
                    didResume = true
                    continuation.resume(returning: "")
                }
            }
        }
    }

    // MARK: - 64-Square Piece Classification

    private struct RGBColor {
        let r: Double
        let g: Double
        let b: Double

        var luminance: Double {
            0.299 * r + 0.587 * g + 0.114 * b
        }

        func distance(to other: RGBColor) -> Double {
            let dr = r - other.r
            let dg = g - other.g
            let db = b - other.b
            return sqrt(dr * dr + dg * dg + db * db)
        }
    }

    private struct CellObservation {
        let boardRow: Int
        let boardCol: Int
        let color: PieceColor
        let guessedPiece: ChessPiece
        let confidence: Double
        let kingLikelihood: Double
        let coverage: Double
        let isHighlighted: Bool
    }

    private struct ScreenCellSample {
        let piece: ChessPiece
        let confidence: Double
        let kingLikelihood: Double
        let coverage: Double
        let isHighlighted: Bool
    }

    private struct ForegroundCellMask {
        let mask: [[Bool]]
        let minX: Int
        let maxX: Int
        let minY: Int
        let maxY: Int
        let innerSize: Int
        let fgCount: Int
        let coverage: Double
        let avgLum: Double
        let avgRMinusB: Double
        let colorScore: Double
        let isHighlighted: Bool
    }

    private func classify64Squares(
        boardCGImage: CGImage,
        fallbackPerspective: PieceColor,
        preferredSideToMove: PieceColor?,
        previousBoard: ChessBoardState,
        forcedPerspective: PieceColor? = nil
    ) -> (board: ChessBoardState, perspective: PieceColor, confidence: Double, notes: String, campConfidence: Double, campReason: String) {
        let normSize = 400 // 50x50 px per square
        guard let rgba = renderRGBABuffer(cgImage: boardCGImage, width: normSize, height: normSize) else {
            return (ChessBoardState.startingPosition, fallbackPerspective, 0.0, "無法讀取圖像像素", 0.5, "無法識別陣營（使用預設方向）")
        }

        let cellSize = 50
        // Estimate global light & dark square RGB from upper corners
        var lightR: [Double] = [], lightG: [Double] = [], lightB: [Double] = []
        var darkR: [Double] = [], darkG: [Double] = [], darkB: [Double] = []

        for r in 0..<8 {
            for c in 0..<8 {
                let sample = sampleSquareCornerRGB(rgba: rgba, strideW: normSize, row: r, col: c, cellSize: cellSize)
                if (r + c) % 2 == 0 {
                    lightR.append(sample.r); lightG.append(sample.g); lightB.append(sample.b)
                } else {
                    darkR.append(sample.r); darkG.append(sample.g); darkB.append(sample.b)
                }
            }
        }

        let globalLight = RGBColor(r: median(lightR), g: median(lightG), b: median(lightB))
        let globalDark = RGBColor(r: median(darkR), g: median(darkG), b: median(darkB))

        // Pass 1: Extract foreground masks & luminance/tint scores for adaptive two-cluster color split
        var fgGrid: [[ForegroundCellMask?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        var screenHighlights: [[Bool]] = Array(repeating: Array(repeating: false, count: 8), count: 8)
        var colorScores: [Double] = []
        colorScores.reserveCapacity(32)

        for screenRow in 0..<8 {
            for screenCol in 0..<8 {
                let isLight = (screenRow + screenCol) % 2 == 0
                let globalBG = isLight ? globalLight : globalDark
                let localCorner = sampleSquareCornerRGB(
                    rgba: rgba,
                    strideW: normSize,
                    row: screenRow,
                    col: screenCol,
                    cellSize: cellSize
                )
                let bgDist = localCorner.distance(to: globalBG)
                let isHighlighted = screenRow >= 1 && bgDist > 34.0
                screenHighlights[screenRow][screenCol] = isHighlighted
                let bg = bgDist > 18.0 ? localCorner : globalBG

                if let fgMask = extractForegroundMask(
                    rgba: rgba,
                    strideW: normSize,
                    screenRow: screenRow,
                    screenCol: screenCol,
                    cellSize: cellSize,
                    bg: bg,
                    isHighlighted: isHighlighted
                ) {
                    fgGrid[screenRow][screenCol] = fgMask
                    colorScores.append(fgMask.colorScore)
                }
            }
        }

        var dynamicColorSplit: Double? = nil
        let sortedScores = colorScores.sorted()
        if sortedScores.count >= 4 {
            let k = max(1, (sortedScores.count * 2) / 5)
            let darkCluster = Array(sortedScores.prefix(k))
            let brightCluster = Array(sortedScores.suffix(k))
            let darkMed = median(darkCluster)
            let brightMed = median(brightCluster)
            if brightMed - darkMed > 14.0 {
                dynamicColorSplit = (darkMed + brightMed) / 2.0
            }
        }

        // Pass 2: Classify piece color & shape, and accumulate weighted camp signals
        var screenCells: [[ScreenCellSample?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        var whiteBottomScore = 0
        var blackBottomScore = 0

        for screenRow in 0..<8 {
            for screenCol in 0..<8 {
                guard let fgMask = fgGrid[screenRow][screenCol] else { continue }
                let pieceColor: PieceColor
                if let split = dynamicColorSplit {
                    pieceColor = fgMask.colorScore >= split ? .white : .black
                } else {
                    pieceColor = (fgMask.avgRMinusB > 5.0 || fgMask.avgLum > 145.0) ? .white : .black
                }

                let result = classifyPieceFromMask(fgMask, pieceColor: pieceColor)
                screenCells[screenRow][screenCol] = ScreenCellSample(
                    piece: result.piece,
                    confidence: result.confidence,
                    kingLikelihood: result.kingLikelihood,
                    coverage: result.coverage,
                    isHighlighted: fgMask.isHighlighted
                )

                let weight: Int
                switch screenRow {
                case 7, 0: weight = 4
                case 6, 1: weight = 3
                case 5, 2: weight = 1
                default: weight = 0
                }
                if screenRow >= 5 {
                    if pieceColor == .white { whiteBottomScore += weight } else { blackBottomScore += weight }
                } else if screenRow <= 2 {
                    if pieceColor == .black { whiteBottomScore += weight } else { blackBottomScore += weight }
                }
            }
        }

        // Signal 2: Back-rank King/Queen structural tie-breaker (e-file vs d-file)
        if let eBottom = screenCells[7][4], let dBottom = screenCells[7][3],
           eBottom.kingLikelihood > dBottom.kingLikelihood + 0.15 {
            whiteBottomScore += 2
        } else if let eBottom = screenCells[7][4], let dBottom = screenCells[7][3],
                  dBottom.kingLikelihood > eBottom.kingLikelihood + 0.15 {
            blackBottomScore += 2
        }
        if let eTop = screenCells[0][4], let dTop = screenCells[0][3],
           eTop.kingLikelihood > dTop.kingLikelihood + 0.15 {
            whiteBottomScore += 2
        } else if let eTop = screenCells[0][4], let dTop = screenCells[0][3],
                  dTop.kingLikelihood > eTop.kingLikelihood + 0.15 {
            blackBottomScore += 2
        }

        let perspective: PieceColor
        let campConfidence: Double
        let campReason: String

        if let forced = forcedPerspective {
            perspective = forced
            campConfidence = 1.0
            campReason = "已指定我方執\(forced.displayName)"
        } else {
            if whiteBottomScore > blackBottomScore {
                perspective = .white
            } else if blackBottomScore > whiteBottomScore {
                perspective = .black
            } else {
                perspective = fallbackPerspective
            }

            let totalWeight = whiteBottomScore + blackBottomScore
            let margin = abs(whiteBottomScore - blackBottomScore)
            if totalWeight > 0 && margin > 0 {
                campConfidence = min(0.99, 0.50 + 0.50 * Double(margin) / Double(max(6, totalWeight)))
            } else {
                campConfidence = 0.55
            }
            campReason = "自動識別：我方執\(perspective.displayName)（信心 \(Int((campConfidence * 100).rounded()))%）"
        }

        var observedGrid: [[CellObservation?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        var detectedPieceCount = 0
        var pieceConfidenceSum = 0.0
        var highlightSquares: Set<BoardSquare> = []
        var highlightedPieceColor: PieceColor?

        for screenRow in 0..<8 {
            for screenCol in 0..<8 {
                let boardRow = perspective == .white ? screenRow : (7 - screenRow)
                let boardCol = perspective == .white ? screenCol : (7 - screenCol)
                let boardSq = BoardSquare(row: boardRow, col: boardCol)
                let isHighlighted = screenHighlights[screenRow][screenCol]
                if isHighlighted {
                    highlightSquares.insert(boardSq)
                }

                if let cell = screenCells[screenRow][screenCol] {
                    observedGrid[boardRow][boardCol] = CellObservation(
                        boardRow: boardRow,
                        boardCol: boardCol,
                        color: cell.piece.color,
                        guessedPiece: cell.piece,
                        confidence: cell.confidence,
                        kingLikelihood: cell.kingLikelihood,
                        coverage: cell.coverage,
                        isHighlighted: cell.isHighlighted
                    )
                    detectedPieceCount += 1
                    pieceConfidenceSum += cell.confidence
                    if cell.isHighlighted {
                        highlightedPieceColor = cell.piece.color
                    }
                }
            }
        }

        let resolvedSideToMove = preferredSideToMove ?? highlightedPieceColor?.opposite ?? perspective
        let (reconstructedBoard, methodLabel) = reconstructGridFromReference(
            observed: observedGrid,
            highlightSquares: highlightSquares,
            previousBoard: previousBoard,
            sideToMove: resolvedSideToMove
        )

        let avgConf = detectedPieceCount > 0 ? (pieceConfidenceSum / Double(detectedPieceCount)) : 0.65
        let turnNote = resolvedSideToMove.displayName
        let note = "已辨識 \(detectedPieceCount) 枚棋子（視角：\(perspective.displayName)｜輪到：\(turnNote)｜\(methodLabel)）"
        return (reconstructedBoard, perspective, avgConf, note, campConfidence, campReason)
    }

    private func reconstructGridFromReference(
        observed: [[CellObservation?]],
        highlightSquares: Set<BoardSquare>,
        previousBoard: ChessBoardState,
        sideToMove: PieceColor
    ) -> (board: ChessBoardState, methodLabel: String) {
        // Stage 1: Exact 0-ply, 1-ply, or 2-ply legal move delta match against previousBoard (then startingPosition)
        if previousBoard != .startingPosition,
           let matchedPrev = findLegalDeltaMatch(
               from: previousBoard,
               observed: observed,
               highlightSquares: highlightSquares,
               preferredSideToMove: sideToMove
           ) {
            return matchedPrev
        }
        if let matchedStart = findLegalDeltaMatch(
            from: .startingPosition,
            observed: observed,
            highlightSquares: highlightSquares,
            preferredSideToMove: sideToMove
        ) {
            return matchedStart
        }

        // Stage 2: Check whether >= 90% of observed pieces are high-confidence template matches
        var totalObsCount = 0
        var highConfCount = 0
        var whiteKingCandidates: [(row: Int, col: Int, score: Double)] = []
        var blackKingCandidates: [(row: Int, col: Int, score: Double)] = []

        for r in 0..<8 {
            for c in 0..<8 {
                if let obs = observed[r][c] {
                    totalObsCount += 1
                    if obs.confidence >= 0.88 {
                        highConfCount += 1
                    }
                    if obs.guessedPiece.type == .king || obs.kingLikelihood > 0.45 {
                        if obs.color == .white {
                            whiteKingCandidates.append((r, c, obs.kingLikelihood))
                        } else {
                            blackKingCandidates.append((r, c, obs.kingLikelihood))
                        }
                    }
                }
            }
        }

        let hasHighConfMajority = totalObsCount > 0 && (Double(highConfCount) / Double(totalObsCount) >= 0.90)

        // Anchored + Displaced-Piece Assignment (supports arbitrary move count & custom themes)
        let refBoard: ChessBoardState
        if previousBoard == .startingPosition {
            refBoard = .startingPosition
        } else {
            let prevAnchor = anchorCount(reference: previousBoard, observed: observed)
            let startAnchor = anchorCount(reference: .startingPosition, observed: observed)
            let obsW = observedCount(in: observed, color: .white)
            let obsB = observedCount(in: observed, color: .black)
            let prevW = pieceCount(in: previousBoard, color: .white)
            let prevB = pieceCount(in: previousBoard, color: .black)
            let canContinueFromPrev = obsW <= prevW && obsB <= prevB && prevAnchor >= startAnchor - 2
            refBoard = canContinueFromPrev ? previousBoard : .startingPosition
        }

        var grid: [[ChessPiece?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)

        for side in [PieceColor.white, PieceColor.black] {
            var displacedRefs: [(row: Int, col: Int, type: PieceType)] = []
            var displacedObs: [CellObservation] = []

            for r in 0..<8 {
                for c in 0..<8 {
                    let refPiece = refBoard.squares[r][c]
                    let obs = observed[r][c]
                    let refSame = (refPiece?.color == side)
                    let obsSame = (obs?.color == side)

                    if let ob = obs, hasHighConfMajority && ob.color == side && ob.confidence >= 0.88 {
                        let finalType: PieceType = (ob.guessedPiece.type == .pawn && (r == 0 || r == 7)) ? .queen : ob.guessedPiece.type
                        grid[r][c] = ChessPiece(color: side, type: finalType)
                    } else if refSame && obsSame, let rp = refPiece {
                        if let ob = obs, ob.confidence >= 0.88 && ob.guessedPiece.type != rp.type {
                            let finalType: PieceType = (ob.guessedPiece.type == .pawn && (r == 0 || r == 7)) ? .queen : ob.guessedPiece.type
                            grid[r][c] = ChessPiece(color: side, type: finalType)
                        } else {
                            grid[r][c] = rp
                        }
                    } else if refSame, let rp = refPiece {
                        displacedRefs.append((r, c, rp.type))
                    } else if obsSame, let ob = obs {
                        displacedObs.append(ob)
                    }
                }
            }

            if !displacedObs.isEmpty {
                let assigned = assignDisplacedPieces(
                    refs: displacedRefs,
                    obs: displacedObs,
                    side: side
                )
                for (obIndex, assignedType) in assigned.enumerated() {
                    let ob = displacedObs[obIndex]
                    let chosenType = ob.confidence >= 0.88 ? ob.guessedPiece.type : assignedType
                    let finalType: PieceType = (chosenType == .pawn && (ob.boardRow == 0 || ob.boardRow == 7)) ? .queen : chosenType
                    grid[ob.boardRow][ob.boardCol] = ChessPiece(color: side, type: finalType)
                }
            }
        }

        ensureKingPresence(grid: &grid, color: .white, candidates: whiteKingCandidates)
        ensureKingPresence(grid: &grid, color: .black, candidates: blackKingCandidates)
        enforceSingleKingPerSide(
            grid: &grid,
            observed: observed,
            whiteCandidates: whiteKingCandidates,
            blackCandidates: blackKingCandidates
        )

        var castling = CastlingRights.none
        if grid[7][4] == ChessPiece(color: .white, type: .king) {
            if grid[7][7] == ChessPiece(color: .white, type: .rook) { castling.whiteKingside = true }
            if grid[7][0] == ChessPiece(color: .white, type: .rook) { castling.whiteQueenside = true }
        }
        if grid[0][4] == ChessPiece(color: .black, type: .king) {
            if grid[0][7] == ChessPiece(color: .black, type: .rook) { castling.blackKingside = true }
            if grid[0][0] == ChessPiece(color: .black, type: .rook) { castling.blackQueenside = true }
        }

        let state = ChessBoardState(
            squares: grid,
            sideToMove: sideToMove,
            castlingRights: castling,
            enPassantTarget: nil,
            halfMoveClock: 0,
            fullMoveNumber: max(1, refBoard.fullMoveNumber)
        )
        return (state, hasHighConfMajority ? "高精準模板直接辨識" : "幾何位移追蹤")
    }

    private func findLegalDeltaMatch(
        from baseBoard: ChessBoardState,
        observed: [[CellObservation?]],
        highlightSquares: Set<BoardSquare>,
        preferredSideToMove: PieceColor
    ) -> (board: ChessBoardState, methodLabel: String)? {
        if occupancyMatches(baseBoard, observed: observed) {
            var updated = baseBoard
            updated.sideToMove = preferredSideToMove
            return (updated, "0步延續")
        }

        let seedSides: [PieceColor] = baseBoard.sideToMove == preferredSideToMove.opposite
            ? [baseBoard.sideToMove, baseBoard.sideToMove.opposite]
            : [baseBoard.sideToMove.opposite, baseBoard.sideToMove]

        var twoPlyBest: (board: ChessBoardState, score: Int)?

        for seedSide in seedSides {
            var seedBoard = baseBoard
            seedBoard.sideToMove = seedSide
            let moves1 = seedBoard.legalMoves()

            var onePlyBest: (board: ChessBoardState, score: Int)?
            for m1 in moves1 {
                let after1 = seedBoard.applying(m1)
                if occupancyMatches(after1, observed: observed) {
                    var score = (highlightSquares.contains(m1.from) ? 4 : 0) + (highlightSquares.contains(m1.to) ? 4 : 0)
                    if m1.promotion == .queen { score += 3 }
                    if observed[m1.to.row][m1.to.col]?.guessedPiece.type == after1.squares[m1.to.row][m1.to.col]?.type {
                        score += 1
                    }
                    if onePlyBest == nil || score > onePlyBest!.score {
                        onePlyBest = (after1, score)
                    }
                } else if twoPlyBest == nil && occupancyDiffCount(after1, observed: observed) <= 4 {
                    for m2 in after1.legalMoves() {
                        let after2 = after1.applying(m2)
                        if occupancyMatches(after2, observed: observed) {
                            var score = (highlightSquares.contains(m2.from) ? 4 : 0) + (highlightSquares.contains(m2.to) ? 4 : 0)
                            if m2.promotion == .queen { score += 3 }
                            if after2.sideToMove == preferredSideToMove { score += 5 }
                            if twoPlyBest == nil || score > twoPlyBest!.score {
                                twoPlyBest = (after2, score)
                            }
                        }
                    }
                }
            }

            if let best1 = onePlyBest {
                return (best1.board, "1步著法追蹤")
            }
        }

        if let best2 = twoPlyBest {
            return (best2.board, "2步著法追蹤")
        }
        return nil
    }

    private func occupancyMatches(_ board: ChessBoardState, observed: [[CellObservation?]]) -> Bool {
        for r in 0..<8 {
            for c in 0..<8 {
                if board.squares[r][c]?.color != observed[r][c]?.color {
                    return false
                }
            }
        }
        return true
    }

    private func occupancyDiffCount(_ board: ChessBoardState, observed: [[CellObservation?]]) -> Int {
        var diffs = 0
        for r in 0..<8 {
            for c in 0..<8 {
                if board.squares[r][c]?.color != observed[r][c]?.color {
                    diffs += 1
                }
            }
        }
        return diffs
    }

    private func anchorCount(reference: ChessBoardState, observed: [[CellObservation?]]) -> Int {
        var count = 0
        for r in 0..<8 {
            for c in 0..<8 {
                if let rp = reference.squares[r][c], let ob = observed[r][c], rp.color == ob.color {
                    count += 1
                }
            }
        }
        return count
    }

    private func pieceCount(in board: ChessBoardState, color: PieceColor) -> Int {
        var count = 0
        for r in 0..<8 {
            for c in 0..<8 where board.squares[r][c]?.color == color {
                count += 1
            }
        }
        return count
    }

    private func observedCount(in observed: [[CellObservation?]], color: PieceColor) -> Int {
        var count = 0
        for r in 0..<8 {
            for c in 0..<8 where observed[r][c]?.color == color {
                count += 1
            }
        }
        return count
    }

    private func assignDisplacedPieces(
        refs: [(row: Int, col: Int, type: PieceType)],
        obs: [CellObservation],
        side: PieceColor
    ) -> [PieceType] {
        guard !obs.isEmpty else { return [] }
        guard !refs.isEmpty else { return obs.map(\.guessedPiece.type) }

        var scoreMatrix: [[Double]] = Array(
            repeating: Array(repeating: -100.0, count: obs.count),
            count: refs.count
        )
        for ri in 0..<refs.count {
            for oi in 0..<obs.count {
                scoreMatrix[ri][oi] = displacementAssignmentScore(ref: refs[ri], obs: obs[oi], side: side)
            }
        }

        var result = obs.map(\.guessedPiece.type)

        // Exact backtracking when displaced count is small (typical opening/midgame)
        if refs.count <= 7 && obs.count <= 7 {
            let targetMatches = min(refs.count, obs.count)
            var bestScore = -Double.infinity
            var bestChoice = Array(repeating: -1, count: obs.count) // obsIdx -> refIdx
            var currentChoice = Array(repeating: -1, count: obs.count)
            var usedRefs = Array(repeating: false, count: refs.count)

            func dfs(obsIdx: Int, matchedCount: Int, currentScore: Double) {
                if obsIdx == obs.count {
                    if matchedCount == targetMatches && currentScore > bestScore {
                        bestScore = currentScore
                        bestChoice = currentChoice
                    }
                    return
                }
                let remainingObs = obs.count - obsIdx
                if matchedCount + remainingObs - 1 >= targetMatches {
                    // Allow leaving this obs unmatched only if obs.count > refs.count
                    currentChoice[obsIdx] = -1
                    dfs(obsIdx: obsIdx + 1, matchedCount: matchedCount, currentScore: currentScore - 2.0)
                }
                for ri in 0..<refs.count where !usedRefs[ri] {
                    usedRefs[ri] = true
                    currentChoice[obsIdx] = ri
                    dfs(obsIdx: obsIdx + 1, matchedCount: matchedCount + 1, currentScore: currentScore + scoreMatrix[ri][obsIdx])
                    usedRefs[ri] = false
                }
            }

            dfs(obsIdx: 0, matchedCount: 0, currentScore: 0.0)
            for oi in 0..<obs.count {
                let ri = bestChoice[oi]
                if ri >= 0 {
                    result[oi] = refs[ri].type
                }
            }
            return result
        }

        // Greedy max-score assignment fallback when many pieces moved
        var pairs: [(ri: Int, oi: Int, score: Double)] = []
        pairs.reserveCapacity(refs.count * obs.count)
        for ri in 0..<refs.count {
            for oi in 0..<obs.count {
                pairs.append((ri, oi, scoreMatrix[ri][oi]))
            }
        }
        pairs.sort { $0.score > $1.score }
        var usedR = Set<Int>()
        var usedO = Set<Int>()
        for pair in pairs {
            if usedR.contains(pair.ri) || usedO.contains(pair.oi) { continue }
            result[pair.oi] = refs[pair.ri].type
            usedR.insert(pair.ri)
            usedO.insert(pair.oi)
        }
        return result
    }

    private func displacementAssignmentScore(
        ref: (row: Int, col: Int, type: PieceType),
        obs: CellObservation,
        side: PieceColor
    ) -> Double {
        let dr = obs.boardRow - ref.row
        let dc = obs.boardCol - ref.col
        let absDr = abs(dr)
        let absDc = abs(dc)
        let homeRank = side == .white ? 7 : 0
        let pawnHomeRank = side == .white ? 6 : 1
        var score = 0.0

        switch ref.type {
        case .pawn:
            let signedDr = side == .white ? -dr : dr
            if signedDr == 1 && absDc == 0 {
                score += 12.0
            } else if ref.row == pawnHomeRank && signedDr == 2 && absDc == 0 {
                score += 12.0
            } else if signedDr == 1 && absDc == 1 {
                score += 9.0
            } else if signedDr > 0 && signedDr <= 4 && absDc <= 2 {
                score += 3.0
            } else {
                score -= 12.0
            }
            if obs.coverage < 0.43 {
                score += 4.0
            } else {
                score -= 3.5
            }

        case .knight:
            if (absDr == 2 && absDc == 1) || (absDr == 1 && absDc == 2) {
                score += 12.0
            } else if isReachableInTwoKnightHops(fromRow: ref.row, fromCol: ref.col, toRow: obs.boardRow, toCol: obs.boardCol) {
                score += 6.5
            } else {
                score += 1.0
            }

        case .bishop:
            let sameParity = ((ref.row + ref.col) % 2) == ((obs.boardRow + obs.boardCol) % 2)
            if !sameParity {
                score -= 20.0
            } else if absDr == absDc {
                score += 12.0
            } else {
                score += 6.0
            }

        case .rook:
            if dr == 0 || dc == 0 {
                score += 11.0
            } else {
                score += 5.0
            }
            if obs.coverage > 0.60 { score += 1.5 }

        case .queen:
            if dr == 0 || dc == 0 || absDr == absDc {
                score += 9.5
            } else {
                score += 5.5
            }
            if obs.coverage < 0.43 { score -= 2.5 }
            if obs.coverage > 0.60 { score += 2.5 }

        case .king:
            if max(absDr, absDc) <= 1 {
                score += 10.0
            } else if ref.row == homeRank && ref.col == 4 && obs.boardRow == homeRank && (obs.boardCol == 2 || obs.boardCol == 6) {
                score += 13.0
            } else if max(absDr, absDc) > 2 {
                score -= 4.0
            }
            if obs.coverage < 0.43 { score -= 2.5 }
            if obs.coverage > 0.60 { score += 4.5 }
            score += obs.kingLikelihood * 2.5
        }

        if obs.guessedPiece.type == ref.type {
            score += 8.0
        }
        return score
    }

    private func isReachableInTwoKnightHops(fromRow: Int, fromCol: Int, toRow: Int, toCol: Int) -> Bool {
        let offsets = [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)]
        for (dr1, dc1) in offsets {
            let mr = fromRow + dr1
            let mc = fromCol + dc1
            guard (0..<8).contains(mr), (0..<8).contains(mc) else { continue }
            let dr2 = abs(toRow - mr)
            let dc2 = abs(toCol - mc)
            if (dr2 == 2 && dc2 == 1) || (dr2 == 1 && dc2 == 2) {
                return true
            }
        }
        return false
    }

    private func ensureKingPresence(
        grid: inout [[ChessPiece?]],
        color: PieceColor,
        candidates: [(row: Int, col: Int, score: Double)]
    ) {
        var kingCount = 0
        for r in 0..<8 {
            for c in 0..<8 {
                if grid[r][c]?.color == color && grid[r][c]?.type == .king {
                    kingCount += 1
                }
            }
        }
        if kingCount == 0, let best = candidates.max(by: { $0.score < $1.score }) {
            grid[best.row][best.col] = ChessPiece(color: color, type: .king)
        }
    }

    private func enforceSingleKingPerSide(
        grid: inout [[ChessPiece?]],
        observed: [[CellObservation?]],
        whiteCandidates: [(row: Int, col: Int, score: Double)],
        blackCandidates: [(row: Int, col: Int, score: Double)]
    ) {
        for color in [PieceColor.white, PieceColor.black] {
            let candidates = color == .white ? whiteCandidates : blackCandidates
            var kingPositions: [(row: Int, col: Int, score: Double)] = []
            for r in 0..<8 {
                for c in 0..<8 {
                    if grid[r][c]?.color == color && grid[r][c]?.type == .king {
                        let candScore = candidates.first(where: { $0.row == r && $0.col == c })?.score
                            ?? observed[r][c]?.kingLikelihood
                            ?? 0.0
                        kingPositions.append((r, c, candScore))
                    }
                }
            }
            guard kingPositions.count > 1,
                  let best = kingPositions.max(by: { $0.score < $1.score }) else {
                continue
            }
            let pawnRank = color == .white ? 6 : 1
            for pos in kingPositions where !(pos.row == best.row && pos.col == best.col) {
                let demotedType: PieceType = pos.row == pawnRank ? .pawn : .queen
                grid[pos.row][pos.col] = ChessPiece(color: color, type: demotedType)
            }
        }
    }

    private func sampleSquareCornerRGB(
        rgba: [UInt8],
        strideW: Int,
        row: Int,
        col: Int,
        cellSize: Int
    ) -> RGBColor {
        let baseX = col * cellSize
        let baseY = row * cellSize
        // Sample upper corners (avoids bottom coordinates a-h, top-left rank digits 1-8, and wide custom piece bases)
        let offsets = [
            (cellSize - 6, 10),
            (cellSize - 7, 12),
            (6, 14),
            (7, 16)
        ]
        var rs: [Double] = [], gs: [Double] = [], bs: [Double] = []
        for (ox, oy) in offsets {
            let px = baseX + ox
            let py = baseY + oy
            let idx = (py * strideW + px) * 4
            rs.append(Double(rgba[idx]))
            gs.append(Double(rgba[idx + 1]))
            bs.append(Double(rgba[idx + 2]))
        }
        return RGBColor(r: median(rs), g: median(gs), b: median(bs))
    }

    private static let oceanBlackTemplates: [(type: PieceType, grid: [Int])] = [
        (.rook,   [13,2,4,6,8,4,2,0,2,10,24,22,24,23,14,0,0,6,25,25,25,25,10,0,0,0,21,25,25,25,0,0,0,0,20,25,25,25,1,0,0,0,20,25,25,25,6,0,0,3,23,25,25,25,15,0,0,19,25,25,25,25,24,1]),
        (.knight, [0,0,3,10,2,0,0,0,0,3,24,25,24,24,12,0,0,12,25,21,25,25,15,0,3,19,13,10,8,25,20,0,1,10,5,10,12,14,21,0,0,0,12,21,14,22,20,0,0,9,23,23,21,23,23,4,0,17,25,25,25,25,25,9]),
        (.bishop, [0,0,0,13,18,0,0,0,0,0,5,22,7,6,0,0,0,0,19,22,11,24,2,0,0,0,25,20,15,25,8,0,0,4,25,25,25,25,10,0,0,0,21,25,25,24,4,0,0,5,19,25,25,25,17,0,0,15,25,25,25,25,25,2]),
        (.queen,  [0,0,5,0,0,5,0,0,4,0,15,8,7,13,0,2,7,11,15,19,13,15,10,19,2,23,21,22,11,22,23,7,0,13,22,20,7,10,19,0,0,9,18,17,9,17,11,0,0,12,21,21,23,24,17,0,0,25,25,25,25,25,24,2]),
        (.king,   [0,0,3,19,24,10,0,0,0,1,11,25,25,20,5,0,5,22,24,25,25,25,25,14,16,25,19,22,25,18,25,24,13,25,17,23,24,19,25,20,1,18,25,25,25,22,23,6,0,8,25,25,25,25,18,0,0,15,25,25,25,25,25,4]),
        (.pawn,   [4,0,0,2,3,0,0,0,0,0,5,24,22,6,0,0,0,0,14,25,25,10,0,0,0,0,5,21,19,8,0,0,0,0,8,11,19,8,0,0,0,0,6,23,22,11,0,0,0,8,23,25,25,25,9,0,0,18,25,25,25,25,19,0])
    ]

    private static let oceanWhiteTemplates: [(type: PieceType, grid: [Int])] = [
        (.rook,   [1,2,4,10,10,5,2,0,0,15,25,25,25,25,15,0,0,13,24,25,25,25,13,0,0,0,16,25,25,14,0,0,0,1,21,25,25,22,1,0,0,1,21,25,25,21,0,0,0,21,25,25,25,25,20,0,0,23,25,25,25,25,24,9]),
        (.knight, [0,0,0,14,3,0,0,0,0,0,11,24,25,17,0,0,0,0,25,25,21,25,13,0,0,13,12,6,6,25,24,0,0,24,1,3,19,25,25,0,0,5,2,22,25,25,19,0,0,0,5,20,25,25,20,3,0,3,25,25,25,25,25,22]),
        (.bishop, [0,0,0,22,15,0,0,0,0,0,6,25,10,5,0,0,0,1,20,22,15,22,0,0,0,6,25,21,20,25,1,0,0,7,25,25,25,25,5,0,0,4,25,25,25,25,3,0,0,9,25,25,25,25,8,0,0,25,25,25,25,25,24,9]),
        (.queen,  [0,0,18,21,11,24,3,0,1,6,17,22,14,23,4,8,11,25,11,22,18,16,14,24,0,11,20,24,24,20,13,12,0,5,11,15,12,16,21,1,0,0,5,0,0,12,10,0,0,1,17,15,15,20,15,0,0,4,25,25,25,25,25,10]),
        (.king,   [0,0,2,20,23,6,0,0,0,2,5,24,25,10,4,0,9,25,25,24,24,25,25,14,20,24,16,25,25,19,19,20,15,25,12,25,25,9,24,17,5,24,25,25,25,25,24,5,0,15,25,25,25,25,16,0,0,25,25,25,25,25,25,15]),
        (.pawn,   [0,0,0,0,0,0,0,0,0,0,1,17,17,0,0,0,0,0,9,25,25,16,0,0,0,0,8,25,25,8,0,0,0,0,12,25,25,10,0,0,0,0,5,25,25,4,0,0,0,5,23,25,25,22,3,0,0,15,25,25,25,25,14,0])
    ]

    private func extractGrid64(from mask: [[Bool]]) -> [Int] {
        var vec = [Int]()
        vec.reserveCapacity(64)
        for by in 0..<8 {
            for bx in 0..<8 {
                var cnt = 0
                for dy in 0..<5 {
                    let row = mask[by * 5 + dy]
                    for dx in 0..<5 where row[bx * 5 + dx] {
                        cnt += 1
                    }
                }
                vec.append(cnt)
            }
        }
        return vec
    }

    private func extractForegroundMask(
        rgba: [UInt8],
        strideW: Int,
        screenRow: Int,
        screenCol: Int,
        cellSize: Int,
        bg: RGBColor,
        isHighlighted: Bool
    ) -> ForegroundCellMask? {
        let baseX = screenCol * cellSize
        let baseY = screenRow * cellSize
        let pad = 5 // analyze inner 40x40 of the 50x50 square
        let innerSize = cellSize - 2 * pad
        let distThreshold = 34.0

        var mask = Array(repeating: Array(repeating: false, count: innerSize), count: innerSize)
        var fgRMinusBSum = 0.0
        var fgLumSum = 0.0
        var fgCount = 0
        var minX = innerSize, maxX = -1
        var minY = innerSize, maxY = -1

        for y in 0..<innerSize {
            for x in 0..<innerSize {
                let px = baseX + pad + x
                let py = baseY + pad + y
                let idx = (py * strideW + px) * 4
                let pixel = RGBColor(r: Double(rgba[idx]), g: Double(rgba[idx + 1]), b: Double(rgba[idx + 2]))
                if pixel.distance(to: bg) > distThreshold {
                    mask[y][x] = true
                    fgCount += 1
                    let lum = pixel.luminance
                    fgRMinusBSum += (pixel.r - pixel.b)
                    fgLumSum += lum
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        let totalInner = innerSize * innerSize
        let coverage = Double(fgCount) / Double(totalInner)
        guard coverage >= 0.08, maxX > minX, maxY > minY else {
            return nil
        }

        let avgRMinusB = fgCount > 0 ? fgRMinusBSum / Double(fgCount) : 0.0
        let avgLum = fgCount > 0 ? fgLumSum / Double(fgCount) : 0.0
        let colorScore = avgLum + 0.35 * avgRMinusB

        return ForegroundCellMask(
            mask: mask,
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
            innerSize: innerSize,
            fgCount: fgCount,
            coverage: coverage,
            avgLum: avgLum,
            avgRMinusB: avgRMinusB,
            colorScore: colorScore,
            isHighlighted: isHighlighted
        )
    }

    private func classifyPieceFromMask(
        _ fg: ForegroundCellMask,
        pieceColor: PieceColor
    ) -> (piece: ChessPiece, confidence: Double, kingLikelihood: Double, coverage: Double) {
        let mask = fg.mask
        let innerSize = fg.innerSize
        let minX = fg.minX
        let maxX = fg.maxX
        let minY = fg.minY
        let maxY = fg.maxY
        let fgCount = fg.fgCount
        let coverage = fg.coverage

        // 8x8 block density template match (supports custom 3D skins like Ocean dolphin/racecar/gas-mask sets)
        let grid64 = extractGrid64(from: mask)
        let templates = (pieceColor == .white) ? Self.oceanWhiteTemplates : Self.oceanBlackTemplates
        var bestTmplType: PieceType = .pawn
        var bestTmplDist = Int.max
        var kingTmplDist = 400
        for tmpl in templates {
            var dist = 0
            for i in 0..<64 {
                dist += abs(grid64[i] - tmpl.grid[i])
            }
            if tmpl.type == .king {
                kingTmplDist = dist
            }
            if dist < bestTmplDist {
                bestTmplDist = dist
                bestTmplType = tmpl.type
            }
        }
        if bestTmplDist < 285 {
            let tmplKingLikelihood = bestTmplType == .king ? 1.2 : max(0.0, 1.0 - Double(kingTmplDist) / 400.0)
            return (ChessPiece(color: pieceColor, type: bestTmplType), 0.94, tmplKingLikelihood, coverage)
        }

        // Extract geometric silhouette features inside bounding box
        let boxW = max(1, maxX - minX + 1)
        let boxH = max(1, maxY - minY + 1)
        let heightRatio = Double(boxH) / Double(innerSize)
        let widthRatio = Double(boxW) / Double(innerSize)
        let fillDensity = Double(fgCount) / Double(boxW * boxH)

        // Vertical profile: width in top/mid/bottom thirds and 6 slices
        var sliceWidths: [Double] = []
        var sliceLeftBias: [Double] = []
        let numSlices = 6
        for s in 0..<numSlices {
            let y0 = minY + (s * boxH) / numSlices
            let y1 = minY + ((s + 1) * boxH) / numSlices
            var rowWidths = 0
            var rowCount = 0
            var leftPixels = 0
            var rightPixels = 0
            let midX = minX + boxW / 2
            for y in y0..<max(y0 + 1, min(innerSize, y1)) {
                var rCount = 0
                for x in minX...maxX where mask[y][x] {
                    rCount += 1
                    if x < midX { leftPixels += 1 } else { rightPixels += 1 }
                }
                rowWidths += rCount
                rowCount += 1
            }
            let avgW = rowCount > 0 ? Double(rowWidths) / Double(rowCount * boxW) : 0.0
            sliceWidths.append(avgW)
            let tot = max(1, leftPixels + rightPixels)
            sliceLeftBias.append(Double(leftPixels - rightPixels) / Double(tot))
        }

        // Count vertical transitions in top 20% of bounding box (crenellations / crown)
        let crownY = min(innerSize - 1, minY + max(1, Int(Double(boxH) * 0.16)))
        var topTransitions = 0
        var prev = false
        for x in minX...maxX {
            let cur = mask[crownY][x]
            if cur != prev { topTransitions += 1 }
            prev = cur
        }
        let topPeaks = (topTransitions + 1) / 2

        let topWidth = sliceWidths[0]
        let upperMidWidth = sliceWidths[1]
        let midWidth = (sliceWidths[2] + sliceWidths[3]) / 2.0
        let baseWidth = sliceWidths[5]
        let asymmetry = abs(sliceLeftBias[1]) + abs(sliceLeftBias[2])

        // Heuristic Scoring per Piece Type
        var scores: [PieceType: Double] = [
            .pawn: 0, .knight: 0, .bishop: 0, .rook: 0, .queen: 0, .king: 0
        ]

        // Pawn: shorter height, narrowest top, smaller overall area
        if heightRatio < 0.72 { scores[.pawn, default: 0] += 3.0 }
        if coverage < 0.28 { scores[.pawn, default: 0] += 2.2 }
        if topWidth < 0.42 && midWidth < 0.56 { scores[.pawn, default: 0] += 1.6 }
        if topPeaks == 1 { scores[.pawn, default: 0] += 1.0 }

        // Rook: flat rectangular tower, wide top, 2-3 crenellation peaks, high fill density
        if topWidth > 0.58 { scores[.rook, default: 0] += 2.6 }
        if fillDensity > 0.62 { scores[.rook, default: 0] += 1.8 }
        if topPeaks >= 2 && topPeaks <= 3 { scores[.rook, default: 0] += 2.0 }
        if abs(topWidth - baseWidth) < 0.25 { scores[.rook, default: 0] += 1.2 }

        // Knight: strong upper-body horizontal asymmetry (snout facing left), medium-tall
        if asymmetry > 0.28 { scores[.knight, default: 0] += 3.2 }
        if heightRatio >= 0.70 { scores[.knight, default: 0] += 1.2 }
        if upperMidWidth > topWidth * 1.15 { scores[.knight, default: 0] += 1.4 }

        // Bishop: tall, pointed top (narrow slice 0), swelling middle, symmetric
        if heightRatio >= 0.74 { scores[.bishop, default: 0] += 1.5 }
        if topWidth < 0.36 && midWidth > 0.48 { scores[.bishop, default: 0] += 2.2 }
        if asymmetry < 0.22 && topPeaks == 1 { scores[.bishop, default: 0] += 1.4 }

        // Queen: tall, wide crown with >= 3 peaks, broad upper silhouette
        if heightRatio >= 0.78 { scores[.queen, default: 0] += 1.8 }
        if topPeaks >= 3 { scores[.queen, default: 0] += 3.2 }
        if topWidth > 0.55 && widthRatio > 0.72 { scores[.queen, default: 0] += 2.0 }

        // King: tallest piece, cross finial at top (narrow slice 0, wide slice 1/2), high coverage
        if heightRatio >= 0.82 { scores[.king, default: 0] += 2.6 }
        if coverage > 0.34 { scores[.king, default: 0] += 1.8 }
        if topWidth < 0.48 && upperMidWidth > 0.62 { scores[.king, default: 0] += 2.4 }
        if topPeaks <= 2 && asymmetry < 0.22 { scores[.king, default: 0] += 1.2 }

        let bestType = scores.max(by: { $0.value < $1.value })?.key ?? .pawn
        let kingLike = (scores[.king] ?? 0) / 8.0

        return (ChessPiece(color: pieceColor, type: bestType), 0.78, kingLike, coverage)
    }

    // MARK: - Helpers

    private func renderRGBABuffer(cgImage: CGImage, width: Int, height: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let ctx = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0.0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }
}
