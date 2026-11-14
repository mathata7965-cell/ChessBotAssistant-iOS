import Foundation

@MainActor
final class ChessEngineService: ObservableObject {
    @Published var targetDepth: Int = 12
    @Published var multiPVCount: Int = 3
    @Published var autoHintEnabled: Bool = true
    @Published var useCloudStockfish: Bool = true

    // 防誤封與隱私隔離保護設定
    @Published var zeroNetworkIsolationMode: Bool = false
    @Published var humanMatchSafetyLockEnabled: Bool = true
    @Published var coachPieceOnlyHintMode: Bool = false

    // 下棋風格與進階戰術視覺化設定
    @Published var playStyleMode: PlayStyleMode = .engineBest
    @Published var botTargetProfile: BotTargetProfile = .universal
    @Published var showOpponentReplyArrow: Bool = true

    @Published private(set) var isAnalyzing: Bool = false
    @Published private(set) var currentAnalysis: EngineAnalysisResult?
    @Published private(set) var lastErrorMessage: String?

    private var activeTask: Task<Void, Never>?
    private var cloudCache: [String: EngineAnalysisResult] = [:]
    private var lastRawAnalysis: EngineAnalysisResult?
    private var lastRawPositionKey: String?

    @discardableResult
    func reapplyPlayStyle(for board: ChessBoardState) -> Bool {
        guard lastRawPositionKey == board.positionKey, let raw = lastRawAnalysis else { return false }
        currentAnalysis = Self.applyPlayStyle(playStyleMode, botProfile: botTargetProfile, to: raw, board: board)
        return true
    }

    func cancelAnalysis() {
        activeTask?.cancel()
        activeTask = nil
        isAnalyzing = false
    }

    func analyze(board: ChessBoardState) {
        activeTask?.cancel()
        lastErrorMessage = nil

        let legal = board.legalMoves()
        let fen = board.toFEN()

        if legal.isEmpty {
            isAnalyzing = false
            let inCheck = board.isKingInCheck(board.sideToMove)
            let winnerCP = inCheck ? (board.sideToMove == .white ? -30000 : 30000) : 0
            let mateVal: Int? = inCheck ? (board.sideToMove == .white ? -0 : 0) : nil
            currentAnalysis = EngineAnalysisResult(
                fen: fen,
                sideToMove: board.sideToMove,
                lines: [],
                depthReached: 0,
                isCloudVerified: false,
                engineSource: inCheck ? "將殺結束" : "逼和結束",
                nodesSearched: 0,
                timestamp: Date()
            )
            _ = (winnerCP, mateVal)
            return
        }

        let requestedDepth = max(4, min(18, targetDepth))
        let requestedPV = max(1, min(3, multiPVCount))
        let isZeroNetwork = zeroNetworkIsolationMode
        let allowCloud = useCloudStockfish && !isZeroNetwork
        let activeStyle = playStyleMode
        let activeBotProfile = botTargetProfile
        let cacheKey = "\(board.positionKey)|d\(requestedDepth)|pv\(requestedPV)"

        // 0. Check bundled 10MB Offline GM Engine Pack opening book first (0ms response)
        if let bookHit = OfflineEnginePack.shared.lookupBookLines(for: board, multiPV: requestedPV),
           !bookHit.lines.isEmpty {
            let bookResult = EngineAnalysisResult(
                fen: fen,
                sideToMove: board.sideToMove,
                lines: bookHit.lines,
                depthReached: 20,
                isCloudVerified: true,
                engineSource: "📚 離線大師開局庫 (\(OfflineEnginePack.shared.packSizeMBString))",
                nodesSearched: bookHit.lines.count,
                timestamp: Date()
            )
            lastRawAnalysis = bookResult
            lastRawPositionKey = board.positionKey
            currentAnalysis = Self.applyPlayStyle(activeStyle, botProfile: activeBotProfile, to: bookResult, board: board)
            if !allowCloud || bookHit.lines.count >= requestedPV {
                isAnalyzing = false
                return
            }
        }

        if allowCloud, let cached = cloudCache[cacheKey] {
            lastRawAnalysis = cached
            lastRawPositionKey = board.positionKey
            currentAnalysis = Self.applyPlayStyle(activeStyle, botProfile: activeBotProfile, to: cached, board: board)
            isAnalyzing = false
            return
        }

        isAnalyzing = true

        activeTask = Task { [weak self] in
            guard let self else { return }

            // 1. Run local fast Multi-PV engine and Cloud query in parallel
            let localMaxDepth = isZeroNetwork ? min(requestedDepth, 6) : min(requestedDepth, 5)
            let localBudget: TimeInterval = isZeroNetwork ? 0.85 : 0.40

            async let cloudTask: EngineAnalysisResult? = allowCloud
                ? self.fetchCloudAnalysis(board: board, requestedDepth: requestedDepth, multiPV: requestedPV)
                : nil

            let localResult = await Task.detached(priority: .userInitiated) {
                LocalAlphaBetaEngine.analyze(
                    board: board,
                    maxDepth: localMaxDepth,
                    multiPV: requestedPV,
                    timeBudgetSeconds: localBudget,
                    isZeroNetworkMode: isZeroNetwork
                )
            }.value

            if Task.isCancelled { return }
            self.lastRawAnalysis = localResult
            self.lastRawPositionKey = board.positionKey
            self.currentAnalysis = Self.applyPlayStyle(self.playStyleMode, botProfile: self.botTargetProfile, to: localResult, board: board)

            // 2. If Cloud Stockfish is disabled or Zero-Network Isolation is active, finish strictly offline
            guard allowCloud else {
                self.isAnalyzing = false
                return
            }

            // 3. Await parallel Cloud Stockfish 16 NNUE result and merge fallback lines
            if let rawCloud = await cloudTask {
                if Task.isCancelled { return }
                let mergedCloud = Self.mergeCloudWithLocalFallback(
                    cloud: rawCloud,
                    localLines: localResult.lines,
                    multiPV: requestedPV
                )
                self.cloudCache[cacheKey] = mergedCloud
                self.lastRawAnalysis = mergedCloud
                self.lastRawPositionKey = board.positionKey
                self.currentAnalysis = Self.applyPlayStyle(self.playStyleMode, botProfile: self.botTargetProfile, to: mergedCloud, board: board)
            }

            if !Task.isCancelled {
                self.isAnalyzing = false
            }
        }
    }

