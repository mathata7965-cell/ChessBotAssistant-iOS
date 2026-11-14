import Foundation

enum PieceColor: String, Codable, CaseIterable, Sendable, Hashable {
    case white
    case black

    var opposite: PieceColor {
        self == .white ? .black : .white
    }

    var displayName: String {
        self == .white ? "白方" : "黑方"
    }

    var fenChar: String {
        self == .white ? "w" : "b"
    }
}

enum PieceType: String, Codable, CaseIterable, Sendable, Hashable {
    case pawn
    case knight
    case bishop
    case rook
    case queen
    case king

    var fenUpperChar: Character {
        switch self {
        case .pawn: return "P"
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        case .king: return "K"
        }
    }

    var promotionUCI: String {
        switch self {
        case .knight: return "n"
        case .bishop: return "b"
        case .rook: return "r"
        case .queen: return "q"
        default: return ""
        }
    }

    var sanLetter: String {
        switch self {
        case .pawn: return ""
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        case .king: return "K"
        }
    }

    var baseValue: Int {
        switch self {
        case .pawn: return 100
        case .knight: return 320
        case .bishop: return 330
        case .rook: return 500
        case .queen: return 900
        case .king: return 20000
        }
    }

    var displayName: String {
        switch self {
        case .pawn: return "兵"
        case .knight: return "馬"
        case .bishop: return "象"
        case .rook: return "車"
        case .queen: return "后"
        case .king: return "王"
        }
    }
}

struct ChessPiece: Codable, Equatable, Hashable, Sendable {
    let color: PieceColor
    let type: PieceType

    var fenChar: Character {
        let upper = type.fenUpperChar
        return color == .white ? upper : Character(String(upper).lowercased())
    }

    var symbol: String {
        String(fenChar)
    }

    /// Outlined unicode glyph (used for white or labels)
    var unicode: String {
        switch (color, type) {
        case (.white, .king): return "♔"
        case (.white, .queen): return "♕"
        case (.white, .rook): return "♖"
        case (.white, .bishop): return "♗"
        case (.white, .knight): return "♘"
        case (.white, .pawn): return "♙"
        case (.black, .king): return "♚"
        case (.black, .queen): return "♛"
        case (.black, .rook): return "♜"
        case (.black, .bishop): return "♝"
        case (.black, .knight): return "♞"
        case (.black, .pawn): return "♟"
        }
    }

    /// Filled silhouette glyph (ideal for crisp UI rendering with custom fill + stroke)
    var solidUnicode: String {
        switch type {
        case .king: return "♚"
        case .queen: return "♛"
        case .rook: return "♜"
        case .bishop: return "♝"
        case .knight: return "♞"
        case .pawn: return "♟︎"
        }
    }

    var baseValue: Int {
        type.baseValue
    }

    init(color: PieceColor, type: PieceType) {
        self.color = color
        self.type = type
    }

    init?(fenChar: Character) {
        let color: PieceColor = fenChar.isUppercase ? .white : .black
        switch Character(fenChar.uppercased()) {
        case "P": self.init(color: color, type: .pawn)
        case "N": self.init(color: color, type: .knight)
        case "B": self.init(color: color, type: .bishop)
        case "R": self.init(color: color, type: .rook)
        case "Q": self.init(color: color, type: .queen)
        case "K": self.init(color: color, type: .king)
        default: return nil
        }
    }
}

struct BoardSquare: Codable, Equatable, Hashable, Sendable {
    /// 0 = rank 8 (top), 7 = rank 1 (bottom)
    let row: Int
    /// 0 = file 'a' (left), 7 = file 'h' (right)
    let col: Int

    var isValid: Bool {
        row >= 0 && row < 8 && col >= 0 && col < 8
    }

    var fileChar: Character {
        let files = Array("abcdefgh")
        return files[col]
    }

    var rankNumber: Int {
        8 - row
    }

    var algebraic: String {
        "\(fileChar)\(rankNumber)"
    }

    var isLightSquare: Bool {
        (row + col) % 2 == 0
    }

    init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }

    init?(algebraic: String) {
        let trimmed = algebraic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count == 2 else { return nil }
        let chars = Array(trimmed)
        let files = Array("abcdefgh")
        guard let colIndex = files.firstIndex(of: chars[0]),
              let rank = Int(String(chars[1])),
              rank >= 1 && rank <= 8 else {
            return nil
        }
        self.row = 8 - rank
        self.col = colIndex
    }
}

