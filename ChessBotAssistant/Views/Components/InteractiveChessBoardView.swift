import SwiftUI

struct InteractiveChessBoardView: View {
    let boardState: ChessBoardState
    let perspective: PieceColor
    let selectedSquare: BoardSquare?
    let legalTargets: [ChessMove]
    let lastMove: ChessMove?
    let pvLines: [PVLine]
    let showAutoHintArrows: Bool
    let highlightedPVIndex: Int?
    var coachPieceOnlyMode: Bool = false
    var isSafetyLocked: Bool = false
    var hangingSquares: Set<BoardSquare> = []
    var showOpponentReplyArrow: Bool = true
    var boardTheme: BoardTheme = .glacierBlue
    let onTapSquare: (BoardSquare) -> Void

    private var lightSquareColor: Color {
        let rgb = boardTheme.lightRGB
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private var darkSquareColor: Color {
        let rgb = boardTheme.darkRGB
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private let files = ["a", "b", "c", "d", "e", "f", "g", "h"]

    var body: some View {
        GeometryReader { geo in
            let boardSize = max(16, min(geo.size.width, geo.size.height))
            let cellSize = boardSize / 8.0

            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { screenRow in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { screenCol in
                                let boardRow = perspective == .white ? screenRow : (7 - screenRow)
                                let boardCol = perspective == .white ? screenCol : (7 - screenCol)
                                let square = BoardSquare(row: boardRow, col: boardCol)
                                let piece = boardState.squares[boardRow][boardCol]
                                let isSelected = selectedSquare == square
                                let targetMove = legalTargets.first { $0.to == square }
                                let isBestFrom = !isSafetyLocked && showAutoHintArrows && pvLines.first?.bestMove.from == square
                                let isBestTo = !isSafetyLocked && !coachPieceOnlyMode && showAutoHintArrows && pvLines.first?.bestMove.to == square
                                let isLastMoveSquare = lastMove?.from == square || lastMove?.to == square
                                let isCheckedKing = piece?.type == .king &&
                                    piece?.color == boardState.sideToMove &&
                                    boardState.isKingInCheck(boardState.sideToMove)
                                let isHanging = hangingSquares.contains(square)

                                ZStack {
                                    // Base square color
                                    (square.isLightSquare ? lightSquareColor : darkSquareColor)

                                    // Last move tint
                                    if isLastMoveSquare {
                                        Color(red: 0.96, green: 0.94, blue: 0.32).opacity(0.38)
                                    }

                                    // Best move square highlight
                                    if isBestFrom {
                                        Color(red: 0.35, green: 0.88, blue: 0.42).opacity(0.32)
                                    } else if isBestTo {
                                        Color(red: 0.35, green: 0.88, blue: 0.42).opacity(0.45)
                                    }

                                    // Selected square highlight
                                    if isSelected {
                                        Color(red: 0.98, green: 0.82, blue: 0.25).opacity(0.58)
                                    }

                                    // King in check radial glow
                                    if isCheckedKing {
                                        RadialGradient(
                                            colors: [Color.red.opacity(0.88), Color.red.opacity(0.0)],
                                            center: .center,
                                            startRadius: 2,
                                            endRadius: cellSize * 0.6
                                        )
                                    }

                                    // Hanging piece warning highlight
                                    if isHanging && !isCheckedKing {
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(Color(red: 1.0, green: 0.30, blue: 0.34).opacity(0.85), lineWidth: max(2, cellSize * 0.06))
                                            .padding(1.5)
                                    }

                                    // Rank coordinate on left edge
                                    if screenCol == 0 {
                                        Text("\(8 - boardRow)")
                                            .font(.system(size: max(8, cellSize * 0.21), weight: .bold))
                                            .foregroundColor(square.isLightSquare ? darkSquareColor : lightSquareColor)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                            .padding(.leading, 2)
                                            .padding(.top, 1)
                                    }

                                    // File coordinate on bottom edge
                                    if screenRow == 7 {
                                        Text(files[boardCol])
                                            .font(.system(size: max(8, cellSize * 0.21), weight: .bold))
                                            .foregroundColor(square.isLightSquare ? darkSquareColor : lightSquareColor)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                            .padding(.trailing, 2)
                                            .padding(.bottom, 1)
                                    }

                                    // Piece rendering
                                    if let piece {
                                        PieceView(piece: piece, cellSize: cellSize)
                                    }

                                    // Legal move target indicators
                                    if targetMove != nil {
                                        if piece != nil {
                                            Circle()
                                                .stroke(Color.black.opacity(0.28), lineWidth: max(3, cellSize * 0.1))
                                                .padding(cellSize * 0.08)
                                        } else {
                                            Circle()
                                                .fill(Color.black.opacity(0.22))
                                                .frame(width: cellSize * 0.30, height: cellSize * 0.30)
                                        }
                                    }
                                }
                                .frame(width: cellSize, height: cellSize)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onTapSquare(square)
                                }
                            }
                        }
                    }
                }
                .frame(width: boardSize, height: boardSize)

                MoveArrowOverlayView(
                    pvLines: pvLines,
                    perspective: perspective,
                    showArrows: showAutoHintArrows,
                    highlightedPVIndex: highlightedPVIndex,
                    coachPieceOnlyMode: coachPieceOnlyMode,
                    isSafetyLocked: isSafetyLocked,
                    showOpponentReplyArrow: showOpponentReplyArrow
                )
                .frame(width: boardSize, height: boardSize)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct PieceView: View {
    let piece: ChessPiece
    let cellSize: CGFloat

    var body: some View {
        ZStack {
            if piece.color == .white {
                // Crisp dark outline underneath bright white silhouette
                Text(piece.solidUnicode)
                    .font(.system(size: cellSize * 0.78))
                    .foregroundColor(Color(white: 0.12))
                    .shadow(color: Color(white: 0.12), radius: 0.8, x: 0.6, y: 0.6)
                    .shadow(color: Color(white: 0.12), radius: 0.8, x: -0.6, y: -0.6)
                Text(piece.solidUnicode)
                    .font(.system(size: cellSize * 0.74))
                    .foregroundColor(Color(red: 0.99, green: 0.99, blue: 0.97))
            } else {
                // Subtle light rim underneath charcoal black piece
                Text(piece.solidUnicode)
                    .font(.system(size: cellSize * 0.77))
                    .foregroundColor(Color.white.opacity(0.45))
                    .offset(y: -0.4)
                Text(piece.solidUnicode)
                    .font(.system(size: cellSize * 0.75))
                    .foregroundColor(Color(red: 0.13, green: 0.14, blue: 0.16))
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            }
        }
    }
}