    // MARK: - Cloud Stockfish Integration

    private static func mergeCloudWithLocalFallback(
        cloud: EngineAnalysisResult,
        localLines: [PVLine],
        multiPV: Int
    ) -> EngineAnalysisResult {
        guard cloud.lines.count < multiPV else { return cloud }
        var merged = cloud.lines
        let existingUCIs = Set(merged.map { $0.bestMove.uci })
        var nextIdx = merged.count + 1

        for local in localLines where !existingUCIs.contains(local.bestMove.uci) {
            if merged.count >= multiPV { break }
            merged.append(PVLine(
                multipvIndex: nextIdx,
                bestMove: local.bestMove,
                continuationSAN: local.continuationSAN,
                continuationUCI: local.continuationUCI,
                scoreCentipawns: local.scoreCentipawns,
                mateInMoves: local.mateInMoves,
                depth: local.depth,
                sourceLabel: "本地備選",
                predictedOpponentReply: local.predictedOpponentReply
            ))
            nextIdx += 1
        }

        return EngineAnalysisResult(
            fen: cloud.fen,
            sideToMove: cloud.sideToMove,
            lines: merged,
            depthReached: cloud.depthReached,
            isCloudVerified: cloud.isCloudVerified,
            engineSource: cloud.engineSource,
            nodesSearched: cloud.nodesSearched,
            timestamp: cloud.timestamp
        )
    }

    private func fetchCloudAnalysis(
        board: ChessBoardState,
        requestedDepth: Int,
        multiPV: Int
    ) async -> EngineAnalysisResult? {
        let sfDepth = min(max(requestedDepth, 10), 15)
        async let lichessTask = queryLichessCloudEval(board: board, multiPV: multiPV)
        async let sfOnlineTask = queryStockfishOnline(board: board, depth: sfDepth)

        // Prefer Lichess Cloud Eval (supports Multi-PV natively)
        if let lichessLines = await lichessTask, !lichessLines.lines.isEmpty {
            return EngineAnalysisResult(
                fen: board.toFEN(),
                sideToMove: board.sideToMove,
                lines: Array(lichessLines.lines.prefix(multiPV)),
                depthReached: lichessLines.depth,
                isCloudVerified: true,
                engineSource: "Stockfish NNUE (Lichess Cloud)",
                nodesSearched: lichessLines.knodes * 1000,
                timestamp: Date()
            )
        }

        if Task.isCancelled { return nil }

        // Fallback to stockfish.online API (already running in parallel)
        if let sfLine = await sfOnlineTask {
            return EngineAnalysisResult(
                fen: board.toFEN(),
                sideToMove: board.sideToMove,
                lines: [sfLine],
                depthReached: sfDepth,
                isCloudVerified: true,
                engineSource: "Stockfish 16 NNUE",
                nodesSearched: 0,
                timestamp: Date()
            )
        }

        return nil
    }

