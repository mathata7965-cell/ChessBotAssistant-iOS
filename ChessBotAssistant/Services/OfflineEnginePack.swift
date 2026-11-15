import Foundation

struct OfflineBookMove: Codable, Sendable {
    let uci: String
    let cp: Int
    let weight: Int
    let opening: String
    let note: String
}

struct BotCounterGuide: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let rating: Int
    let style: String
    let weakness: String
    let counterTip: String
}

private struct OfflinePackMetadata: Decodable {
    let book: [String: [OfflineBookMove]]
    let botGuides: [BotCounterGuide]
}

final class OfflineEnginePack: @unchecked Sendable {
    static let shared = OfflineEnginePack()

    let isLoaded: Bool
    let packByteCount: Int
    let botGuides: [BotCounterGuide]

    private let book: [String: [OfflineBookMove]]
    private let placementSideBook: [String: [OfflineBookMove]]
    private let mappedData: Data?
    private let tableOffset: Int
    private let tableLength: Int
    private let zobristKeys: [UInt64]

    var packSizeMBString: String {
        if packByteCount <= 0 { return "0.0 MB" }
        return String(format: "%.1f MB", Double(packByteCount) / (1024.0 * 1024.0))
    }

    var bookPositionCount: Int {
        book.count
    }

    private init() {
        var loadedBook: [String: [OfflineBookMove]] = [:]
        var loadedPlacementSide: [String: [OfflineBookMove]] = [:]
        var loadedGuides: [BotCounterGuide] = []
        var loadedData: Data? = nil
        var parsedByteCount = 0
        var parsedTableOffset = 0
        var parsedTableLength = 0
        var keys: [UInt64] = []

        if let url = Self.locatePackURL(),
           let data = try? Data(contentsOf: url, options: .mappedIfSafe),
           data.count >= 16,
           String(data: data.subdata(in: 0..<8), encoding: .ascii) == "CBOTPACK" {
            let jsonLen = Int(Self.readUInt32LE(data: data, offset: 12))
            let jsonEnd = 16 + jsonLen
            if jsonLen > 0 && jsonEnd <= data.count {
                let jsonData = data.subdata(in: 16..<jsonEnd)
                if let meta = try? JSONDecoder().decode(OfflinePackMetadata.self, from: jsonData) {
                    loadedBook = meta.book
                    loadedGuides = meta.botGuides
                    for (fullKey, moves) in meta.book {
                        let parts = fullKey.split(separator: " ")
                        if parts.count >= 2 {
                            let shortKey = "\(parts[0]) \(parts[1])"
                            if loadedPlacementSide[shortKey] == nil {
                                loadedPlacementSide[shortKey] = moves
                            }
                        }
                    }
                }
                loadedData = data
                parsedByteCount = data.count

                // Read 1,024 uint64 Zobrist keys (8,192 bytes) from start of binary table
                let keyBytesNeeded = 1024 * 8
                if jsonEnd + keyBytesNeeded <= data.count {
                    keys.reserveCapacity(1024)
                    for i in 0..<1024 {
                        keys.append(Self.readUInt64LE(data: data, offset: jsonEnd + i * 8))
                    }
                    parsedTableOffset = jsonEnd + keyBytesNeeded
                    parsedTableLength = data.count - parsedTableOffset
                }
            }
        }

        if keys.count < 1024 {
            keys = Self.fallbackZobristKeys(count: 1024)
        }

        self.isLoaded = loadedData != nil && !loadedBook.isEmpty
        self.packByteCount = parsedByteCount
        self.book = loadedBook
        self.placementSideBook = loadedPlacementSide
        self.botGuides = loadedGuides
        self.mappedData = loadedData
        self.tableOffset = parsedTableOffset
        self.tableLength = parsedTableLength
        self.zobristKeys = keys
    }

    private static func locatePackURL() -> URL? {
        if let direct = Bundle.main.url(forResource: "OfflineEnginePack", withExtension: "bin") {
            return direct
        }
        if let resURL = Bundle.main.resourceURL?.appendingPathComponent("OfflineEnginePack.bin"),
           FileManager.default.fileExists(atPath: resURL.path) {
            return resURL
        }
        return nil
    }

