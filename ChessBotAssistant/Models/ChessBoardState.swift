import Foundation

struct ChessBoardState: Equatable, Hashable, Codable, Sendable {
    static let standardStartingFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    /// 8x8 grid indexed by [row][col], where row 0 = rank 8, row 7 = rank 1, col 0 = file 'a', col 7 = file 'h'
    var squares: [[ChessPiece?]]
    var sideToMove: PieceColor
    var castlingRights: CastlingRights
    var enPassantTarget: BoardSquare?
    var halfMoveClock: Int
    var fullMoveNumber: Int

    init(
        squares: [[ChessPiece?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8),
        sideToMove: PieceColor = .white,
        castlingRights: CastlingRights = .all,
        enPassantTarget: BoardSquare? = nil,
        halfMoveClock: Int = 0,
        fullMoveNumber: Int = 1
    ) {
        self.squares = squares
        self.sideToMove = sideToMove
        self.castlingRights = castlingRights
        self.enPassantTarget = enPassantTarget
        self.halfMoveClock = halfMoveClock
        self.fullMoveNumber = fullMoveNumber
    }

    static var startingPosition: ChessBoardState {
        ChessBoardState(fen: standardStartingFEN) ?? ChessBoardState()
    }

    static var empty: ChessBoardState {
        ChessBoardState(
            squares: Array(repeating: Array(repeating: nil, count: 8), count: 8),
            sideToMove: .white,
            castlingRights: .none,
            enPassantTarget: nil,
            halfMoveClock: 0,
            fullMoveNumber: 1
        )
    }

    init?(fen: String) {
        let trimmed = fen.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard !parts.isEmpty else { return nil }

        let ranks = parts[0].split(separator: "/")
        guard ranks.count == 8 else { return nil }

        var grid: [[ChessPiece?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        for (row, rankStr) in ranks.enumerated() {
            var col = 0
            for ch in rankStr {
                if let emptyCount = Int(String(ch)), emptyCount >= 1 && emptyCount <= 8 {
                    col += emptyCount
                } else if let piece = ChessPiece(fenChar: ch) {
                    guard col < 8 else { return nil }
                    grid[row][col] = piece
                    col += 1
                } else {
                    return nil
                }
            }
            guard col == 8 else { return nil }
        }

        let side: PieceColor
        if parts.count >= 2 {
            side = (parts[1] == "b") ? .black : .white
        } else {
            side = .white
        }

        let castling: CastlingRights
        if parts.count >= 3 {
            castling = CastlingRights(fenString: String(parts[2]))
        } else {
            castling = .none
        }

        let ep: BoardSquare?
        if parts.count >= 4 && parts[3] != "-" {
            ep = BoardSquare(algebraic: String(parts[3]))
        } else {
            ep = nil
        }

        let half = parts.count >= 5 ? (Int(parts[4]) ?? 0) : 0
        let full = parts.count >= 6 ? max(1, Int(parts[5]) ?? 1) : 1

        self.init(
            squares: grid,
            sideToMove: side,
            castlingRights: castling,
            enPassantTarget: ep,
            halfMoveClock: half,
            fullMoveNumber: full
        )
    }

    func piece(at square: BoardSquare) -> ChessPiece? {
        guard square.isValid else { return nil }
        return squares[square.row][square.col]
    }

    func piece(row: Int, col: Int) -> ChessPiece? {
        guard row >= 0 && row < 8 && col >= 0 && col < 8 else { return nil }
        return squares[row][col]
    }

    func toFEN() -> String {
        var rankStrings: [String] = []
        for row in 0..<8 {
            var rank = ""
            var emptyRun = 0
            for col in 0..<8 {
                if let p = squares[row][col] {
                    if emptyRun > 0 {
                        rank.append(String(emptyRun))
                        emptyRun = 0
                    }
                    rank.append(p.fenChar)
                } else {
                    emptyRun += 1
                }
            }
            if emptyRun > 0 {
                rank.append(String(emptyRun))
            }
            rankStrings.append(rank)
        }
        let boardPart = rankStrings.joined(separator: "/")
        let epPart = enPassantTarget?.algebraic ?? "-"
        return "\(boardPart) \(sideToMove.fenChar) \(castlingRights.fenString) \(epPart) \(halfMoveClock) \(fullMoveNumber)"
    }

    /// Position-only key for repetition / caching
    var positionKey: String {
        let fenParts = toFEN().split(separator: " ")
        return fenParts.prefix(4).joined(separator: " ")
    }

    func findKing(of color: PieceColor) -> BoardSquare? {
        for r in 0..<8 {
            for c in 0..<8 {
                if let p = squares[r][c], p.color == color && p.type == .king {
                    return BoardSquare(row: r, col: c)
                }
            }
        }
        return nil
    }

    func isKingInCheck(_ color: PieceColor) -> Bool {
        guard let kingSq = findKing(of: color) else { return false }
        return isSquareAttacked(row: kingSq.row, col: kingSq.col, by: color.opposite)
    }

    func isSquareAttacked(row: Int, col: Int, by attacker: PieceColor) -> Bool {
        // 1. Pawns
        let pawnSourceRow = attacker == .white ? row + 1 : row - 1
        if pawnSourceRow >= 0 && pawnSourceRow < 8 {
            for dc in [-1, 1] {
                let c = col + dc
                if c >= 0 && c < 8,
                   let p = squares[pawnSourceRow][c],
                   p.color == attacker && p.type == .pawn {
                    return true
                }
            }
        }

        // 2. Knights
        let knightOffsets = [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)]
        for (dr, dc) in knightOffsets {
            let r = row + dr
            let c = col + dc
            if r >= 0 && r < 8 && c >= 0 && c < 8,
               let p = squares[r][c],
               p.color == attacker && p.type == .knight {
                return true
            }
        }

        // 3. King
        for dr in -1...1 {
            for dc in -1...1 {
                if dr == 0 && dc == 0 { continue }
                let r = row + dr
                let c = col + dc
                if r >= 0 && r < 8 && c >= 0 && c < 8,
                   let p = squares[r][c],
                   p.color == attacker && p.type == .king {
                    return true
                }
            }
        }

        // 4. Orthogonal (Rook / Queen)
        let orthoDirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        for (dr, dc) in orthoDirs {
            var r = row + dr
            var c = col + dc
            while r >= 0 && r < 8 && c >= 0 && c < 8 {
                if let p = squares[r][c] {
                    if p.color == attacker && (p.type == .rook || p.type == .queen) {
                        return true
                    }
                    break
                }
                r += dr
                c += dc
            }
        }

        // 5. Diagonal (Bishop / Queen)
        let diagDirs = [(-1, -1), (-1, 1), (1, -1), (1, 1)]
        for (dr, dc) in diagDirs {
            var r = row + dr
            var c = col + dc
            while r >= 0 && r < 8 && c >= 0 && c < 8 {
                if let p = squares[r][c] {
                    if p.color == attacker && (p.type == .bishop || p.type == .queen) {
                        return true
                    }
                    break
                }
                r += dr
                c += dc
            }
        }

        return false
    }

    func generatePseudoLegalMoves() -> [ChessMove] {
        var moves: [ChessMove] = []
        moves.reserveCapacity(48)

        let color = sideToMove
        let enemy = color.opposite

        for r in 0..<8 {
            for c in 0..<8 {
                guard let piece = squares[r][c], piece.color == color else { continue }
                let from = BoardSquare(row: r, col: c)

                switch piece.type {
                case .pawn:
                    let dir = color == .white ? -1 : 1
                    let startRow = color == .white ? 6 : 1
                    let promoRow = color == .white ? 0 : 7
                    let oneStep = r + dir

                    if oneStep >= 0 && oneStep < 8 && squares[oneStep][c] == nil {
                        let to = BoardSquare(row: oneStep, col: c)
                        if oneStep == promoRow {
                            for promo: PieceType in [.queen, .rook, .bishop, .knight] {
                                moves.append(ChessMove(from: from, to: to, promotion: promo))
                            }
                        } else {
                            moves.append(ChessMove(from: from, to: to))
                            if r == startRow {
                                let twoStep = r + 2 * dir
                                if squares[twoStep][c] == nil {
                                    moves.append(ChessMove(from: from, to: BoardSquare(row: twoStep, col: c)))
                                }
                            }
                        }
                    }

                    for dc in [-1, 1] {
                        let nc = c + dc
                        guard nc >= 0 && nc < 8 && oneStep >= 0 && oneStep < 8 else { continue }
                        let to = BoardSquare(row: oneStep, col: nc)
                        if let target = squares[oneStep][nc], target.color == enemy {
                            if oneStep == promoRow {
                                for promo: PieceType in [.queen, .rook, .bishop, .knight] {
                                    moves.append(ChessMove(from: from, to: to, promotion: promo, capturedPiece: target))
                                }
                            } else {
                                moves.append(ChessMove(from: from, to: to, capturedPiece: target))
                            }
                        } else if let ep = enPassantTarget, ep.row == oneStep && ep.col == nc {
                            let capturedPawn = squares[r][nc]
                            moves.append(ChessMove(from: from, to: to, capturedPiece: capturedPawn, isEnPassant: true))
                        }
                    }

                case .knight:
                    let offsets = [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)]
                    for (dr, dc) in offsets {
                        let nr = r + dr
                        let nc = c + dc
                        guard nr >= 0 && nr < 8 && nc >= 0 && nc < 8 else { continue }
                        let target = squares[nr][nc]
                        if target == nil || target?.color == enemy {
                            moves.append(ChessMove(from: from, to: BoardSquare(row: nr, col: nc), capturedPiece: target))
                        }
                    }

                case .bishop:
                    addSlidingMoves(from: from, dirs: [(-1, -1), (-1, 1), (1, -1), (1, 1)], enemy: enemy, into: &moves)

                case .rook:
                    addSlidingMoves(from: from, dirs: [(-1, 0), (1, 0), (0, -1), (0, 1)], enemy: enemy, into: &moves)

                case .queen:
                    addSlidingMoves(from: from, dirs: [(-1, -1), (-1, 1), (1, -1), (1, 1), (-1, 0), (1, 0), (0, -1), (0, 1)], enemy: enemy, into: &moves)

                case .king:
                    for dr in -1...1 {
                        for dc in -1...1 {
                            if dr == 0 && dc == 0 { continue }
                            let nr = r + dr
                            let nc = c + dc
                            guard nr >= 0 && nr < 8 && nc >= 0 && nc < 8 else { continue }
                            let target = squares[nr][nc]
                            if target == nil || target?.color == enemy {
                                moves.append(ChessMove(from: from, to: BoardSquare(row: nr, col: nc), capturedPiece: target))
                            }
                        }
                    }

                    // Castling
                    let homeRow = color == .white ? 7 : 0
                    if r == homeRow && c == 4 && !isSquareAttacked(row: homeRow, col: 4, by: enemy) {
                        let canK = color == .white ? castlingRights.whiteKingside : castlingRights.blackKingside
                        if canK,
                           squares[homeRow][5] == nil,
                           squares[homeRow][6] == nil,
                           let rook = squares[homeRow][7], rook.color == color && rook.type == .rook,
                           !isSquareAttacked(row: homeRow, col: 5, by: enemy),
                           !isSquareAttacked(row: homeRow, col: 6, by: enemy) {
                            moves.append(ChessMove(from: from, to: BoardSquare(row: homeRow, col: 6), isCastling: true))
                        }
                        let canQ = color == .white ? castlingRights.whiteQueenside : castlingRights.blackQueenside
                        if canQ,
                           squares[homeRow][3] == nil,
                           squares[homeRow][2] == nil,
                           squares[homeRow][1] == nil,
                           let rook = squares[homeRow][0], rook.color == color && rook.type == .rook,
                           !isSquareAttacked(row: homeRow, col: 3, by: enemy),
                           !isSquareAttacked(row: homeRow, col: 2, by: enemy) {
                            moves.append(ChessMove(from: from, to: BoardSquare(row: homeRow, col: 2), isCastling: true))
                        }
                    }
                }
            }
        }
        return moves
    }

    private func addSlidingMoves(from: BoardSquare, dirs: [(Int, Int)], enemy: PieceColor, into moves: inout [ChessMove]) {
        for (dr, dc) in dirs {
            var r = from.row + dr
            var c = from.col + dc
            while r >= 0 && r < 8 && c >= 0 && c < 8 {
                if let target = squares[r][c] {
                    if target.color == enemy {
                        moves.append(ChessMove(from: from, to: BoardSquare(row: r, col: c), capturedPiece: target))
                    }
                    break
                } else {
                    moves.append(ChessMove(from: from, to: BoardSquare(row: r, col: c)))
                }
                r += dr
                c += dc
            }
        }
    }

    func legalMoves(includeFormattedSAN: Bool = true) -> [ChessMove] {
        let pseudo = generatePseudoLegalMoves()
        var legal: [ChessMove] = []
        legal.reserveCapacity(pseudo.count)

        for move in pseudo {
            let nextState = applyingRaw(move)
            if !nextState.isKingInCheck(sideToMove) {
                legal.append(move)
            }
        }

        if !includeFormattedSAN {
            return legal
        }

        return legal.map { move in
            var copy = move
            copy.san = formatSAN(for: move, allLegalMoves: legal)
            copy.tacticalTag = inferTacticalTag(for: move, san: copy.san)
            return copy
        }
    }

    func applyingRaw(_ move: ChessMove) -> ChessBoardState {
        var next = self
        guard let movingPiece = next.squares[move.from.row][move.from.col] else { return next }

        next.squares[move.from.row][move.from.col] = nil

        if move.isEnPassant {
            next.squares[move.from.row][move.to.col] = nil
        }

        if move.isCastling {
            let row = move.from.row
            if move.to.col == 6 {
                next.squares[row][5] = next.squares[row][7]
                next.squares[row][7] = nil
            } else if move.to.col == 2 {
                next.squares[row][3] = next.squares[row][0]
                next.squares[row][0] = nil
            }
        }

        if let promo = move.promotion {
            next.squares[move.to.row][move.to.col] = ChessPiece(color: movingPiece.color, type: promo)
        } else {
            next.squares[move.to.row][move.to.col] = movingPiece
        }

        // Update castling rights
        if movingPiece.type == .king {
            if movingPiece.color == .white {
                next.castlingRights.whiteKingside = false
                next.castlingRights.whiteQueenside = false
            } else {
                next.castlingRights.blackKingside = false
                next.castlingRights.blackQueenside = false
            }
        }
        if movingPiece.type == .rook {
            if move.from.row == 7 && move.from.col == 7 { next.castlingRights.whiteKingside = false }
            if move.from.row == 7 && move.from.col == 0 { next.castlingRights.whiteQueenside = false }
            if move.from.row == 0 && move.from.col == 7 { next.castlingRights.blackKingside = false }
            if move.from.row == 0 && move.from.col == 0 { next.castlingRights.blackQueenside = false }
        }
        if move.to.row == 7 && move.to.col == 7 { next.castlingRights.whiteKingside = false }
        if move.to.row == 7 && move.to.col == 0 { next.castlingRights.whiteQueenside = false }
        if move.to.row == 0 && move.to.col == 7 { next.castlingRights.blackKingside = false }
        if move.to.row == 0 && move.to.col == 0 { next.castlingRights.blackQueenside = false }

        // Update en passant target
        if movingPiece.type == .pawn && abs(move.to.row - move.from.row) == 2 {
            next.enPassantTarget = BoardSquare(row: (move.from.row + move.to.row) / 2, col: move.from.col)
        } else {
            next.enPassantTarget = nil
        }

        if movingPiece.type == .pawn || move.capturedPiece != nil {
            next.halfMoveClock = 0
        } else {
            next.halfMoveClock += 1
        }

        if sideToMove == .black {
            next.fullMoveNumber += 1
        }
        next.sideToMove = sideToMove.opposite
        return next
    }

    func applying(_ move: ChessMove) -> ChessBoardState {
        applyingRaw(move)
    }

    func formatSAN(for move: ChessMove, allLegalMoves: [ChessMove]? = nil) -> String {
        guard let movingPiece = squares[move.from.row][move.from.col] else { return move.uci }

        let nextState = applyingRaw(move)
        let opponent = sideToMove.opposite
        let givesCheck = nextState.isKingInCheck(opponent)
        let isMate = givesCheck && nextState.legalMoves(includeFormattedSAN: false).isEmpty
        let suffix = isMate ? "#" : (givesCheck ? "+" : "")

        if move.isCastling {
            return (move.to.col == 6 ? "O-O" : "O-O-O") + suffix
        }

        var san = ""
        let isCapture = move.capturedPiece != nil || move.isEnPassant

        if movingPiece.type == .pawn {
            if isCapture {
                san += "\(move.from.fileChar)x"
            }
            san += move.to.algebraic
            if let promo = move.promotion {
                san += "=\(promo.sanLetter)"
            }
        } else {
            san += movingPiece.type.sanLetter
            let candidates = (allLegalMoves ?? legalMoves(includeFormattedSAN: false)).filter { other in
                other.to == move.to &&
                other.from != move.from &&
                squares[other.from.row][other.from.col]?.type == movingPiece.type
            }
            if !candidates.isEmpty {
                let sameFile = candidates.contains { $0.from.col == move.from.col }
                let sameRank = candidates.contains { $0.from.row == move.from.row }
                if !sameFile {
                    san += String(move.from.fileChar)
                } else if !sameRank {
                    san += String(move.from.rankNumber)
                } else {
                    san += move.from.algebraic
                }
            }
            if isCapture {
                san += "x"
            }
            san += move.to.algebraic
        }

        return san + suffix
    }

    private func inferTacticalTag(for move: ChessMove, san: String) -> String? {
        if san.hasSuffix("#") { return "將殺" }
        if san.hasSuffix("+") { return "將軍" }
        if move.promotion != nil { return "升變" }
        if move.isCastling { return "王車易位" }
        if let captured = move.capturedPiece {
            if let attacker = piece(at: move.from), captured.baseValue > attacker.baseValue {
                return "賺子吃子"
            }
            return "吃子"
        }
        let centerSquares = [(3, 3), (3, 4), (4, 3), (4, 4)]
        if centerSquares.contains(where: { $0.0 == move.to.row && $0.1 == move.to.col }) {
            return "控制中心"
        }
        return nil
    }

    func legalMove(uci: String) -> ChessMove? {
        let target = uci.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return legalMoves().first { $0.uci == target }
    }

    func legalMove(sanOrUCI token: String) -> ChessMove? {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let moves = legalMoves()
        if let uciMatch = moves.first(where: { $0.uci.caseInsensitiveCompare(cleaned) == .orderedSame }) {
            return uciMatch
        }
        let normalized = cleaned.replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "?", with: "")
        return moves.first { move in
            let moveNorm = move.san.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "#", with: "")
            return moveNorm == normalized || move.san == cleaned
        }
    }

    /// Parses either a FEN string, a PGN game, or a space-separated move list into a ChessBoardState
    static func parseFromInput(_ rawInput: String) -> (state: ChessBoardState, history: [ChessBoardState], moveSANs: [String])? {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Check if it looks like a FEN string
        if let fenBoard = ChessBoardState(fen: trimmed) {
            return (fenBoard, [], [])
        }

        // 2. Check if PGN has a [FEN "..."] header
        var current = ChessBoardState.startingPosition
        if let fenRange = trimmed.range(of: #"\[FEN\s+"([^"]+)"\]"#, options: .regularExpression) {
            let tag = String(trimmed[fenRange])
            if let firstQuote = tag.firstIndex(of: "\""),
               let lastQuote = tag.lastIndex(of: "\""),
               firstQuote < lastQuote {
                let innerFEN = String(tag[tag.index(after: firstQuote)..<lastQuote])
                if let custom = ChessBoardState(fen: innerFEN) {
                    current = custom
                }
            }
        }

        // 3. Strip PGN headers [...] and comments {...}
        var body = trimmed.replacingOccurrences(of: #"\[[^\]]*\]"#, with: " ", options: .regularExpression)
        body = body.replacingOccurrences(of: #"\{[^}]*\}"#, with: " ", options: .regularExpression)
        body = body.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)

        let rawTokens = body.split { $0.isWhitespace }.map { String($0) }
        var history: [ChessBoardState] = []
        var moveSANs: [String] = []

        for token in rawTokens {
            // Skip move numbers like "1.", "12...", results like "1-0", "0-1", "1/2-1/2", "*"
            if token == "*" || token == "1-0" || token == "0-1" || token == "1/2-1/2" {
                continue
            }
            var moveToken = token
            if let dotIdx = moveToken.lastIndex(of: ".") {
                let afterDot = String(moveToken[moveToken.index(after: dotIdx)...])
                if afterDot.isEmpty { continue }
                moveToken = afterDot
            }
            guard !moveToken.isEmpty else { continue }
            if let found = current.legalMove(sanOrUCI: moveToken) {
                history.append(current)
                moveSANs.append(found.san)
                current = current.applying(found)
            }
        }

        if moveSANs.isEmpty && !trimmed.contains("[FEN") {
            return nil
        }
        return (current, history, moveSANs)
    }

    // MARK: - Tactical Radar, Material Balance & ECO Opening Recognition

    func buildTacticalRadar(for camp: PieceColor, moveHistorySAN: [String]) -> TacticalRadarReport {
        let standardCounts: [(type: PieceType, count: Int)] = [
            (.queen, 1), (.rook, 2), (.bishop, 2), (.knight, 2), (.pawn, 8)
        ]

        var whiteCounts: [PieceType: Int] = [:]
        var blackCounts: [PieceType: Int] = [:]
        var whiteMaterial = 0
        var blackMaterial = 0
        var totalNonKingPieces = 0

        let enemy = camp.opposite
        var hangingFriendlySquares: [BoardSquare] = []
        var hangingDescriptions: [String] = []
        var freeTargetDescriptions: [String] = []

        for r in 0..<8 {
            for c in 0..<8 {
                guard let piece = squares[r][c] else { continue }
                if piece.color == .white {
                    whiteCounts[piece.type, default: 0] += 1
                    whiteMaterial += piece.baseValue
                } else {
                    blackCounts[piece.type, default: 0] += 1
                    blackMaterial += piece.baseValue
                }
                if piece.type != .king {
                    totalNonKingPieces += 1
                }

                let sq = BoardSquare(row: r, col: c)
                if piece.type != .king {
                    if piece.color == camp {
                        if isSquareAttacked(row: r, col: c, by: enemy) {
                            let isDefended = isSquareAttacked(row: r, col: c, by: camp)
                            let minEnemyVal = lowestAttackerValue(row: r, col: c, by: enemy)
                            if !isDefended || (minEnemyVal != nil && minEnemyVal! < piece.baseValue) {
                                hangingFriendlySquares.append(sq)
                                let reason = !isDefended ? "無保護受攻" : "被低價值子威脅"
                                hangingDescriptions.append("\(piece.type.displayName)\(sq.algebraic)(\(reason))")
                            }
                        }
                    } else {
                        if isSquareAttacked(row: r, col: c, by: camp) {
                            let isEnemyDefended = isSquareAttacked(row: r, col: c, by: enemy)
                            let minMyVal = lowestAttackerValue(row: r, col: c, by: camp)
                            if !isEnemyDefended || (minMyVal != nil && minMyVal! < piece.baseValue) {
                                freeTargetDescriptions.append("\(piece.type.displayName)\(sq.algebraic)")
                            }
                        }
                    }
                }
            }
        }

        let whitePawns = Double(whiteMaterial - blackMaterial) / 100.0
        let campPawns = camp == .white ? whitePawns : -whitePawns
        let materialDiff = Int(campPawns.rounded())

        var missingWhite: [ChessPiece] = []
        var missingBlack: [ChessPiece] = []
        for entry in standardCounts {
            let wDiff = max(0, entry.count - (whiteCounts[entry.type] ?? 0))
            for _ in 0..<wDiff {
                missingWhite.append(ChessPiece(color: .white, type: entry.type))
            }
            let bDiff = max(0, entry.count - (blackCounts[entry.type] ?? 0))
            for _ in 0..<bDiff {
                missingBlack.append(ChessPiece(color: .black, type: entry.type))
            }
        }

        let capturedByUser = camp == .white ? missingBlack : missingWhite
        let capturedByOpponent = camp == .white ? missingWhite : missingBlack

        let openingName = detectOpeningName(moveHistorySAN: moveHistorySAN, totalNonKingPieces: totalNonKingPieces)

        let inCheck = isKingInCheck(camp)
        let checkers = inCheck ? checkingPieces(for: camp) : []
        let checkingDescs = checkers.map { "\($0.piece.type.displayName)\($0.square.algebraic)" }
        let pins = pinnedPieces(for: camp)
        let tensionCount = hangingFriendlySquares.count + freeTargetDescriptions.count
        let thinkRange: String
        if inCheck || tensionCount >= 2 {
            thinkRange = "4~8 秒"
        } else if totalNonKingPieces >= 28 {
            thinkRange = "1.5~3.5 秒"
        } else if totalNonKingPieces <= 10 {
            thinkRange = "5~9 秒"
        } else {
            thinkRange = "3~5 秒"
        }

        return TacticalRadarReport(
            materialDiffForPerspective: materialDiff,
            capturedByUser: capturedByUser,
            capturedByOpponent: capturedByOpponent,
            hangingFriendlySquares: hangingFriendlySquares,
            hangingDescriptions: Array(hangingDescriptions.prefix(3)),
            freeTargetDescriptions: Array(freeTargetDescriptions.prefix(3)),
            openingName: openingName,
            recommendedThinkRange: thinkRange,
            isKingInCheck: inCheck,
            checkingDescriptions: Array(checkingDescs.prefix(2)),
            pinnedPieces: Array(pins.prefix(3))
        )
    }

    func checkingPieces(for camp: PieceColor) -> [(square: BoardSquare, piece: ChessPiece)] {
        guard let kingSq = findKing(of: camp) else { return [] }
        let enemy = camp.opposite
        var attackers: [(square: BoardSquare, piece: ChessPiece)] = []
        let row = kingSq.row
        let col = kingSq.col

        let pawnSourceRow = enemy == .white ? row + 1 : row - 1
        if pawnSourceRow >= 0 && pawnSourceRow < 8 {
            for dc in [-1, 1] {
                let c = col + dc
                if c >= 0 && c < 8,
                   let p = squares[pawnSourceRow][c],
                   p.color == enemy && p.type == .pawn {
                    attackers.append((BoardSquare(row: pawnSourceRow, col: c), p))
                }
            }
        }

        let knightOffsets = [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)]
        for (dr, dc) in knightOffsets {
            let r = row + dr, c = col + dc
            if r >= 0 && r < 8 && c >= 0 && c < 8,
               let p = squares[r][c],
               p.color == enemy && p.type == .knight {
                attackers.append((BoardSquare(row: r, col: c), p))
            }
        }

        let orthoDirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        for (dr, dc) in orthoDirs {
            var r = row + dr, c = col + dc
            while r >= 0 && r < 8 && c >= 0 && c < 8 {
                if let p = squares[r][c] {
                    if p.color == enemy && (p.type == .rook || p.type == .queen) {
                        attackers.append((BoardSquare(row: r, col: c), p))
                    }
                    break
                }
                r += dr; c += dc
            }
        }

        let diagDirs = [(-1, -1), (-1, 1), (1, -1), (1, 1)]
        for (dr, dc) in diagDirs {
            var r = row + dr, c = col + dc
            while r >= 0 && r < 8 && c >= 0 && c < 8 {
                if let p = squares[r][c] {
                    if p.color == enemy && (p.type == .bishop || p.type == .queen) {
                        attackers.append((BoardSquare(row: r, col: c), p))
                    }
                    break
                }
                r += dr; c += dc
            }
        }
        return attackers
    }

    func pinnedPieces(for camp: PieceColor) -> [PinnedPieceInfo] {
        guard let kingSq = findKing(of: camp) else { return [] }
        let enemy = camp.opposite
        var pins: [PinnedPieceInfo] = []

        let dirs: [(dr: Int, dc: Int, isDiagonal: Bool)] = [
            (-1, 0, false), (1, 0, false), (0, -1, false), (0, 1, false),
            (-1, -1, true), (-1, 1, true), (1, -1, true), (1, 1, true)
        ]

        for dir in dirs {
            var r = kingSq.row + dir.dr
            var c = kingSq.col + dir.dc
            var candidateFriendly: (square: BoardSquare, piece: ChessPiece)? = nil

            while r >= 0 && r < 8 && c >= 0 && c < 8 {
                if let p = squares[r][c] {
                    if p.color == camp {
                        if candidateFriendly == nil {
                            candidateFriendly = (BoardSquare(row: r, col: c), p)
                        } else {
                            break
                        }
                    } else if p.color == enemy {
                        if let friendly = candidateFriendly {
                            let isPinningSlider = dir.isDiagonal
                                ? (p.type == .bishop || p.type == .queen)
                                : (p.type == .rook || p.type == .queen)
                            if isPinningSlider {
                                pins.append(PinnedPieceInfo(
                                    square: friendly.square,
                                    piece: friendly.piece,
                                    attackerSquare: BoardSquare(row: r, col: c),
                                    attackerPiece: p
                                ))
                            }
                        }
                        break
                    }
                }
                r += dir.dr
                c += dir.dc
            }
        }
        return pins
    }

    func explainMoveTactics(_ move: ChessMove) -> String {
        let mover = piece(at: move.from)
        let after = applyingRaw(move)
        let enemy = sideToMove.opposite

        if isKingInCheck(sideToMove) {
            if mover?.type == .king {
                return "王正被將軍：移開國王至安全格 (\(move.to.algebraic)) 解圍"
            }
            if let cap = move.capturedPiece {
                return "王正被將軍：直接吃掉\(move.to.algebraic)攻擊子(\(cap.type.displayName))解圍"
            }
            return "王正被將軍：調動\(mover?.type.displayName ?? "棋子")擋住將軍線保護國王"
        }

        let san = move.san.isEmpty ? formatSAN(for: move) : move.san
        if san.hasSuffix("#") {
            return "致命一擊：直接將殺對手國王"
        }
        if move.isCastling {
            return "王車易位：將國王藏入安全翼並同時出動城堡"
        }
        if let promo = move.promotion {
            return "兵底線升變：升變為\(promo.fullChineseName)大幅擴大子力"
        }

        if let cap = move.capturedPiece {
            let isTargetDefended = after.isSquareAttacked(row: move.to.row, col: move.to.col, by: enemy)
            if !isTargetDefended {
                return "白吃得子：吃掉無保護的敵方\(cap.type.displayName) (\(move.to.algebraic))"
            }
            if let m = mover, cap.baseValue > m.baseValue {
                return "賺子交換：以\(m.type.displayName)換取高價值敵方\(cap.type.displayName)"
            }
            return "主動兌子：吃掉\(move.to.algebraic)敵方\(cap.type.displayName)消滅威脅"
        }

        if san.hasSuffix("+") {
            return "先手將軍：強迫對手應將以搶得戰術先手"
        }

        // Check if move threatens enemy Queen or valuable piece
        for r in 0..<8 {
            for c in 0..<8 {
                if let p = after.squares[r][c], p.color == enemy, p.type == .queen {
                    if !isSquareAttacked(row: r, col: c, by: sideToMove) && after.isSquareAttacked(row: r, col: c, by: sideToMove) {
                        return "攻后奪先：走子威脅\(BoardSquare(row: r, col: c).algebraic)敵方皇后，搶占先手"
                    }
                }
            }
        }

        // Check if move rescues a previously hanging friendly piece
        if let m = mover,
           isSquareAttacked(row: move.from.row, col: move.from.col, by: enemy),
           !after.isSquareAttacked(row: move.to.row, col: move.to.col, by: enemy) {
            return "避險脫身：將受威脅的\(m.type.displayName)移至安全格 \(move.to.algebraic)"
        }

        let centerSquares = [(3, 3), (3, 4), (4, 3), (4, 4)]
        if centerSquares.contains(where: { $0.0 == move.to.row && $0.1 == move.to.col }) {
            return "控制中心：搶占核心要道與子力活躍格"
        }
        if let m = mover, (m.type == .knight || m.type == .bishop) && (move.from.row == 0 || move.from.row == 7) {
            return "出子爭先：活化\(m.type.fullChineseName)並加速王翼/后翼展開"
        }
        return "穩健推進：改善子力協調與王翼長期安全"
    }

    private func lowestAttackerValue(row: Int, col: Int, by attacker: PieceColor) -> Int? {
        var best: Int? = nil
        func record(_ value: Int) {
            if let cur = best { best = min(cur, value) } else { best = value }
        }

        let pawnSourceRow = attacker == .white ? row + 1 : row - 1
        if pawnSourceRow >= 0 && pawnSourceRow < 8 {
            for dc in [-1, 1] {
                let c = col + dc
                if c >= 0 && c < 8, let p = squares[pawnSourceRow][c], p.color == attacker && p.type == .pawn {
                    record(p.baseValue)
                }
            }
        }

        let knightOffsets = [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)]
        for (dr, dc) in knightOffsets {
            let r = row + dr, c = col + dc
            if r >= 0 && r < 8 && c >= 0 && c < 8,
               let p = squares[r][c], p.color == attacker && p.type == .knight {
                record(p.baseValue)
            }
        }

        let diagDirs = [(-1, -1), (-1, 1), (1, -1), (1, 1)]
        for (dr, dc) in diagDirs {
            var r = row + dr, c = col + dc
            while r >= 0 && r < 8 && c >= 0 && c < 8 {
                if let p = squares[r][c] {
                    if p.color == attacker && (p.type == .bishop || p.type == .queen) {
                        record(p.baseValue)
                    }
                    break
                }
                r += dr; c += dc
            }
        }

        let orthoDirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        for (dr, dc) in orthoDirs {
            var r = row + dr, c = col + dc
            while r >= 0 && r < 8 && c >= 0 && c < 8 {
                if let p = squares[r][c] {
                    if p.color == attacker && (p.type == .rook || p.type == .queen) {
                        record(p.baseValue)
                    }
                    break
                }
                r += dr; c += dc
            }
        }

        for dr in -1...1 {
            for dc in -1...1 where !(dr == 0 && dc == 0) {
                let r = row + dr, c = col + dc
                if r >= 0 && r < 8 && c >= 0 && c < 8,
                   let p = squares[r][c], p.color == attacker && p.type == .king {
                    record(p.baseValue)
                }
            }
        }
        return best
    }

    func detectOpeningName(moveHistorySAN: [String], totalNonKingPieces: Int? = nil) -> String {
        let joined = moveHistorySAN.prefix(8).joined(separator: " ")
        if !joined.isEmpty {
            let sanRules: [(prefix: String, name: String)] = [
                ("e4 e5 Nf3 Nc6 Bb5", "西班牙開局 (Ruy Lopez)"),
                ("e4 e5 Nf3 Nc6 Bc4 Bc5", "義大利開局・吉奧科平靜 (Giuoco Piano)"),
                ("e4 e5 Nf3 Nc6 Bc4 Nf6", "雙馬防禦 (Two Knights Defense)"),
                ("e4 e5 Nf3 Nc6 Bc4", "義大利開局 (Italian Game)"),
                ("e4 e5 Nf3 Nc6 d4", "蘇格蘭開局 (Scotch Game)"),
                ("e4 e5 Nf3 Nc6 Nc3 Nf6", "四馬開局 (Four Knights Game)"),
                ("e4 e5 Nf3 Nf6", "彼得羅夫防禦 (Petrov's Defense)"),
                ("e4 e5 Nf3 d6", "菲利道爾防禦 (Philidor Defense)"),
                ("e4 e5 Nc3", "維也納開局 (Vienna Game)"),
                ("e4 e5 f4", "王翼棄兵 (King's Gambit)"),
                ("e4 e5 d4", "中心開局 (Center Game)"),
                ("e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6", "西西里納伊道夫 (Sicilian Najdorf)"),
                ("e4 c5 Nf3 Nc6 Bb5", "西西里羅索里莫 (Sicilian Rossolimo)"),
                ("e4 c5 c3", "西西里阿拉平 (Sicilian Alapin)"),
                ("e4 c5", "西西里防禦 (Sicilian Defense)"),
                ("e4 e6 d4 d5", "法蘭西防禦 (French Defense)"),
                ("e4 e6", "法蘭西防禦 (French Defense)"),
                ("e4 c6 d4 d5", "卡羅-康防禦 (Caro-Kann Defense)"),
                ("e4 c6", "卡羅-康防禦 (Caro-Kann Defense)"),
                ("e4 d5", "斯堪地那維亞防禦 (Scandinavian)"),
                ("e4 d6 d4 Nf6 Nc3 g6", "皮爾茨防禦 (Pirc Defense)"),
                ("e4 g6", "現代防禦 (Modern Defense)"),
                ("d4 d5 c4 e6", "拒絕后翼棄兵 (QGD)"),
                ("d4 d5 c4 c6", "斯拉夫防禦 (Slav Defense)"),
                ("d4 d5 c4 dxc4", "接受后翼棄兵 (QGA)"),
                ("d4 d5 c4", "后翼棄兵 (Queen's Gambit)"),
                ("d4 d5 Bf4", "倫敦體系 (London System)"),
                ("d4 Nf6 c4 g6 Nc3 Bg7", "王翼印度防禦 (King's Indian)"),
                ("d4 Nf6 c4 g6 Nc3 d5", "格林菲爾德防禦 (Grunfeld)"),
                ("d4 Nf6 c4 e6 Nc3 Bb4", "尼姆佐-印度防禦 (Nimzo-Indian)"),
                ("d4 Nf6 c4 e6 Nf3 b6", "后翼印度防禦 (Queen's Indian)"),
                ("d4 Nf6 c4 e6 g3", "加泰隆尼亞開局 (Catalan)"),
                ("d4 Nf6 c4 c5", "貝諾尼防禦 (Benoni)"),
                ("d4 f5", "荷蘭防禦 (Dutch Defense)"),
                ("c4", "英國式開局 (English Opening)"),
                ("Nf3", "雷蒂開局 (Reti Opening)"),
                ("f4", "柏德開局 (Bird's Opening)"),
                ("b3", "尼姆佐-拉森攻擊 (Nimzo-Larsen)"),
                ("e4", "王前兵開局 (King's Pawn)"),
                ("d4", "后前兵開局 (Queen's Pawn)")
            ]
            for rule in sanRules where joined.hasPrefix(rule.prefix) {
                return rule.name
            }
        }

        // Geometric board signature detection (works directly from screenshots without SAN history)
        func has(_ alg: String, _ color: PieceColor, _ type: PieceType) -> Bool {
            guard let sq = BoardSquare(algebraic: alg), let p = squares[sq.row][sq.col] else { return false }
            return p.color == color && p.type == type
        }

        if self == .startingPosition {
            return "標準開局預備 (Starting Position)"
        }
        if has("e4", .white, .pawn) {
            if has("c5", .black, .pawn) {
                if has("f3", .white, .knight) && has("d6", .black, .pawn) { return "西西里防禦・主線 (Sicilian)" }
                return "西西里防禦 (Sicilian Defense)"
            }
            if has("e5", .black, .pawn) {
                if has("b5", .white, .bishop) && has("c6", .black, .knight) { return "西班牙開局 (Ruy Lopez)" }
                if has("c4", .white, .bishop) && has("f3", .white, .knight) { return "義大利開局 (Italian Game)" }
                if has("f3", .white, .knight) && has("f6", .black, .knight) && !has("c6", .black, .knight) { return "彼得羅夫防禦 (Petrov)" }
                return "開放性開局 (Open Game 1.e4 e5)"
            }
            if has("c6", .black, .pawn) { return "卡羅-康防禦 (Caro-Kann)" }
            if has("e6", .black, .pawn) && !has("e5", .black, .pawn) { return "法蘭西防禦 (French Defense)" }
            if has("d5", .black, .pawn) && has("d4", .white, .pawn) == false { return "斯堪地那維亞防禦 (Scandinavian)" }
        }
        if has("d4", .white, .pawn) {
            if has("f4", .white, .bishop) && has("e3", .white, .pawn) { return "倫敦體系 (London System)" }
            if has("d5", .black, .pawn) && has("c4", .white, .pawn) {
                if has("c6", .black, .pawn) { return "斯拉夫防禦 (Slav Defense)" }
                if has("e6", .black, .pawn) { return "拒絕后翼棄兵 (QGD)" }
                return "后翼棄兵 (Queen's Gambit)"
            }
            if has("g6", .black, .pawn) && has("g7", .black, .bishop) { return "王翼印度防禦 (King's Indian)" }
            if has("d5", .black, .pawn) && has("f4", .white, .bishop) { return "倫敦體系 (London System)" }
            if has("f5", .black, .pawn) { return "荷蘭防禦 (Dutch Defense)" }
        }
        if has("c4", .white, .pawn) && !has("d4", .white, .pawn) {
            return "英國式開局 (English Opening)"
        }

        let count = totalNonKingPieces ?? squares.flatMap { $0 }.compactMap { $0 }.filter { $0.type != .king }.count
        if count <= 10 {
            return "殘局精算階段 (Endgame)"
        } else if count >= 26 {
            return "開局發展階段 (Opening)"
        }
        return "中局戰術交鋒 (Middlegame)"
    }
}