    private func queryLichessCloudEval(board: ChessBoardState, multiPV: Int) async -> (lines: [PVLine], depth: Int, knodes: Int)? {
        let fen = board.toFEN()
        guard var components = URLComponents(string: "https://lichess.org/api/cloud-eval") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "fen", value: fen),
            URLQueryItem(name: "multiPv", value: String(multiPV))
        ]
        guard let url = components.url else { return nil }

        var req = URLRequest(url: url, timeoutInterval: 2.2)
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(LichessCloudEvalResponse.self, from: data)
            let depth = decoded.depth ?? 20
            var parsedLines: [PVLine] = []

            for (idx, pv) in decoded.pvs.enumerated() {
                let uciTokens = pv.moves.split(separator: " ").map { String($0) }
                guard let firstUCI = uciTokens.first,
                      let firstMove = board.legalMove(uci: firstUCI) else { continue }

                let sanLine = Self.convertUCILineToSAN(startBoard: board, uciMoves: uciTokens)
                let cp: Int
                if let mate = pv.mate {
                    cp = mate > 0 ? (30000 - abs(mate) * 10) : (-30000 + abs(mate) * 10)
                } else {
                    cp = pv.cp ?? 0
                }

                parsedLines.append(PVLine(
                    multipvIndex: idx + 1,
                    bestMove: firstMove,
                    continuationSAN: sanLine,
                    continuationUCI: uciTokens,
                    scoreCentipawns: cp,
                    mateInMoves: pv.mate,
                    depth: depth,
                    sourceLabel: "SF Cloud",
                    predictedOpponentReply: Self.extractOpponentReply(
                        on: board,
                        firstMove: firstMove,
                        continuationUCI: uciTokens
                    )
                ))
            }
            return (parsedLines, depth, decoded.knodes ?? 0)
        } catch {
            return nil
        }
    }

    private func queryStockfishOnline(board: ChessBoardState, depth: Int) async -> PVLine? {
        let fen = board.toFEN()
        guard var components = URLComponents(string: "https://stockfish.online/api/s/v2.php") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "fen", value: fen),
            URLQueryItem(name: "depth", value: String(depth))
        ]
        guard let url = components.url else { return nil }

        let req = URLRequest(url: url, timeoutInterval: 4.0)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(StockfishOnlineResponse.self, from: data)
            guard decoded.success else { return nil }

            let bestParts = (decoded.bestmove ?? "").split(separator: " ").map { String($0) }
            let bestUCI: String?
            if bestParts.count >= 2 && bestParts[0] == "bestmove" {
                bestUCI = bestParts[1]
            } else {
                bestUCI = bestParts.first
            }

            let contTokens = (decoded.continuation ?? "").split(separator: " ").map { String($0) }
            let primaryUCI = bestUCI ?? contTokens.first
            guard let uci = primaryUCI,
                  let bestMove = board.legalMove(uci: uci) else { return nil }

            let fullUCI: [String]
            if contTokens.first == uci {
                fullUCI = contTokens
            } else {
                fullUCI = [uci] + contTokens.filter { $0 != uci }
            }

            let sanLine = Self.convertUCILineToSAN(startBoard: board, uciMoves: fullUCI)
            let cp: Int
            if let mate = decoded.mate {
                cp = mate > 0 ? (30000 - abs(mate) * 10) : (-30000 + abs(mate) * 10)
            } else {
                cp = Int(((decoded.evaluation ?? 0.0) * 100.0).rounded())
            }

            return PVLine(
                multipvIndex: 1,
                bestMove: bestMove,
                continuationSAN: sanLine,
                continuationUCI: fullUCI,
                scoreCentipawns: cp,
                mateInMoves: decoded.mate,
                depth: depth,
                sourceLabel: "SF16 NNUE",
                predictedOpponentReply: Self.extractOpponentReply(
                    on: board,
                    firstMove: bestMove,
                    continuationUCI: fullUCI
                )
            )
        } catch {
            return nil
        }
    }

    nonisolated static func extractOpponentReply(
        on board: ChessBoardState,
        firstMove: ChessMove,
        continuationUCI: [String]
    ) -> ChessMove? {
        let afterFirst = board.applying(firstMove)
        if let secondUCI = continuationUCI.dropFirst().first,
           let reply = afterFirst.legalMove(uci: secondUCI) {
            return reply
        }

        let opponentMoves = afterFirst.legalMoves()
        guard !opponentMoves.isEmpty else { return nil }
        var bestReply = opponentMoves[0]
        var bestVal = -Int.max
        for move in opponentMoves {
            let afterOpp = afterFirst.applyingRaw(move)
            let val = -LocalAlphaBetaEngine.evaluate(board: afterOpp)
            if val > bestVal {
                bestVal = val
                bestReply = move
            }
        }
        return bestReply
    }

    nonisolated static func applyPlayStyle(
        _ style: PlayStyleMode,
        botProfile: BotTargetProfile = .universal,
        to result: EngineAnalysisResult,
        board: ChessBoardState
    ) -> EngineAnalysisResult {
        guard (style != .engineBest || botProfile != .universal), result.lines.count > 1 else {
            return result
        }

        let sideMultiplier = board.sideToMove == .white ? 1 : -1
        let bestCpForSide = (result.lines.first?.scoreCentipawns ?? 0) * sideMultiplier
        let styleTolerance: Int
        switch style {
        case .engineBest: styleTolerance = 0
        case .humanSafe: styleTolerance = 30
        case .aggressive: styleTolerance = 45
        case .defensive: styleTolerance = 35
        }
        let profileTolerance: Int
        switch botProfile {
        case .universal: profileTolerance = 0
        case .antiNelson: profileTolerance = 40
        case .beginnerCrusher: profileTolerance = 45
        case .antiMaster: profileTolerance = 25
        }
        let toleranceCp = max(styleTolerance, profileTolerance)

        let enemyColor = board.sideToMove.opposite
        var enemyQueenSq: BoardSquare? = nil
        outer: for r in 0..<8 {
            for c in 0..<8 {
                if let p = board.squares[r][c], p.color == enemyColor, p.type == .queen {
                    enemyQueenSq = BoardSquare(row: r, col: c)
                    break outer
                }
            }
        }

        func styleBonus(for line: PVLine) -> Int {
            let lineCpForSide = line.scoreCentipawns * sideMultiplier
            if line.mateInMoves == nil && (bestCpForSide - lineCpForSide) > toleranceCp {
                return -10_000
            }
            var bonus = 0
            let san = line.bestMove.san
            let move = line.bestMove
            let after = board.applying(move)
            let isInDangerAfter = after.isSquareAttacked(row: move.to.row, col: move.to.col, by: enemyColor)
                && !after.isSquareAttacked(row: move.to.row, col: move.to.col, by: board.sideToMove)

            switch style {
            case .engineBest:
                break
            case .aggressive:
                if san.contains("#") { bonus += 500 }
                if san.contains("+") { bonus += 90 }
                if move.capturedPiece != nil { bonus += 70 }
                if move.promotion != nil { bonus += 80 }
            case .defensive:
                if move.isCastling { bonus += 100 }
                if !isInDangerAfter { bonus += 60 }
                if move.capturedPiece == nil && !san.contains("+") { bonus += 35 }
            case .humanSafe:
                if !isInDangerAfter { bonus += 40 }
                if move.isCastling { bonus += 60 }
                if let p = board.piece(at: move.from), p.type == .knight || p.type == .bishop {
                    bonus += 30
                }
            }

            switch botProfile {
            case .universal:
                break
            case .antiNelson:
                if move.capturedPiece?.type == .queen {
                    bonus += 600
                } else if let qSq = enemyQueenSq,
                          !isInDangerAfter,
                          after.isSquareAttacked(row: qSq.row, col: qSq.col, by: board.sideToMove) {
                    bonus += 140
                }
                if board.fullMoveNumber <= 12,
                   let p = board.piece(at: move.from),
                   p.type == .knight || p.type == .bishop || move.isCastling {
                    bonus += 55
                }
            case .beginnerCrusher:
                if san.contains("#") { bonus += 600 }
                if san.contains("+") { bonus += 110 }
                if move.capturedPiece != nil { bonus += 80 }
            case .antiMaster:
                if !isInDangerAfter { bonus += 75 }
                if move.isCastling { bonus += 95 }
                if let p = board.piece(at: move.from),
                   !(p.type == .pawn && board.fullMoveNumber <= 16 && (move.from.col >= 5 || move.from.col <= 2)) {
                    bonus += 30
                }
            }
            return bonus
        }

        let ranked = result.lines.sorted { a, b in
            let sa = styleBonus(for: a)
            let sb = styleBonus(for: b)
            if sa != sb { return sa > sb }
            return a.scoreCentipawns * sideMultiplier > b.scoreCentipawns * sideMultiplier
        }

        let modeTag = style == .engineBest ? botProfile.shortName : style.displayName
        let reindexed: [PVLine] = ranked.enumerated().map { idx, line in
            var moveCopy = line.bestMove
            if idx == 0 && (moveCopy.tacticalTag == nil || moveCopy.tacticalTag?.isEmpty == true) {
                moveCopy.tacticalTag = modeTag
            }
            return PVLine(
                multipvIndex: idx + 1,
                bestMove: moveCopy,
                continuationSAN: line.continuationSAN,
                continuationUCI: line.continuationUCI,
                scoreCentipawns: line.scoreCentipawns,
                mateInMoves: line.mateInMoves,
                depth: line.depth,
                sourceLabel: "\(line.sourceLabel)•\(modeTag)",
                predictedOpponentReply: line.predictedOpponentReply
            )
        }

        return EngineAnalysisResult(
            fen: result.fen,
            sideToMove: result.sideToMove,
            lines: reindexed,
            depthReached: result.depthReached,
            isCloudVerified: result.isCloudVerified,
            engineSource: "\(result.engineSource)（\(modeTag)）",
            nodesSearched: result.nodesSearched,
            timestamp: result.timestamp
        )
    }

    nonisolated static func convertUCILineToSAN(startBoard: ChessBoardState, uciMoves: [String]) -> [String] {
        var cursor = startBoard
        var result: [String] = []
        for uci in uciMoves.prefix(10) {
            guard let legal = cursor.legalMove(uci: uci) else { break }
            result.append(legal.san)
            cursor = cursor.applying(legal)
        }
        return result
    }
}

