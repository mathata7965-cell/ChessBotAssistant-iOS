import SwiftUI
import WebKit

struct LiveChessArrowPayload: Encodable, Equatable {
    let fromRow: Int
    let fromCol: Int
    let toRow: Int
    let toCol: Int
    let rank: Int
    let pieceOnly: Bool
}

struct LiveChessWebView: UIViewRepresentable {
    let lines: [PVLine]
    let showArrows: Bool
    let coachPieceOnly: Bool
    let reloadToken: UUID
    let onBoardSync: @MainActor (String, Bool, PieceColor?) -> Void

    static let computerPlayURL = URL(string: "https://www.chess.com/play/computer")!

    func makeCoordinator() -> Coordinator {
        Coordinator(onBoardSync: onBoardSync)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(
            WeakScriptMessageHandler(delegate: context.coordinator),
            name: "chessSync"
        )

        let script = WKUserScript(
            source: Self.observerJavaScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(script)

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.11, green: 0.13, blue: 0.16, alpha: 1.0)
        webView.scrollView.backgroundColor = UIColor(red: 0.11, green: 0.13, blue: 0.16, alpha: 1.0)

        context.coordinator.lastReloadToken = reloadToken
        webView.load(URLRequest(url: Self.computerPlayURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onBoardSync = onBoardSync

        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            webView.load(URLRequest(url: Self.computerPlayURL))
            return
        }

        let payloads: [LiveChessArrowPayload]
        if coachPieceOnly, let best = lines.first {
            payloads = [
                LiveChessArrowPayload(
                    fromRow: best.bestMove.from.row,
                    fromCol: best.bestMove.from.col,
                    toRow: best.bestMove.from.row,
                    toCol: best.bestMove.from.col,
                    rank: 0,
                    pieceOnly: true
                )
            ]
        } else if showArrows {
            payloads = lines.prefix(3).enumerated().map { idx, line in
                LiveChessArrowPayload(
                    fromRow: line.bestMove.from.row,
                    fromCol: line.bestMove.from.col,
                    toRow: line.bestMove.to.row,
                    toCol: line.bestMove.to.col,
                    rank: idx,
                    pieceOnly: false
                )
            }
        } else {
            payloads = []
        }

        guard payloads != context.coordinator.lastSentPayloads else { return }
        context.coordinator.lastSentPayloads = payloads

        if let data = try? JSONEncoder().encode(payloads),
           let json = String(data: data, encoding: .utf8) {
            let js = "if (window.__updateAssistantArrows) { window.__updateAssistantArrows(\(json)); }"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.evaluateJavaScript(
            "if (window.__agySyncTimer) { clearInterval(window.__agySyncTimer); window.__agySyncTimer = null; }",
            completionHandler: nil
        )
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "chessSync")
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onBoardSync: @MainActor (String, Bool, PieceColor?) -> Void
        var lastSentPayloads: [LiveChessArrowPayload] = []
        var lastReloadToken: UUID = UUID()

        init(onBoardSync: @escaping @MainActor (String, Bool, PieceColor?) -> Void) {
            self.onBoardSync = onBoardSync
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "chessSync",
                  let body = message.body as? [String: Any],
                  let fenBoard = body["fenBoard"] as? String else {
                return
            }
            let flipped = (body["flipped"] as? Bool) ?? false
            let turnStr = body["turnHint"] as? String
            let turnHint: PieceColor? = switch turnStr {
            case "w": .white
            case "b": .black
            default: nil
            }

            Task { @MainActor [onBoardSync] in
                onBoardSync(fenBoard, flipped, turnHint)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(LiveChessWebView.observerJavaScript, completionHandler: nil)
        }
    }

    private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
        weak var delegate: WKScriptMessageHandler?
        init(delegate: WKScriptMessageHandler) {
            self.delegate = delegate
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            delegate?.userContentController(userContentController, didReceive: message)
        }
    }

    // MARK: - Chess.com DOM Board Observer & SVG Arrow Overlay JS

    private static let observerJavaScript: String = #"""
    (function() {
        const fenMap = {
            wp: 'P', wn: 'N', wb: 'B', wr: 'R', wq: 'Q', wk: 'K',
            bp: 'p', bn: 'n', bb: 'b', br: 'r', bq: 'q', bk: 'k'
        };

        window.__assistantLastArrows = window.__assistantLastArrows || [];
        let lastSnapshot = "";

        function findBoardElement() {
            return document.querySelector('wc-chess-board, chess-board, .board');
        }

        function ensureArrowSVG(board) {
            if (!board) return null;
            let svg = document.getElementById('agy-assistant-arrows');
            if (!svg || svg.parentElement !== board) {
                if (svg && svg.parentElement) svg.parentElement.removeChild(svg);
                svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
                svg.setAttribute('id', 'agy-assistant-arrows');
                svg.setAttribute('viewBox', '0 0 800 800');
                svg.style.position = 'absolute';
                svg.style.top = '0';
                svg.style.left = '0';
                svg.style.width = '100%';
                svg.style.height = '100%';
                svg.style.pointerEvents = 'none';
                svg.style.zIndex = '9999';
                if (getComputedStyle(board).position === 'static') {
                    board.style.position = 'relative';
                }
                board.appendChild(svg);
            }
            return svg;
        }

        function renderArrows() {
            const board = findBoardElement();
            if (!board) return;
            const svg = ensureArrowSVG(board);
            if (!svg) return;

            while (svg.firstChild) svg.removeChild(svg.firstChild);
            const arrows = window.__assistantLastArrows || [];
            if (!arrows.length) return;

            const isFlipped = board.classList.contains('flipped');
            const palette = [
                'rgba(52, 224, 118, 0.88)',
                'rgba(56, 198, 245, 0.78)',
                'rgba(250, 184, 56, 0.74)'
            ];

            // Draw #3 -> #1 so primary #1 arrow sits on top
            for (let i = arrows.length - 1; i >= 0; i--) {
                const a = arrows[i];
                const color = palette[Math.min(a.rank || 0, palette.length - 1)];

                const fromSX = isFlipped ? (7 - a.fromCol) : a.fromCol;
                const fromSY = isFlipped ? (7 - a.fromRow) : a.fromRow;
                const cx = fromSX * 100 + 50;
                const cy = fromSY * 100 + 50;

                if (a.pieceOnly) {
                    const ring = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
                    ring.setAttribute('cx', cx);
                    ring.setAttribute('cy', cy);
                    ring.setAttribute('r', '38');
                    ring.setAttribute('fill', 'rgba(247, 235, 92, 0.25)');
                    ring.setAttribute('stroke', 'rgba(247, 235, 92, 0.95)');
                    ring.setAttribute('stroke-width', '8');
                    svg.appendChild(ring);
                    continue;
                }

                const toSX = isFlipped ? (7 - a.toCol) : a.toCol;
                const toSY = isFlipped ? (7 - a.toRow) : a.toRow;
                const ex = toSX * 100 + 50;
                const ey = toSY * 100 + 50;

                const dx = ex - cx;
                const dy = ey - cy;
                const len = Math.hypot(dx, dy);
                if (len < 1) continue;

                const ux = dx / len;
                const uy = dy / len;
                const headLen = (a.rank === 0) ? 28 : 22;
                const headHalf = (a.rank === 0) ? 16 : 12;
                const shaftW = (a.rank === 0) ? 14 : 9.5;

                const tipX = ex - ux * 10;
                const tipY = ey - uy * 10;
                const baseX = tipX - ux * headLen;
                const baseY = tipY - uy * headLen;
                const startX = cx + ux * 16;
                const startY = cy + uy * 16;

                const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
                line.setAttribute('x1', startX);
                line.setAttribute('y1', startY);
                line.setAttribute('x2', baseX);
                line.setAttribute('y2', baseY);
                line.setAttribute('stroke', color);
                line.setAttribute('stroke-width', shaftW);
                line.setAttribute('stroke-linecap', 'round');
                svg.appendChild(line);

                const px = -uy * headHalf;
                const py = ux * headHalf;
                const head = document.createElementNS('http://www.w3.org/2000/svg', 'polygon');
                head.setAttribute('points', `${tipX},${tipY} ${baseX + px},${baseY + py} ${baseX - px},${baseY - py}`);
                head.setAttribute('fill', color);
                svg.appendChild(head);
            }
        }

        window.__updateAssistantArrows = function(arrows) {
            window.__assistantLastArrows = Array.isArray(arrows) ? arrows : [];
            renderArrows();
        };

        function readBoardState() {
            const board = findBoardElement();
            if (!board) return;

            ensureArrowSVG(board);

            const grid = Array.from({ length: 8 }, () => Array(8).fill(null));
            const pieces = board.querySelectorAll('.piece');
            if (!pieces || pieces.length < 2) return;

            let hasWhiteKing = false;
            let hasBlackKing = false;

            const highlightSet = new Set();
            const highlights = board.querySelectorAll('.highlight');
            highlights.forEach(hl => {
                for (const cls of hl.classList) {
                    const m = /^square-([1-8])([1-8])$/.exec(cls);
                    if (m) highlightSet.add(`${m[1]}${m[2]}`);
                }
            });

            let lastMovedColor = null;

            pieces.forEach(el => {
                if (el.classList.contains('dragging')) return;
                let pieceCode = null;
                let sqKey = null;
                for (const cls of el.classList) {
                    if (fenMap[cls]) pieceCode = cls;
                    const m = /^square-([1-8])([1-8])$/.exec(cls);
                    if (m) sqKey = `${m[1]}${m[2]}`;
                }
                if (!pieceCode || !sqKey) return;

                const file = parseInt(sqKey[0], 10);
                const rank = parseInt(sqKey[1], 10);
                const col = file - 1;
                const row = 8 - rank;
                const fenChar = fenMap[pieceCode];
                grid[row][col] = fenChar;

                if (fenChar === 'K') hasWhiteKing = true;
                if (fenChar === 'k') hasBlackKing = true;

                if (highlightSet.has(sqKey)) {
                    lastMovedColor = pieceCode[0]; // 'w' or 'b'
                }
            });

            if (!hasWhiteKing || !hasBlackKing) return;

            const fenRows = [];
            for (let r = 0; r < 8; r++) {
                let rowStr = "";
                let empty = 0;
                for (let c = 0; c < 8; c++) {
                    const ch = grid[r][c];
                    if (!ch) {
                        empty++;
                    } else {
                        if (empty > 0) {
                            rowStr += empty;
                            empty = 0;
                        }
                        rowStr += ch;
                    }
                }
                if (empty > 0) rowStr += empty;
                fenRows.push(rowStr);
            }

            const fenBoard = fenRows.join('/');
            const flipped = board.classList.contains('flipped');
            const turnHint = lastMovedColor ? (lastMovedColor === 'w' ? 'b' : 'w') : '';
            const snapshot = `${fenBoard}|${flipped ? 1 : 0}|${turnHint}`;

            if (snapshot !== lastSnapshot) {
                lastSnapshot = snapshot;
                renderArrows();
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chessSync) {
                    window.webkit.messageHandlers.chessSync.postMessage({
                        fenBoard: fenBoard,
                        flipped: flipped,
                        turnHint: turnHint
                    });
                }
            }
        }

        if (window.__agySyncTimer) {
            clearInterval(window.__agySyncTimer);
        }
        window.__agySyncTimer = setInterval(readBoardState, 250);
        setTimeout(readBoardState, 200);
    })();
    """#
}
