import SwiftUI

struct MoveArrowOverlayView: View {
    let pvLines: [PVLine]
    let perspective: PieceColor
    let showArrows: Bool
    let highlightedPVIndex: Int?
    var coachPieceOnlyMode: Bool = false
    var isSafetyLocked: Bool = false
    var showOpponentReplyArrow: Bool = true

    private func arrowColor(for rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 0.35, green: 0.88, blue: 0.42).opacity(0.90)
        case 2: return Color(red: 0.22, green: 0.78, blue: 0.96).opacity(0.75)
        default: return Color(red: 0.98, green: 0.72, blue: 0.22).opacity(0.70)
        }
    }

    var body: some View {
        GeometryReader { geo in
            if showArrows && !isSafetyLocked && !coachPieceOnlyMode && !pvLines.isEmpty {
                let size = max(16, min(geo.size.width, geo.size.height))
                let cell = size / 8.0

                Canvas { context, _ in
                    // Draw secondary lines first, primary line on top
                    let ordered = pvLines.prefix(3).sorted { a, b in
                        if a.multipvIndex == highlightedPVIndex { return false }
                        if b.multipvIndex == highlightedPVIndex { return true }
                        return a.multipvIndex > b.multipvIndex
                    }

                    for line in ordered {
                        let isTop = line.multipvIndex == (highlightedPVIndex ?? 1)
                        let color = arrowColor(for: line.multipvIndex)
                        let lineWidth: CGFloat = isTop ? max(7.0, cell * 0.20) : max(4.5, cell * 0.13)

                        let p0 = centerPoint(for: line.bestMove.from, cellSize: cell)
                        let p1 = centerPoint(for: line.bestMove.to, cellSize: cell)

                        drawArrow(
                            in: &context,
                            from: p0,
                            to: p1,
                            color: color,
                            lineWidth: lineWidth,
                            rankBadge: pvLines.count > 1 ? "\(line.multipvIndex)" : nil,
                            isDashed: false
                        )
                    }

                    // Draw dashed crimson arrow for predicted opponent reply on highlighted/primary PV line
                    if showOpponentReplyArrow {
                        let activeLine = pvLines.first(where: { $0.multipvIndex == (highlightedPVIndex ?? 1) }) ?? pvLines.first
                        if let reply = activeLine?.predictedOpponentReply {
                            let rp0 = centerPoint(for: reply.from, cellSize: cell)
                            let rp1 = centerPoint(for: reply.to, cellSize: cell)
                            drawArrow(
                                in: &context,
                                from: rp0,
                                to: rp1,
                                color: Color(red: 1.0, green: 0.32, blue: 0.36).opacity(0.85),
                                lineWidth: max(4.5, cell * 0.13),
                                rankBadge: "敵",
                                isDashed: true
                            )
                        }
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func centerPoint(for square: BoardSquare, cellSize: CGFloat) -> CGPoint {
        let screenCol = perspective == .white ? square.col : (7 - square.col)
        let screenRow = perspective == .white ? square.row : (7 - square.row)
        return CGPoint(
            x: (CGFloat(screenCol) + 0.5) * cellSize,
            y: (CGFloat(screenRow) + 0.5) * cellSize
        )
    }

    private func drawArrow(
        in context: inout GraphicsContext,
        from p0: CGPoint,
        to p1: CGPoint,
        color: Color,
        lineWidth: CGFloat,
        rankBadge: String?,
        isDashed: Bool = false
    ) {
        let dx = p1.x - p0.x
        let dy = p1.y - p0.y
        let length = hypot(dx, dy)
        guard length > 4 else { return }

        let ux = dx / length
        let uy = dy / length

        let headLength = lineWidth * 2.35
        let headHalfWidth = lineWidth * 1.32
        let shaftStart = CGPoint(x: p0.x + ux * (lineWidth * 0.6), y: p0.y + uy * (lineWidth * 0.6))
        let shaftEnd = CGPoint(x: p1.x - ux * (headLength * 0.72), y: p1.y - uy * (headLength * 0.72))

        var shaft = Path()
        shaft.move(to: shaftStart)
        shaft.addLine(to: shaftEnd)
        context.stroke(
            shaft,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round,
                dash: isDashed ? [max(5, lineWidth * 1.15), max(4, lineWidth * 0.95)] : []
            )
        )

        let perpX = -uy
        let perpY = ux
        let baseCenter = CGPoint(x: p1.x - ux * headLength, y: p1.y - uy * headLength)
        let leftWing = CGPoint(x: baseCenter.x + perpX * headHalfWidth, y: baseCenter.y + perpY * headHalfWidth)
        let rightWing = CGPoint(x: baseCenter.x - perpX * headHalfWidth, y: baseCenter.y - perpY * headHalfWidth)

        var head = Path()
        head.move(to: p1)
        head.addLine(to: leftWing)
        head.addLine(to: rightWing)
        head.closeSubpath()
        context.fill(head, with: .color(color))

        if let rankBadge {
            let badgeCenter = CGPoint(
                x: p0.x + ux * (length * 0.36),
                y: p0.y + uy * (length * 0.36)
            )
            let radius: CGFloat = max(7.5, lineWidth * 0.95)
            let circleRect = CGRect(
                x: badgeCenter.x - radius,
                y: badgeCenter.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: circleRect), with: .color(Color(red: 0.08, green: 0.10, blue: 0.12)))
            context.stroke(Path(ellipseIn: circleRect), with: .color(color), lineWidth: 1.5)
            context.draw(
                Text(rankBadge)
                    .font(.system(size: radius * 1.15, weight: .heavy, design: .rounded))
                    .foregroundColor(.white),
                at: badgeCenter
            )
        }
    }
}