private struct LichessCloudEvalResponse: Decodable {
    struct PV: Decodable {
        let moves: String
        let cp: Int?
        let mate: Int?
    }
    let depth: Int?
    let knodes: Int?
    let pvs: [PV]
}

private struct StockfishOnlineResponse: Decodable {
    let success: Bool
    let evaluation: Double?
    let mate: Int?
    let bestmove: String?
    let continuation: String?
}

// MARK: - Built-in Offline PeSTO Tapered Alpha-Beta Multi-PV Engine

private enum LocalAlphaBetaEngine {
    private static let mateScore = 30000

    // Middlegame & Endgame piece values
    private static let mgValues: [PieceType: Int] = [
        .pawn: 82, .knight: 337, .bishop: 365, .rook: 477, .queen: 1025, .king: 0
    ]
    private static let egValues: [PieceType: Int] = [
        .pawn: 94, .knight: 281, .bishop: 297, .rook: 512, .queen: 936, .king: 0
    ]
    private static let phaseWeights: [PieceType: Int] = [
        .pawn: 0, .knight: 1, .bishop: 1, .rook: 2, .queen: 4, .king: 0
    ]

    // PeSTO Piece-Square Tables (White orientation, index 0 = rank 8, index 63 = rank 1)
    private static let mgPawnPST: [Int] = [
          0,   0,   0,   0,   0,   0,  0,   0,
         98, 134,  61,  95,  68, 126, 34, -11,
         -6,   7,  26,  31,  65,  56, 25, -20,
        -14,  13,   6,  21,  23,  12, 17, -23,
        -27,  -2,  -5,  12,  17,   6, 10, -25,
        -26,  -4,  -4, -10,   3,   3, 33, -12,
        -35,  -1, -20, -23, -15,  24, 38, -22,
          0,   0,   0,   0,   0,   0,  0,   0
    ]

    private static let egPawnPST: [Int] = [
          0,   0,   0,   0,   0,   0,   0,   0,
        178, 173, 158, 134, 147, 132, 165, 187,
         94, 100,  85,  67,  56,  53,  82,  84,
         32,  24,  13,   5,  -2,   4,  17,  17,
         13,   9,  -3,  -7,  -7,  -8,   3,  -1,
          4,   7,  -6,   1,   0,  -5,  -1,  -8,
         13,   8,   8,  10,  13,   0,   2,  -7,
          0,   0,   0,   0,   0,   0,   0,   0
    ]

    private static let mgKnightPST: [Int] = [
        -167, -89, -34, -49,  61, -97, -15, -107,
         -73, -41,  72,  36,  23,  62,   7,  -17,
         -47,  60,  37,  65,  84, 129,  73,   44,
          -9,  17,  19,  53,  37,  69,  18,   22,
         -13,   4,  16,  13,  28,  19,  21,   -8,
         -23,  -9,  12,  10,  19,  17,  25,  -16,
         -29, -53, -12,  -3,  -1,  18, -14,  -19,
        -105, -21, -58, -33, -17, -28, -19,  -23
    ]