struct CastlingRights: Codable, Equatable, Hashable, Sendable {
    var whiteKingside: Bool = true
    var whiteQueenside: Bool = true
    var blackKingside: Bool = true
    var blackQueenside: Bool = true

    static let all = CastlingRights(whiteKingside: true, whiteQueenside: true, blackKingside: true, blackQueenside: true)
    static let none = CastlingRights(whiteKingside: false, whiteQueenside: false, blackKingside: false, blackQueenside: false)

    var fenString: String {
        var str = ""
        if whiteKingside { str.append("K") }
        if whiteQueenside { str.append("Q") }
        if blackKingside { str.append("k") }
        if blackQueenside { str.append("q") }
        return str.isEmpty ? "-" : str
    }

    init(whiteKingside: Bool = true, whiteQueenside: Bool = true, blackKingside: Bool = true, blackQueenside: Bool = true) {
        self.whiteKingside = whiteKingside
        self.whiteQueenside = whiteQueenside
        self.blackKingside = blackKingside
        self.blackQueenside = blackQueenside
    }

    init(fenString: String) {
        self.whiteKingside = fenString.contains("K")
        self.whiteQueenside = fenString.contains("Q")
        self.blackKingside = fenString.contains("k")
        self.blackQueenside = fenString.contains("q")
    }
}

struct ChessMove: Identifiable, Codable, Equatable, Hashable, Sendable {
    let from: BoardSquare
    let to: BoardSquare
    let promotion: PieceType?
    let capturedPiece: ChessPiece?
    let isEnPassant: Bool
    let isCastling: Bool
    var san: String
    var tacticalTag: String?

    var id: String { uci }

    var uci: String {
        from.algebraic + to.algebraic + (promotion?.promotionUCI ?? "")
    }

    var coordinateDisplay: String {
        let promo = promotion != nil ? "=\(promotion!.sanLetter)" : ""
        return "\(from.algebraic) → \(to.algebraic)\(promo)"
    }

    init(
        from: BoardSquare,
        to: BoardSquare,
        promotion: PieceType? = nil,
        capturedPiece: ChessPiece? = nil,
        isEnPassant: Bool = false,
        isCastling: Bool = false,
        san: String = "",
        tacticalTag: String? = nil
    ) {
        self.from = from
        self.to = to
        self.promotion = promotion
        self.capturedPiece = capturedPiece
        self.isEnPassant = isEnPassant
        self.isCastling = isCastling
        self.san = san
        self.tacticalTag = tacticalTag
    }
}

enum CampDetectionMode: String, CaseIterable, Identifiable, Sendable {
    case auto = "auto"
    case forceWhite = "white"
    case forceBlack = "black"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "自動識別"
        case .forceWhite: return "固定我執白"
        case .forceBlack: return "固定我執黑"
        }
    }
}

enum PlayStyleMode: String, CaseIterable, Identifiable, Sendable {
    case engineBest = "engineBest"
    case humanSafe = "humanSafe"
    case aggressive = "aggressive"
    case defensive = "defensive"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .engineBest: return "最強引擎"
        case .humanSafe: return "自然防封"
        case .aggressive: return "積極進攻"
        case .defensive: return "穩健防守"
        }
    }

    var icon: String {
        switch self {
        case .engineBest: return "cpu"
        case .humanSafe: return "theatermasks"
        case .aggressive: return "flame.fill"
        case .defensive: return "shield.fill"
        }
    }
}

enum BotTargetProfile: String, CaseIterable, Identifiable, Sendable {
    case universal = "universal"
    case antiNelson = "antiNelson"
    case beginnerCrusher = "beginnerCrusher"
    case antiMaster = "antiMaster"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .universal: return "通用全能克制"
        case .antiNelson: return "克制 Nelson (抓早出后)"
        case .beginnerCrusher: return "速勝低階 Bot (連將壓制)"
        case .antiMaster: return "高階大師 Bot (零破綻穩健)"
        }
    }

    var shortName: String {
        switch self {
        case .universal: return "通用Bot"
        case .antiNelson: return "克Nelson"
        case .beginnerCrusher: return "速勝Bot"
        case .antiMaster: return "抗大師"
        }
    }

    var tacticTip: String {
        switch self {
        case .universal: return "平衡計算子力與位置，適用所有一般電腦對局。"
        case .antiNelson: return "專門懲罰愛早出皇后的進攻型 Bot，優先出子抓后搶先手。"
        case .beginnerCrusher: return "優先選擇將軍、吃子與快速攻王路線，迅速結束對局。"
        case .antiMaster: return "提高兵形結構與王翼安全權重，避免給 2000+ 高階 Bot 反擊機會。"
        }
    }
}

