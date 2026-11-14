import SwiftUI

struct BoardEditorSheetView: View {
    @ObservedObject var viewModel: AssistantViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var draftBoard: ChessBoardState = .startingPosition
    @State private var selectedToolPiece: ChessPiece? = ChessPiece(color: .white, type: .queen)
    @State private var isEraserSelected: Bool = false

    private let whitePalette: [ChessPiece] = [
        ChessPiece(color: .white, type: .king),
        ChessPiece(color: .white, type: .queen),
        ChessPiece(color: .white, type: .rook),
        ChessPiece(color: .white, type: .bishop),
        ChessPiece(color: .white, type: .knight),
        ChessPiece(color: .white, type: .pawn)
    ]

    private let blackPalette: [ChessPiece] = [
        ChessPiece(color: .black, type: .king),
        ChessPiece(color: .black, type: .queen),
        ChessPiece(color: .black, type: .rook),
        ChessPiece(color: .black, type: .bishop),
        ChessPiece(color: .black, type: .knight),
        ChessPiece(color: .black, type: .pawn)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    InteractiveChessBoardView(
                        boardState: draftBoard,
                        perspective: viewModel.perspective,
                        selectedSquare: nil,
                        legalTargets: [],
                        lastMove: nil,
                        pvLines: [],
                        showAutoHintArrows: false,
                        highlightedPVIndex: nil,
                        onTapSquare: { square in
                            if isEraserSelected {
                                draftBoard.squares[square.row][square.col] = nil
                            } else if let tool = selectedToolPiece {
                                if draftBoard.squares[square.row][square.col] == tool {
                                    draftBoard.squares[square.row][square.col] = nil
                                } else {
                                    draftBoard.squares[square.row][square.col] = tool
                                }
                            }
                        }
                    )
                    .padding(.horizontal, 12)

                    // Piece palette
                    VStack(spacing: 8) {
                        paletteRow(pieces: whitePalette)
                        paletteRow(pieces: blackPalette)
                    }
                    .padding(.horizontal, 12)

                    // Controls
                    HStack(spacing: 10) {
                        Button {
                            isEraserSelected = true
                            selectedToolPiece = nil
                        } label: {
                            Label("清除格位", systemImage: "eraser.fill")
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(isEraserSelected ? Color.red.opacity(0.30) : Color.white.opacity(0.10))
                                .foregroundColor(isEraserSelected ? .red : .white)
                                .clipShape(Capsule())
                        }

                        Button {
                            draftBoard = .empty
                        } label: {
                            Label("清空棋盤", systemImage: "trash")
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.10))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }

                        Button {
                            draftBoard = .startingPosition
                        } label: {
                            Label("標準擺法", systemImage: "arrow.counterclockwise")
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.10))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }

                    Picker("輪到走棋", selection: $draftBoard.sideToMove) {
                        Text("白方走").tag(PieceColor.white)
                        Text("黑方走").tag(PieceColor.black)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("手動擺盤與微調")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("套用局面") {
                        viewModel.applyCustomBoard(draftBoard)
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear {
                draftBoard = viewModel.boardState
            }
        }
        .preferredColorScheme(.dark)
    }

    private func paletteRow(pieces: [ChessPiece]) -> some View {
        HStack(spacing: 8) {
            ForEach(pieces, id: \.self) { piece in
                let isSelected = !isEraserSelected && selectedToolPiece == piece
                Button {
                    isEraserSelected = false
                    selectedToolPiece = piece
                } label: {
                    PieceView(piece: piece, cellSize: 38)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? Color(red: 0.50, green: 0.72, blue: 0.30).opacity(0.32) : Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelected ? Color(red: 0.50, green: 0.72, blue: 0.30) : Color.clear, lineWidth: 2)
                        )
                }
            }
        }
    }
}