    private static let mgBishopPST: [Int] = [
        -29,   4, -82, -37, -25, -42,   7,  -8,
        -26,  16, -18, -13,  30,  59,  18, -47,
        -16,  37,  43,  40,  35,  50,  37,  -2,
         -4,   5,  19,  50,  37,  37,   7,  -2,
         -6,  13,  13,  26,  34,  12,  10,   4,
          0,  15,  15,  15,  14,  27,  18,  10,
          4,  15,  16,   0,   7,  21,  33,   1,
        -33,  -3, -14, -21, -13, -12, -39, -21
    ]

    private static let mgRookPST: [Int] = [
         32,  42,  32,  51, 63,  9,  31,  43,
         27,  32,  58,  62, 80, 67,  26,  44,
         -5,  19,  26,  36, 17, 45,  61,  16,
        -24, -11,   7,  26, 24, 35,  -8, -20,
        -36, -26, -12,  -1,  9, -7,   6, -23,
        -45, -25, -16, -17,  3,  0,  -5, -33,
        -44, -16, -20,  -9, -1, 11,  -6, -71,
        -19, -13,   1,  17, 16,  7, -37, -26
    ]

    private static let mgQueenPST: [Int] = [
        -28,   0,  29,  12,  59,  44,  43,  45,
        -24, -39,  -5,   1, -16,  57,  28,  54,
        -13, -17,   7,   8,  29,  56,  47,  57,
        -27, -27, -16, -16,  -1,  17,  -2,   1,
         -9, -26,  -9, -10,  -2,  -4,   3,  -3,
        -14,   2, -11,  -2,  -5,   2,  14,   5,
        -35,  -8,  11,   2,   8,  15,  -3,   1,
         -1, -18,  -9,  10, -15, -25, -31, -50
    ]

    private static let mgKingPST: [Int] = [
        -65,  23,  16, -15, -56, -34,   2,  13,
         29,  -1, -20,  -7,  -8,  -4, -38, -29,
         -9,  24,   2, -16, -20,   6,  22, -22,
        -17, -20, -12, -27, -30, -25, -14, -36,
        -49,  -1, -27, -39, -46, -44, -33, -51,
        -14, -14, -22, -46, -44, -30, -15, -27,
          1,   7,  -8, -64, -43, -16,   9,   8,
        -15,  36,  12, -54,   8, -28,  24,  14
    ]

    private static let egKingPST: [Int] = [
        -74, -35, -18, -18, -11,  15,   4, -17,
        -12,  17,  14,  17,  17,  38,  23,  11,
         10,  17,  23,  15,  20,  45,  44,  13,
         -8,  22,  24,  27,  26,  33,  26,   3,
        -18,  -4,  21,  24,  27,  23,   9, -11,
        -19,  -3,  11,  21,  23,  16,   7,  -9,
        -27, -11,   4,  13,  14,   4,  -5, -17,
        -53, -33, -21, -11, -28, -14, -24, -43
    ]

    private static let egKnightPST: [Int] = [
        -58, -38, -13, -28, -31, -27, -63, -99,
        -25,  -8, -25,  -2,  -9, -25, -24, -52,
        -24, -20,  10,   9,  -1,  -9, -19, -41,
        -17,   3,  22,  22,  22,  11,   8, -18,
        -18,  -6,  16,  25,  16,  17,   4, -18,
        -23,  -3,  -1,  15,  10,  -3, -20, -22,
        -42, -20, -10,  -5,  -2, -20, -23, -44,
        -29, -51, -23, -15, -22, -18, -50, -64
    ]

    private static let egBishopPST: [Int] = [
        -14, -21, -11,  -8,  -7,  -9, -17, -24,
         -8,  -4,   7, -12,  -3, -13,  -4, -14,
          2,  -8,   0,  -1,  -2,   6,   0,   4,
         -3,   9,  12,   9,  14,  10,   3,   2,
         -6,   3,  13,  19,   7,  10,  -3,  -9,
        -12,  -3,   8,  10,  13,   3,  -7, -15,
        -14, -18,  -7,  -1,   4,  -9, -15, -27,
        -23,  -9, -23,  -5,  -9, -16,  -5, -17
    ]

    private static let egRookPST: [Int] = [
         13,  10,  18,  15,  12,  12,   8,   5,
         11,  13,  13,  11,  -3,   3,   8,   3,
          7,   7,   7,   5,   4,  -3,  -5,  -3,
          4,   3,  13,   1,   2,   1,  -1,   2,
          3,   5,   8,   4,  -5,  -6,  -8, -11,
         -4,   0,  -5,  -1,  -7, -12,  -8, -16,
         -6,  -6,   0,   2,  -9,  -9, -11,  -3,
         -9,   2,   3,  -1,  -5, -13,   4, -20
    ]

    private static let egQueenPST: [Int] = [
         -9,  22,  22,  27,  27,  19,  10,  20,
        -17,  20,  32,  41,  58,  25,  30,   0,
        -20,   6,   9,  49,  47,  35,  19,   9,
          3,  22,  24,  45,  57,  40,  57,  36,
        -18,  28,  19,  47,  31,  34,  39,  23,
        -16, -27,  15,   6,   9,  17,  10,   5,
        -22, -23, -30, -16, -16, -23, -36, -32,
        -33, -28, -22, -43,  -5, -32, -20, -41
    ]

    private struct TTEntry {
        var key: UInt64 = 0
        var depth: Int = -1
        var score: Int = 0
        var flag: UInt8 = 0
        var bestUCI: String = ""
    }

    private final class SearchContext {
        var nodes: Int = 0
        let deadline: Date
        var cancelled: Bool = false
        var tt: [TTEntry] = Array(repeating: TTEntry(), count: 16_384)
        var killers: [[String]] = Array(repeating: [], count: 32)

        init(deadline: Date) {
            self.deadline = deadline
        }

