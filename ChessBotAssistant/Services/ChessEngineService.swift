import Foundation

@MainActor
final class ChessEngineService: ObservableObject {
    @Published var targetDepth: Int = 12
    @Published var multiPVCount: Int = 3
    @Published var autoHintEnabled: Bool = true
    @Published var useCloudStockfish: Bool = true

    // 防誤封與隱私隔離保護設定
    @Published var zeroNetworkIsolationMode: Bool = true
    @Published var humanMatchSafetyLockEnabled: Bool = true
    @Published var coachPieceOnlyHintMode: Bool = false

    @Published private(set) var isAnalyzing: Bool = false
    @Published private(set) var currentAnalysis: EngineAnalysisResult?
    @Published private(set) var lastErrorMessage: String?

    private var activeTask: Task<Void, Never>?
    private var cloudCache: [String: EngineAnalysisResult] = [:]

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
        let cacheKey = "\(board.positionKey)|d\(requestedDepth)|pv\(requestedPV)"

        if allowCloud, let cached = cloudCache[cacheKey] {
            currentAnalysis = cached
            isAnalyzing = false
            return
        }

        isAnalyzing = true

        activeTask = Task { [weak self] in
            guard let self else { return }

            // 1. Run local fast Multi-PV engine off the main thread
            let localMaxDepth = isZeroNetwork ? min(requestedDepth, 6) : min(requestedDepth, 5)
            let localBudget: TimeInterval = isZeroNetwork ? 1.1 : 0.9

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
            self.currentAnalysis = localResult

            // 2. If Cloud Stockfish is disabled or Zero-Network Isolation is active, finish strictly offline
            guard allowCloud else {
                self.isAnalyzing = false
                return
            }

            // 3. Query Cloud Stockfish 16 NNUE (Lichess Multi-PV first, then Stockfish.online)
            if let cloudResult = await self.fetchCloudAnalysis(
                board: board,
                requestedDepth: requestedDepth,
                multiPV: requestedPV,
                localFallbackLines: localResult.lines
            ) {
                if Task.isCancelled { return }
                self.cloudCache[cacheKey] = cloudResult
                self.currentAnalysis = cloudResult
            }

            if !Task.isCancelled {
                self.isAnalyzing = false
            }
        }
    }

    // MARK: - Cloud Stockfish Integration

    private func fetchCloudAnalysis(
        board: ChessBoardState,
        requestedDepth: Int,
        multiPV: Int,
        localFallbackLines: [PVLine]
    ) async -> EngineAnalysisResult? {
        // Try Lichess Cloud Eval (supports multiPv=3 natively)
        if let lichessLines = await queryLichessCloudEval(board: board, multiPV: multiPV), !lichessLines.lines.isEmpty {
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

        // Fallback to stockfish.online API (works on any arbitrary midgame/endgame position)
        let sfDepth = min(max(requestedDepth, 10), 15)
        if let sfLine = await queryStockfishOnline(board: board, depth: sfDepth) {
            var merged: [PVLine] = [sfLine]
            var nextIdx = 2
            for local in localFallbackLines where local.bestMove.uci != sfLine.bestMove.uci {
                if merged.count >= multiPV { break }
                merged.append(PVLine(
                    multipvIndex: nextIdx,
                    bestMove: local.bestMove,
                    continuationSAN: local.continuationSAN,
                    continuationUCI: local.continuationUCI,
                    scoreCentipawns: local.scoreCentipawns,
                    mateInMoves: local.mateInMoves,
                    depth: local.depth,
                    sourceLabel: "本地備選"
                ))
                nextIdx += 1
            }
            return EngineAnalysisResult(
                fen: board.toFEN(),
                sideToMove: board.sideToMove,
                lines: merged,
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

        var req = URLRequest(url: url, timeoutInterval: 4.5)
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
                    sourceLabel: "SF Cloud"
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

        let req = URLRequest(url: url, timeoutInterval: 6.5)

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
                sourceLabel: "SF16 NNUE"
            )
        } catch {
            return nil
        }
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

    private final class SearchContext {
        var nodes: Int = 0
        let deadline: Date
        var cancelled: Bool = false

        init(deadline: Date) {
            self.deadline = deadline
        }
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
                currentResults.append((move, score, [move] + childPV))
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
            bestScoredMoves = orderedInitial.map { ($0, 0, [$0]) }
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
                sourceLabel: "本地 D\(completedDepth)"
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
        let legal = board.legalMoves(includeFormattedSAN: false)

        if legal.isEmpty {
            if board.isKingInCheck(board.sideToMove) {
                return -mateScore + ply
            }
            return 0
        }

        let ordered = orderMoves(legal, board: board, pvHintUCI: nil)
        var bestAlpha = alpha
        var bestPV: [ChessMove] = []

        for move in ordered {
            let next = board.applyingRaw(move)
            var childPV: [ChessMove] = []
            let score = -negamax(
                board: next,
                depth: depth - 1,
                ply: ply + 1,
                alpha: -beta,
                beta: -bestAlpha,
                ctx: ctx,
                pvOut: &childPV
            )
            if ctx.cancelled { return 0 }

            if score >= beta {
                return beta
            }
            if score > bestAlpha {
                bestAlpha = score
                bestPV = [move] + childPV
            }
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

    private static func orderMoves(_ moves: [ChessMove], board: ChessBoardState, pvHintUCI: String?) -> [ChessMove] {
        return moves.sorted { a, b in
            scoreMoveOrder(a, board: board, pvHintUCI: pvHintUCI) > scoreMoveOrder(b, board: board, pvHintUCI: pvHintUCI)
        }
    }

    private static func scoreMoveOrder(_ move: ChessMove, board: ChessBoardState, pvHintUCI: String?) -> Int {
        if let hint = pvHintUCI, move.uci == hint { return 1_000_000 }
        var score = 0
        if let captured = move.capturedPiece {
            let attackerValue = board.piece(at: move.from)?.baseValue ?? 100
            score += 10_000 + captured.baseValue * 10 - attackerValue
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

    /// PeSTO Tapered Evaluation from `board.sideToMove` perspective
    private static func evaluate(board: ChessBoardState) -> Int {
        var mgWhite = 0, mgBlack = 0
        var egWhite = 0, egBlack = 0
        var phase = 0
        var whiteBishops = 0, blackBishops = 0

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
                case .knight:
                    mgPST = mgKnightPST[sqIdx]
                    egPST = mgKnightPST[sqIdx]
                case .bishop:
                    mgPST = mgBishopPST[sqIdx]
                    egPST = mgBishopPST[sqIdx]
                    if p.color == .white { whiteBishops += 1 } else { blackBishops += 1 }
                case .rook:
                    mgPST = mgRookPST[sqIdx]
                    egPST = mgRookPST[sqIdx]
                case .queen:
                    mgPST = mgQueenPST[sqIdx]
                    egPST = mgQueenPST[sqIdx]
                case .king:
                    mgPST = mgKingPST[sqIdx]
                    egPST = egKingPST[sqIdx]
                }

                if p.color == .white {
                    mgWhite += mgMat + mgPST
                    egWhite += egMat + egPST
                } else {
                    mgBlack += mgMat + mgPST
                    egBlack += egMat + egPST
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