enum BoardTheme: String, CaseIterable, Identifiable, Sendable {
    case glacierBlue = "glacierBlue"
    case classicGreen = "classicGreen"
    case cyberPurple = "cyberPurple"
    case walnutWood = "walnutWood"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .glacierBlue: return "冰川藍"
        case .classicGreen: return "經典綠"
        case .cyberPurple: return "深邃紫"
        case .walnutWood: return "胡桃木"
        }
    }

    var lightRGB: (Double, Double, Double) {
        switch self {
        case .glacierBlue: return (0.918, 0.914, 0.898)
        case .classicGreen: return (0.922, 0.925, 0.816)
        case .cyberPurple: return (0.890, 0.865, 0.945)
        case .walnutWood: return (0.941, 0.851, 0.710)
        }
    }

    var darkRGB: (Double, Double, Double) {
        switch self {
        case .glacierBlue: return (0.298, 0.545, 0.678)
        case .classicGreen: return (0.467, 0.584, 0.337)
        case .cyberPurple: return (0.465, 0.365, 0.665)
        case .walnutWood: return (0.710, 0.533, 0.388)
        }
    }
}

struct TacticalRadarReport: Equatable, Sendable {
    let materialDiffForPerspective: Int
    let capturedByUser: [ChessPiece]
    let capturedByOpponent: [ChessPiece]
    let hangingFriendlySquares: [BoardSquare]
    let hangingDescriptions: [String]
    let freeTargetDescriptions: [String]
    let openingName: String
    let recommendedThinkRange: String
}

struct PVLine: Identifiable, Equatable, Sendable {
    let multipvIndex: Int
    let bestMove: ChessMove
    let continuationSAN: [String]
    let continuationUCI: [String]
    /// Score in centipawns from White's perspective (+ = White better, - = Black better)
    let scoreCentipawns: Int
    /// Mate in N moves from White's perspective (+N = White mates in N, -N = Black mates in N)
    let mateInMoves: Int?
    let depth: Int
    let sourceLabel: String
    let predictedOpponentReply: ChessMove?

    init(
        multipvIndex: Int,
        bestMove: ChessMove,
        continuationSAN: [String],
        continuationUCI: [String],
        scoreCentipawns: Int,
        mateInMoves: Int?,
        depth: Int,
        sourceLabel: String,
        predictedOpponentReply: ChessMove? = nil
    ) {
        self.multipvIndex = multipvIndex
        self.bestMove = bestMove
        self.continuationSAN = continuationSAN
        self.continuationUCI = continuationUCI
        self.scoreCentipawns = scoreCentipawns
        self.mateInMoves = mateInMoves
        self.depth = depth
        self.sourceLabel = sourceLabel
        self.predictedOpponentReply = predictedOpponentReply
    }

    var id: Int { multipvIndex }

    /// White's win probability (0.0 ... 100.0)
    var winProbabilityWhite: Double {
        if let mate = mateInMoves {
            return mate > 0 ? 100.0 : 0.0
        }
        return 100.0 / (1.0 + exp(-0.00368208 * Double(scoreCentipawns)))
    }

    func winProbability(for side: PieceColor) -> Double {
        side == .white ? winProbabilityWhite : (100.0 - winProbabilityWhite)
    }

    var formattedScore: String {
        if let mate = mateInMoves {
            return mate > 0 ? "+M\(mate)" : "-M\(abs(mate))"
        }
        let pawns = Double(scoreCentipawns) / 100.0
        if abs(pawns) < 0.05 {
            return "0.00"
        }
        return String(format: "%+.2f", pawns)
    }

    var continuationPreview: String {
        let line = continuationSAN.prefix(6).joined(separator: " ")
        return line.isEmpty ? bestMove.san : line
    }
}

struct EngineAnalysisResult: Equatable, Sendable {
    let fen: String
    let sideToMove: PieceColor
    let lines: [PVLine]
    let depthReached: Int
    let isCloudVerified: Bool
    let engineSource: String
    let nodesSearched: Int
    let timestamp: Date

    var primaryLine: PVLine? { lines.first }

    var evalBarFractionWhite: Double {
        guard let line = primaryLine else { return 0.5 }
        return min(0.96, max(0.04, line.winProbabilityWhite / 100.0))
    }
}