        func recordKiller(_ uci: String, ply: Int) {
            guard ply >= 0 && ply < killers.count else { return }
            if killers[ply].first == uci { return }
            killers[ply].insert(uci, at: 0)
            if killers[ply].count > 2 {
                killers[ply].removeLast()
            }
        }
    }

    private static func rootPositionalTieBreaker(for move: ChessMove, board: ChessBoardState) -> Int {
        var bonus = 0
        let openingBonuses: [String: Int] = [
            "e2e4": 12, "d2d4": 11, "f1b5": 9, "f1c4": 8,
            "g1f3": 6, "b1c3": 5, "c2c4": 6,
            "e7e5": 11, "d7d5": 10, "c7c5": 10, "g8f6": 6,
            "e7e6": 6, "c7c6": 5
        ]
        if board.fullMoveNumber <= 8, let openBonus = openingBonuses[move.uci] {
            bonus += openBonus
        }

        if let piece = board.piece(at: move.from) {
            if piece.type == .king && abs(move.to.col - move.from.col) == 2 {
                bonus += 6
            }
            let homeRow = piece.color == .white ? 7 : 0
            if (piece.type == .knight || piece.type == .bishop) && move.from.row == homeRow && move.to.row != homeRow {
                bonus += 3
            }
            if (3...4).contains(move.to.row) && (3...4).contains(move.to.col) {
                bonus += 3
            } else if (2...5).contains(move.to.row) && (2...5).contains(move.to.col) {
                bonus += 1
            }
            if piece.type == .pawn && board.fullMoveNumber <= 6 && (move.from.col == 0 || move.from.col == 7) {
                bonus -= 2
            }
        }
        return bonus
    }

    static func analyze(
        board: ChessBoardState,
        maxDepth: Int,
        multiPV: Int,
        timeBudgetSeconds: TimeInterval,
        isZeroNetworkMode: Bool = false
    ) -> EngineAnalysisResult {
        let rootMoves = board.legalMoves()
        let fen = board.toFEN()
        guard !rootMoves.isEmpty else {
            return EngineAnalysisResult(
                fen: fen,
                sideToMove: board.sideToMove,
                lines: [],
                depthReached: 0,
                isCloudVerified: false,
                engineSource: "本地引擎 (PeSTO)",
                nodesSearched: 0,
                timestamp: Date()
            )
        }

        let ctx = SearchContext(deadline: Date().addingTimeInterval(timeBudgetSeconds))
        var bestScoredMoves: [(move: ChessMove, scoreFromSideToMove: Int, pv: [ChessMove])] = []
        var completedDepth = 1

        let orderedInitial = orderMoves(rootMoves, board: board, pvHintUCI: nil)

        // Iterative deepening over root moves
        for depth in 1...max(1, maxDepth) {
            if Date() > ctx.deadline && depth > 1 { break }
            var currentResults: [(move: ChessMove, scoreFromSideToMove: Int, pv: [ChessMove])] = []
            let candidates = bestScoredMoves.isEmpty ? orderedInitial : bestScoredMoves.map(\.move)

            for move in candidates {
                if Date() > ctx.deadline && !bestScoredMoves.isEmpty {
                    ctx.cancelled = true
                    break
                }
                let nextBoard = board.applyingRaw(move)
                var childPV: [ChessMove] = []
                let score = -negamax(
                    board: nextBoard,
                    depth: depth - 1,
                    ply: 1,
                    alpha: -mateScore,
                    beta: mateScore,
                    ctx: ctx,
                    pvOut: &childPV
                )
                if ctx.cancelled { break }
                let tieBreaker = abs(score) < mateScore - 200
                    ? rootPositionalTieBreaker(for: move, board: board)
                    : 0
                currentResults.append((move, score + tieBreaker, [move] + childPV))
            }

            if !ctx.cancelled && !currentResults.isEmpty {
                currentResults.sort { $0.scoreFromSideToMove > $1.scoreFromSideToMove }
                bestScoredMoves = currentResults
                completedDepth = depth
            } else {
                break
            }
        }

        if bestScoredMoves.isEmpty {
            bestScoredMoves = orderedInitial.map { ($0, rootPositionalTieBreaker(for: $0, board: board), [$0]) }
        }

        let pvCount = min(multiPV, bestScoredMoves.count)
        var pvLines: [PVLine] = []

        for idx in 0..<pvCount {
            let entry = bestScoredMoves[idx]
            let rawScore = entry.scoreFromSideToMove
            let whiteCP = board.sideToMove == .white ? rawScore : -rawScore

            var mateMoves: Int? = nil
            if abs(rawScore) > mateScore - 200 {
                let plyToMate = mateScore - abs(rawScore)
                let fullMoves = max(1, (plyToMate + 1) / 2)
                if rawScore > 0 {
                    mateMoves = board.sideToMove == .white ? fullMoves : -fullMoves
                } else {
                    mateMoves = board.sideToMove == .white ? -fullMoves : fullMoves
                }
            }

            let uciLine = entry.pv.map(\.uci)
            let sanLine = ChessEngineService.convertUCILineToSAN(startBoard: board, uciMoves: uciLine)

            pvLines.append(PVLine(
                multipvIndex: idx + 1,
                bestMove: entry.move,
                continuationSAN: sanLine,
                continuationUCI: uciLine,
                scoreCentipawns: whiteCP,
                mateInMoves: mateMoves,
                depth: completedDepth,
                sourceLabel: "本地 D\(completedDepth)",
                predictedOpponentReply: ChessEngineService.extractOpponentReply(
                    on: board,
                    firstMove: entry.move,
                    continuationUCI: uciLine
                )
            ))
        }

        return EngineAnalysisResult(
            fen: fen,
            sideToMove: board.sideToMove,
            lines: pvLines,
            depthReached: completedDepth,
            isCloudVerified: false,
            engineSource: isZeroNetworkMode
                ? "🔒 本機零連網安全引擎 (D\(completedDepth))"
                : "本地離線引擎 (D\(completedDepth))",
            nodesSearched: ctx.nodes,
            timestamp: Date()
        )
    }

