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
}

final class ScreenshotBoardRecognizer: Sendable {
    static let shared = ScreenshotBoardRecognizer()

    private init() {}

    func recognizeBoard(
        from image: UIImage,
        fallbackPerspective: PieceColor = .white,
        sideToMove: PieceColor? = nil
    ) async -> RecognizedBoardResult? {
        guard let uprightCG = normalizedCGImage(from: image) else { return nil }
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

        // 2. Detect perspective via Vision OCR on board coordinate labels (a-h, 1-8)
        let detectedPerspective = await detectBoardPerspective(
            boardCGImage: croppedBoard,
            fallback: fallbackPerspective
        )

        // 3. Analyze surrounding header/footer for Fair-Play human timed match detection
        let matchContext = await analyzeMatchContext(
            fullCGImage: uprightCG,
            boardPixelRect: clampedRect
        )

        // 4. Classify 64 cells
        let classification = classify64Squares(
            boardCGImage: croppedBoard,
            perspective: detectedPerspective,
            sideToMove: sideToMove ?? detectedPerspective
        )

        let croppedUI = UIImage(cgImage: croppedBoard)
        let pngData = croppedUI.pngData()

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
            detectedPerspective: detectedPerspective,
            confidence: classification.confidence,
            notes: classification.notes,
            isLikelyHumanTimedGame: matchContext.isHumanTimed,
            isConfirmedBotMatch: matchContext.isBot,
            detectedMatchContextNote: matchContext.note
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
        var bestBox = CGRect(x: 0, y: Double(targetH) * 0.25, width: Double(minDim), height: Double(minDim))

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

            let yMin = max(0, Int(Double(targetH) * 0.05))
            let yMax = max(yMin, targetH - size - Int(Double(targetH) * 0.03))
            let yStep = 3

            for x in Set(xCandidates) {
                var y = yMin
                while y <= yMax {
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
                        bestBox = CGRect(x: x, y: y, width: size, height: size)
                    }
                    y += yStep
                }
            }
        }

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
                // Sample top-left corner of cell (less likely to be covered by a piece)
                let px = min(bufW - 1, max(0, x + Int((Double(c) + 0.14) * cell)))
                let py = min(bufH - 1, max(0, y + Int((Double(r) + 0.14) * cell)))
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
        guard contrast > 15.0 else { return -1.0 }

        // Count how many squares closely match their expected parity background
        var parityMatches = 0
        for l in lightLums where abs(l - lightMed) < 22.0 { parityMatches += 1 }
        for d in darkLums where abs(d - darkMed) < 22.0 { parityMatches += 1 }

        // Check sharp transitions along internal vertical boundaries (7 lines)
        var boundaryContrast = 0.0
        for r in 0..<8 {
            let py = min(bufH - 1, max(0, y + Int((Double(r) + 0.14) * cell)))
            for c in 1..<8 {
                let bxLeft = min(bufW - 1, max(0, x + Int(Double(c) * cell) - 2))
                let bxRight = min(bufW - 1, max(0, x + Int(Double(c) * cell) + 2))
                let iL = (py * bufW + bxLeft) * 4
                let iR = (py * bufW + bxRight) * 4
                let diff = abs(Double(rgba[iL]) - Double(rgba[iR]))
                    + abs(Double(rgba[iL + 1]) - Double(rgba[iR + 1]))
                    + abs(Double(rgba[iL + 2]) - Double(rgba[iR + 2]))
                boundaryContrast += min(diff, 150.0)
            }
        }
        boundaryContrast /= 56.0

        return contrast * 0.45 + Double(parityMatches) * 2.2 + boundaryContrast * 0.5
    }

    // MARK: - Orientation Detection via Vision OCR

    private func detectBoardPerspective(boardCGImage: CGImage, fallback: PieceColor) async -> PieceColor {
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

        return fallback
    }

    private func recognizeSingleCharLabel(in cgImage: CGImage?) async -> String? {
        guard let cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let observations = req.results as? [VNRecognizedTextObservation] ?? []
                let allText = observations
                    .compactMap { $0.topCandidates(1).first?.string.lowercased() }
                    .joined()
                for target in ["a", "h", "1", "8"] {
                    if allText.contains(target) {
                        continuation.resume(returning: target)
                        return
                    }
                }
                continuation.resume(returning: nil)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
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

        // Exclude top ~6.5% iOS status bar so phone system clock doesn't trigger false positives
        let topStripMinY = min(boardPixelRect.minY, imgH * 0.065)
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
            let request = VNRecognizeTextRequest { req, _ in
                let observations = req.results as? [VNRecognizedTextObservation] ?? []
                let joined = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                continuation.resume(returning: joined)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["zh-Hant", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "")
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

    private func classify64Squares(
        boardCGImage: CGImage,
        perspective: PieceColor,
        sideToMove: PieceColor
    ) -> (board: ChessBoardState, confidence: Double, notes: String) {
        let normSize = 400 // 50x50 px per square
        guard let rgba = renderRGBABuffer(cgImage: boardCGImage, width: normSize, height: normSize) else {
            return (ChessBoardState.startingPosition, 0.0, "無法讀取圖像像素")
        }

        let cellSize = 50
        // Estimate global light & dark square RGB from corners
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

        var grid: [[ChessPiece?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        var detectedPieceCount = 0
        var whiteKingCandidates: [(row: Int, col: Int, score: Double)] = []
        var blackKingCandidates: [(row: Int, col: Int, score: Double)] = []
        var pieceConfidenceSum = 0.0

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
                // Use local corner if square is highlighted (last move / check highlight), else global BG
                let bg = localCorner.distance(to: globalBG) > 18.0 ? localCorner : globalBG

                let boardRow = perspective == .white ? screenRow : (7 - screenRow)
                let boardCol = perspective == .white ? screenCol : (7 - screenCol)

                if let result = classifyCell(
                    rgba: rgba,
                    strideW: normSize,
                    screenRow: screenRow,
                    screenCol: screenCol,
                    cellSize: cellSize,
                    bg: bg
                ) {
                    grid[boardRow][boardCol] = result.piece
                    detectedPieceCount += 1
                    pieceConfidenceSum += result.confidence
                    if result.piece.type == .king || result.kingLikelihood > 0.45 {
                        if result.piece.color == .white {
                            whiteKingCandidates.append((boardRow, boardCol, result.kingLikelihood))
                        } else {
                            blackKingCandidates.append((boardRow, boardCol, result.kingLikelihood))
                        }
                    }
                }
            }
        }

        // Ensure exactly one white king and one black king if kings were swapped with queen
        ensureKingPresence(grid: &grid, color: .white, candidates: whiteKingCandidates)
        ensureKingPresence(grid: &grid, color: .black, candidates: blackKingCandidates)

        // Infer reasonable castling rights from current rook/king locations
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
            fullMoveNumber: 1
        )

        let avgConf = detectedPieceCount > 0 ? (pieceConfidenceSum / Double(detectedPieceCount)) : 0.65
        let note = "已辨識 \(detectedPieceCount) 枚棋子（視角：\(perspective.displayName)）"
        return (state, avgConf, note)
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

    private func sampleSquareCornerRGB(
        rgba: [UInt8],
        strideW: Int,
        row: Int,
        col: Int,
        cellSize: Int
    ) -> RGBColor {
        let baseX = col * cellSize
        let baseY = row * cellSize
        // Sample 4 outer corners of the cell (pixels 3..6 from edges, avoiding coordinate glyphs & piece center)
        let offsets = [
            (cellSize - 6, 4),
            (cellSize - 5, 5),
            (cellSize - 6, cellSize - 5),
            (4, cellSize - 5)
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

    private func classifyCell(
        rgba: [UInt8],
        strideW: Int,
        screenRow: Int,
        screenCol: Int,
        cellSize: Int,
        bg: RGBColor
    ) -> (piece: ChessPiece, confidence: Double, kingLikelihood: Double)? {
        let baseX = screenCol * cellSize
        let baseY = screenRow * cellSize
        let pad = 5 // analyze inner 40x40 of the 50x50 square
        let innerSize = cellSize - 2 * pad
        let distThreshold = 34.0

        var mask = Array(repeating: Array(repeating: false, count: innerSize), count: innerSize)
        var fgLums: [Double] = []
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
                    fgLums.append(pixel.luminance)
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

        // Determine Piece Color (White vs Black) using upper-quartile & median luminance
        let sortedLums = fgLums.sorted()
        let p75Lum = sortedLums[min(sortedLums.count - 1, Int(Double(sortedLums.count) * 0.72))]
        let p50Lum = sortedLums[sortedLums.count / 2]
        let brightRatio = Double(sortedLums.filter { $0 > 180.0 }.count) / Double(sortedLums.count)
        let darkRatio = Double(sortedLums.filter { $0 < 95.0 }.count) / Double(sortedLums.count)

        let pieceColor: PieceColor
        if p75Lum > 175.0 && (brightRatio > 0.25 || p50Lum > 150.0) {
            pieceColor = .white
        } else if darkRatio > 0.35 || p50Lum < 120.0 {
            pieceColor = .black
        } else {
            pieceColor = p75Lum > 165.0 ? .white : .black
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

        return (ChessPiece(color: pieceColor, type: bestType), 0.78, kingLike)
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