    private static func readUInt32LE(data: Data, offset: Int) -> UInt32 {
        var value: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &value) { dst in
            data.copyBytes(to: dst, from: offset..<(offset + 4))
        }
        return UInt32(littleEndian: value)
    }

    private static func readUInt64LE(data: Data, offset: Int) -> UInt64 {
        var value: UInt64 = 0
        _ = withUnsafeMutableBytes(of: &value) { dst in
            data.copyBytes(to: dst, from: offset..<(offset + 8))
        }
        return UInt64(littleEndian: value)
    }

    private static func fallbackZobristKeys(count: Int) -> [UInt64] {
        var x: UInt64 = 0x9E3779B97F4A7C15
        var out: [UInt64] = []
        out.reserveCapacity(count)
        for _ in 0..<count {
            x &+= 0x9E3779B97F4A7C15
            var z = x
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z = z ^ (z >> 31)
            out.append(z)
        }
        return out
    }

    private func pieceZobristIndex(_ piece: ChessPiece) -> Int {
        let base: Int
        switch piece.type {
        case .pawn: base = 0
        case .knight: base = 1
        case .bishop: base = 2
        case .rook: base = 3
        case .queen: base = 4
        case .king: base = 5
        }
        return piece.color == .white ? base : (6 + base)
    }

    func computeZobristHash(for board: ChessBoardState) -> UInt64 {
        var h: UInt64 = 0
        for r in 0..<8 {
            for c in 0..<8 {
                if let piece = board.squares[r][c] {
                    let pIdx = pieceZobristIndex(piece)
                    let keyIdx = pIdx * 64 + r * 8 + c
                    h ^= zobristKeys[keyIdx]
                }
            }
        }
        if board.sideToMove == .black {
            h ^= zobristKeys[768]
        }
        var castMask = 0
        if board.castlingRights.whiteKingside { castMask |= 1 }
        if board.castlingRights.whiteQueenside { castMask |= 2 }
        if board.castlingRights.blackKingside { castMask |= 4 }
        if board.castlingRights.blackQueenside { castMask |= 8 }
        h ^= zobristKeys[769 + castMask]
        if let ep = board.enPassantTarget {
            h ^= zobristKeys[785 + (ep.col & 7)]
        }
        return h
    }

    /// Quantized [-3...3] positional micro-adjustment backed by the mapped binary table.
    func nnueTableAdjustment(piece: ChessPiece, row: Int, col: Int, phase: Int) -> Int {
        guard tableLength > 2048, let mappedData else { return 0 }
        let pIdx = pieceZobristIndex(piece)
        let phaseBucket = min(3, max(0, phase / 7))
        let slot = ((phaseBucket * 768 + pIdx * 64 + row * 8 + col) * 7) % tableLength
        let rawByte = Int(mappedData[tableOffset + slot])
        return (rawByte % 7) - 3
    }

    func lookupBookLines(for board: ChessBoardState, multiPV: Int) -> (lines: [PVLine], openingName: String)? {
        let fullKey = board.positionKey
        let parts = fullKey.split(separator: " ")
        let shortKey = parts.count >= 2 ? "\(parts[0]) \(parts[1])" : fullKey
        guard let rawEntries = book[fullKey] ?? placementSideBook[shortKey], !rawEntries.isEmpty else {
            return nil
        }

        let sortedEntries = rawEntries.sorted { $0.weight > $1.weight }
        var pvLines: [PVLine] = []

        for entry in sortedEntries {
            guard var bestMove = board.legalMove(uci: entry.uci) else { continue }
            if bestMove.tacticalTag == nil || bestMove.tacticalTag?.isEmpty == true {
                bestMove.tacticalTag = entry.opening
            }

            // Trace up to 4 book replies for a rich continuation preview
            var uciLine = [entry.uci]
            var cursor = board.applying(bestMove)
            for _ in 0..<4 {
                let k = cursor.positionKey
                let kp = k.split(separator: " ")
                let sk = kp.count >= 2 ? "\(kp[0]) \(kp[1])" : k
                guard let nextEntry = (book[k] ?? placementSideBook[sk])?.max(by: { $0.weight < $1.weight }),
                      let nextMove = cursor.legalMove(uci: nextEntry.uci) else {
                    break
                }
                uciLine.append(nextEntry.uci)
                cursor = cursor.applying(nextMove)
            }

            let sanLine = ChessEngineService.convertUCILineToSAN(startBoard: board, uciMoves: uciLine)
            let reply = ChessEngineService.extractOpponentReply(
                on: board,
                firstMove: bestMove,
                continuationUCI: uciLine
            )

            let reason = entry.note.isEmpty
                ? board.explainMoveTactics(bestMove)
                : "\(entry.opening)：\(entry.note)"

            pvLines.append(PVLine(
                multipvIndex: pvLines.count + 1,
                bestMove: bestMove,
                continuationSAN: sanLine,
                continuationUCI: uciLine,
                scoreCentipawns: entry.cp,
                mateInMoves: nil,
                depth: 20,
                sourceLabel: "GM大師庫",
                predictedOpponentReply: reply,
                tacticalReason: reason
            ))

            if pvLines.count >= multiPV { break }
        }

        guard !pvLines.isEmpty else { return nil }
        return (pvLines, sortedEntries[0].opening)
    }
}