    private static func negamax(
        board: ChessBoardState,
        depth: Int,
        ply: Int,
        alpha: Int,
        beta: Int,
        ctx: SearchContext,
        pvOut: inout [ChessMove]
    ) -> Int {
        if ctx.cancelled || (ctx.nodes & 1023 == 0 && Date() > ctx.deadline) {
            ctx.cancelled = true
            return 0
        }

        if depth <= 0 {
            return quiescence(board: board, alpha: alpha, beta: beta, ply: ply, ctx: ctx)
        }

        ctx.nodes += 1

        let zKey = OfflineEnginePack.shared.computeZobristHash(for: board)
        let ttIdx = Int(zKey & 16_383)
        let ttEntry = ctx.tt[ttIdx]
        var curAlpha = alpha
        var curBeta = beta
        var ttHint: String? = nil

        if ttEntry.key == zKey && ttEntry.flag != 0 {
            ttHint = ttEntry.bestUCI.isEmpty ? nil : ttEntry.bestUCI
            if ttEntry.depth >= depth && abs(ttEntry.score) < mateScore - 500 {
                if ttEntry.flag == 1 {
                    if let hint = ttHint, let m = board.legalMove(uci: hint) {
                        pvOut = [m]
                    }
                    return ttEntry.score
                } else if ttEntry.flag == 2 {
                    curAlpha = max(curAlpha, ttEntry.score)
                } else if ttEntry.flag == 3 {
                    curBeta = min(curBeta, ttEntry.score)
                }
                if curAlpha >= curBeta {
                    if let hint = ttHint, let m = board.legalMove(uci: hint) {
                        pvOut = [m]
                    }
                    return ttEntry.score
                }
            }
        }

        let legal = board.legalMoves(includeFormattedSAN: false)

        if legal.isEmpty {
            if board.isKingInCheck(board.sideToMove) {
                return -mateScore + ply
            }
            return 0
        }

        let killerUCIs = ply < ctx.killers.count ? ctx.killers[ply] : []
        let ordered = orderMoves(legal, board: board, pvHintUCI: ttHint, killerUCIs: killerUCIs)
        let origAlpha = curAlpha
        var bestAlpha = curAlpha
        var bestPV: [ChessMove] = []
        var bestUCI = ordered.first?.uci ?? ""

        for move in ordered {
            let next = board.applyingRaw(move)
            var childPV: [ChessMove] = []
            let score = -negamax(
                board: next,
                depth: depth - 1,
                ply: ply + 1,
                alpha: -curBeta,
                beta: -bestAlpha,
                ctx: ctx,
                pvOut: &childPV
            )
            if ctx.cancelled { return 0 }

            if score >= curBeta {
                if move.capturedPiece == nil && move.promotion == nil {
                    ctx.recordKiller(move.uci, ply: ply)
                }
                if abs(curBeta) < mateScore - 500 {
                    ctx.tt[ttIdx] = TTEntry(key: zKey, depth: depth, score: curBeta, flag: 2, bestUCI: move.uci)
                }
                return curBeta
            }
            if score > bestAlpha {
                bestAlpha = score
                bestPV = [move] + childPV
                bestUCI = move.uci
            }
        }

        if abs(bestAlpha) < mateScore - 500 {
            let flag: UInt8 = bestAlpha > origAlpha ? 1 : 3
            ctx.tt[ttIdx] = TTEntry(key: zKey, depth: depth, score: bestAlpha, flag: flag, bestUCI: bestUCI)
        }

        pvOut = bestPV
        return bestAlpha
    }

    private static func quiescence(
        board: ChessBoardState,
        alpha: Int,
        beta: Int,
        ply: Int,
        ctx: SearchContext
    ) -> Int {
        if ctx.cancelled || (ctx.nodes & 1023 == 0 && Date() > ctx.deadline) {
            ctx.cancelled = true
            return 0
        }
        ctx.nodes += 1

        let standPat = evaluate(board: board)
        if standPat >= beta {
            return beta
        }
        var bestAlpha = max(alpha, standPat)

        // Limit q-search depth explosion
        if ply >= 10 {
            return bestAlpha
        }

        let captures = board.legalMoves(includeFormattedSAN: false).filter {
            $0.capturedPiece != nil || $0.promotion != nil
        }
        let ordered = orderMoves(captures, board: board, pvHintUCI: nil)

        for move in ordered {
            let next = board.applyingRaw(move)
            let score = -quiescence(board: next, alpha: -beta, beta: -bestAlpha, ply: ply + 1, ctx: ctx)
            if ctx.cancelled { return 0 }
            if score >= beta {
                return beta
            }
            if score > bestAlpha {
                bestAlpha = score
            }
        }
        return bestAlpha
    }

    private static func orderMoves(_ moves: [ChessMove], board: ChessBoardState, pvHintUCI: String?, killerUCIs: [String] = []) -> [ChessMove] {
        return moves.sorted { a, b in
            scoreMoveOrder(a, board: board, pvHintUCI: pvHintUCI, killerUCIs: killerUCIs) > scoreMoveOrder(b, board: board, pvHintUCI: pvHintUCI, killerUCIs: killerUCIs)
        }
    }

    private static func scoreMoveOrder(_ move: ChessMove, board: ChessBoardState, pvHintUCI: String?, killerUCIs: [String] = []) -> Int {
        if let hint = pvHintUCI, move.uci == hint { return 1_000_000 }
        var score = 0
        if let captured = move.capturedPiece {
            let attackerValue = board.piece(at: move.from)?.baseValue ?? 100
            score += 10_000 + captured.baseValue * 10 - attackerValue
        } else if let idx = killerUCIs.firstIndex(of: move.uci) {
            score += 6_500 - idx * 400
        }
        if let promo = move.promotion {
            score += 8_000 + promo.baseValue
        }
        if move.isCastling {
            score += 500
        }
        // Center control bonus
        let centerDist = abs(Double(move.to.row) - 3.5) + abs(Double(move.to.col) - 3.5)
        score += Int((7.0 - centerDist) * 10.0)
        return score
    }

    /// PeSTO Tapered Evaluation + Passed Pawns + King Shield + Offline Binary Micro-Tables
    fileprivate static func evaluate(board: ChessBoardState) -> Int {
        var mgWhite = 0, mgBlack = 0
        var egWhite = 0, egBlack = 0
        var phase = 0
        var whiteBishops = 0, blackBishops = 0
        var whiteKingPos: (r: Int, c: Int)? = nil
        var blackKingPos: (r: Int, c: Int)? = nil
        var whitePawnFileMask = Array(repeating: 0, count: 8)
        var blackPawnFileMask = Array(repeating: 0, count: 8)

        for r in 0..<8 {
            for c in 0..<8 {
                guard let p = board.squares[r][c] else { continue }
                phase += phaseWeights[p.type] ?? 0
                let sqIdx = p.color == .white ? (r * 8 + c) : ((7 - r) * 8 + c)

                let mgMat = mgValues[p.type] ?? 0
                let egMat = egValues[p.type] ?? 0
                let mgPST: Int
                let egPST: Int

                switch p.type {
                case .pawn:
                    mgPST = mgPawnPST[sqIdx]
                    egPST = egPawnPST[sqIdx]
                    if p.color == .white {
                        whitePawnFileMask[c] |= (1 << r)
                    } else {
                        blackPawnFileMask[c] |= (1 << r)
                    }
                case .knight:
                    mgPST = mgKnightPST[sqIdx]
                    egPST = egKnightPST[sqIdx]
                case .bishop:
                    mgPST = mgBishopPST[sqIdx]
                    egPST = egBishopPST[sqIdx]
                    if p.color == .white { whiteBishops += 1 } else { blackBishops += 1 }
                case .rook:
                    mgPST = mgRookPST[sqIdx]
                    egPST = egRookPST[sqIdx]
                case .queen:
                    mgPST = mgQueenPST[sqIdx]
                    egPST = egQueenPST[sqIdx]
                case .king:
                    mgPST = mgKingPST[sqIdx]
                    egPST = egKingPST[sqIdx]
                    if p.color == .white { whiteKingPos = (r, c) } else { blackKingPos = (r, c) }
                }

                let microAdj = OfflineEnginePack.shared.nnueTableAdjustment(piece: p, row: r, col: c, phase: phase)
                if p.color == .white {
                    mgWhite += mgMat + mgPST + microAdj
                    egWhite += egMat + egPST + microAdj
                } else {
                    mgBlack += mgMat + mgPST + microAdj
                    egBlack += egMat + egPST + microAdj
                }
            }
        }

        // Passed pawn bonus (weighted towards endgame)
        let passedBonus = [0, 65, 45, 32, 22, 18, 12, 0]
        for c in 0..<8 {
            for r in 1..<7 {
                guard let p = board.squares[r][c], p.type == .pawn else { continue }
                let minCol = max(0, c - 1)
                let maxCol = min(7, c + 1)
                if p.color == .white {
                    var blocked = false
                    for fc in minCol...maxCol {
                        for ar in 0..<r where (blackPawnFileMask[fc] & (1 << ar)) != 0 {
                            blocked = true
                            break
                        }
                        if blocked { break }
                    }
                    if !blocked {
                        let bonus = passedBonus[r]
                        mgWhite += bonus / 2
                        egWhite += bonus
                    }
                } else {
                    var blocked = false
                    for fc in minCol...maxCol {
                        for ar in (r + 1)..<8 where (whitePawnFileMask[fc] & (1 << ar)) != 0 {
                            blocked = true
                            break
                        }
                        if blocked { break }
                    }
                    if !blocked {
                        let bonus = passedBonus[7 - r]
                        mgBlack += bonus / 2
                        egBlack += bonus
                    }
                }
            }
        }

        // Castled king pawn shield bonus (middlegame)
        if let wk = whiteKingPos, wk.r == 7 && (wk.c >= 5 || wk.c <= 2) {
            for fc in max(0, wk.c - 1)...min(7, wk.c + 1) {
                if (whitePawnFileMask[fc] & ((1 << 6) | (1 << 5))) != 0 {
                    mgWhite += 14
                }
            }
        }
        if let bk = blackKingPos, bk.r == 0 && (bk.c >= 5 || bk.c <= 2) {
            for fc in max(0, bk.c - 1)...min(7, bk.c + 1) {
                if (blackPawnFileMask[fc] & ((1 << 1) | (1 << 2))) != 0 {
                    mgBlack += 14
                }
            }
        }

        if whiteBishops >= 2 { mgWhite += 30; egWhite += 45 }
        if blackBishops >= 2 { mgBlack += 30; egBlack += 45 }

        let clampedPhase = min(24, phase)
        let mgDiff = mgWhite - mgBlack
        let egDiff = egWhite - egBlack
        let taperedWhite = (mgDiff * clampedPhase + egDiff * (24 - clampedPhase)) / 24

        return board.sideToMove == .white ? taperedWhite : -taperedWhite
    }
}
