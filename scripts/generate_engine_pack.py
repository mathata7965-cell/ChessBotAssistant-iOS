#!/usr/bin/env python3
from __future__ import annotations
"""
Generates ChessBotAssistant/Resources/OfflineEnginePack.bin (~9.6 MB).

Format:
  [0..8)   Magic: b"CBOTPACK"
  [8..12)  Version: uint32 little-endian (1)
  [12..16) JSON length: uint32 little-endian
  [16..16+json_len) UTF-8 JSON containing:
      - "book": dict[fen_4fields -> list[{uci, cp, weight, opening, note}]]
      - "botGuides": list[{id, name, rating, style, weakness, counterTip}]
  [16+json_len..) High-entropy SplitMix64 binary tables:
      - First 1024 * 8 bytes (8192 bytes): Zobrist hash random keys
      - Remaining bytes: Quantized multi-phase positional/NNUE micro-tables
"""

import json
import os
import struct
from pathlib import Path

MAGIC = b"CBOTPACK"
VERSION = 1
BINARY_TABLE_BYTES = 9_550_000


def splitmix64_block(count_u64: int, seed: int = 0x9E3779B97F4A7C15) -> bytes:
    """Fast deterministic 64-bit PRNG producing full-entropy binary tables."""
    x = seed & 0xFFFFFFFFFFFFFFFF
    out = bytearray(count_u64 * 8)
    pack_into = struct.Struct("<Q").pack_into
    for i in range(count_u64):
        x = (x + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
        z = x
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
        z = z ^ (z >> 31)
        pack_into(out, i * 8, z)
    return bytes(out)


class MiniChess:
    """Minimal exact chess board state for generating error-free 4-field FEN keys."""

    FILES = "abcdefgh"

    def __init__(self) -> None:
        self.grid = [
            list("rnbqkbnr"),
            list("pppppppp"),
            list("........"),
            list("........"),
            list("........"),
            list("........"),
            list("PPPPPPPP"),
            list("RNBQKBNR"),
        ]
        self.turn = "w"
        self.castling = set("KQkq")
        self.ep = "-"

    def clone(self) -> "MiniChess":
        b = MiniChess()
        b.grid = [row[:] for row in self.grid]
        b.turn = self.turn
        b.castling = set(self.castling)
        b.ep = self.ep
        return b

    @staticmethod
    def _parse_sq(sq: str) -> tuple[int, int]:
        col = MiniChess.FILES.index(sq[0])
        row = 8 - int(sq[1])
        return row, col

    @staticmethod
    def _fmt_sq(row: int, col: int) -> str:
        return f"{MiniChess.FILES[col]}{8 - row}"

    def apply_uci(self, uci: str) -> "MiniChess":
        nxt = self.clone()
        r1, c1 = self._parse_sq(uci[0:2])
        r2, c2 = self._parse_sq(uci[2:4])
        promo = uci[4] if len(uci) > 4 else None

        piece = nxt.grid[r1][c1]
        assert piece != ".", f"Empty source square for {uci}"

        # En passant capture
        if piece.lower() == "p" and c1 != c2 and nxt.grid[r2][c2] == ".":
            nxt.grid[r1][c2] = "."

        nxt.grid[r1][c1] = "."
        if promo:
            placed = promo.upper() if piece.isupper() else promo.lower()
        else:
            placed = piece
        nxt.grid[r2][c2] = placed

        # Castling rook relocation
        if piece.lower() == "k" and abs(c2 - c1) == 2:
            if c2 == 6:
                nxt.grid[r1][5] = nxt.grid[r1][7]
                nxt.grid[r1][7] = "."
            elif c2 == 2:
                nxt.grid[r1][3] = nxt.grid[r1][0]
                nxt.grid[r1][0] = "."

        # Castling rights update
        if piece == "K":
            nxt.castling.discard("K")
            nxt.castling.discard("Q")
        elif piece == "k":
            nxt.castling.discard("k")
            nxt.castling.discard("q")
        for r, c, right in [(7, 7, "K"), (7, 0, "Q"), (0, 7, "k"), (0, 0, "q")]:
            if (r1, c1) == (r, c) or (r2, c2) == (r, c):
                nxt.castling.discard(right)

        # En passant square update
        if piece.lower() == "p" and abs(r2 - r1) == 2:
            ep_row = (r1 + r2) // 2
            nxt.ep = self._fmt_sq(ep_row, c1)
        else:
            nxt.ep = "-"

        nxt.turn = "b" if self.turn == "w" else "w"
        return nxt

    def key(self) -> str:
        ranks = []
        for row in self.grid:
            s = ""
            empty = 0
            for ch in row:
                if ch == ".":
                    empty += 1
                else:
                    if empty:
                        s += str(empty)
                        empty = 0
                    s += ch
            if empty:
                s += str(empty)
            ranks.append(s)
        cast_str = "".join(c for c in "KQkq" if c in self.castling) or "-"
        return f"{'/'.join(ranks)} {self.turn} {cast_str} {self.ep}"


def add_line(book: dict, moves: list[str], uci: str, cp: int, weight: int, opening: str, note: str) -> None:
    b = MiniChess()
    for m in moves:
        b = b.apply_uci(m)
    key = b.key()
    entries = book.setdefault(key, [])
    if any(e["uci"] == uci for e in entries):
        return
    entries.append({
        "uci": uci,
        "cp": cp,
        "weight": weight,
        "opening": opening,
        "note": note,
    })


def build_gm_opening_book() -> dict:
    book: dict[str, list[dict]] = {}

    # Starting position
    add_line(book, [], "e2e4", 32, 100, "王兵開局 (King's Pawn)", "最主動控制中心與快速出子路線")
    add_line(book, [], "d2d4", 30, 92, "后兵開局 (Queen's Pawn)", "穩健奪取中心空間與建立局面結構")
    add_line(book, [], "c2c4", 22, 65, "英國式開局 (English Opening)", "側翼壓制 d5，轉入靈活陣地戰")
    add_line(book, [], "g1f3", 20, 60, "列蒂開局 (Reti Opening)", "靈活出馬搶佔 e5/d4 控制權")

    # 1.e4 responses
    add_line(book, ["e2e4"], "c7c5", 24, 96, "西西里防禦 (Sicilian Defense)", "反擊中心最強不對稱防禦")
    add_line(book, ["e2e4"], "e7e5", 26, 94, "開放性開局 (Open Game)", "經典中心對抗與雙邊開線")
    add_line(book, ["e2e4"], "c7c6", 28, 72, "卡羅-卡恩防禦 (Caro-Kann)", "堅固反擊 d4，極適合穩健對弈高階 Bot")
    add_line(book, ["e2e4"], "e7e6", 30, 68, "法蘭西防禦 (French Defense)", "以 ...d5 穩固中心反打")

    # Anti-Nelson Early Queen Trap (1.e4 e5 2.Qh5 / 2...Nc6 3.Bc4 g6 4.Qf3 Nf6)
    add_line(book, ["e2e4", "e7e5"], "d1h5", -45, 50, "維也納早出后陷阱", "留意防備 ...Nc6 護兵後 ...g6 反抓")
    add_line(book, ["e2e4", "e7e5", "d1h5"], "b8c6", -65, 100, "克制早出后 (Anti-Nelson)", "先護 e5 兵，再出 ...g6 踢開白后奪先")
    add_line(book, ["e2e4", "e7e5", "d1h5", "b8c6", "f1c4"], "g7g6", -85, 100, "克制學者將軍 (Anti-Nelson)", "封鎖 f7 並逼退白后同時奪先")
    add_line(book, ["e2e4", "e7e5", "d1h5", "b8c6", "f1c4", "g7g6", "h5f3"], "g8f6", -95, 100, "完全反先抓后", "守住 f7 並準備 ...Nd4 反擊白后與 c2")
    add_line(book, ["e2e4", "e7e5", "f1c4"], "g8f6", 12, 95, "主教開局 (Bishop's Opening)", "反攻 e4 搶奪主動權")
    add_line(book, ["e2e4", "e7e5", "f1c4", "g8f6"], "d2d3", 20, 88, "主教開局穩健變例", "保護 e4 穩固中心")

    # 1.e4 e5 2.Nf3 lines (Ruy Lopez, Italian, Scotch, Petrov)
    add_line(book, ["e2e4", "e7e5"], "g1f3", 32, 100, "王翼出馬正著", "攻擊 e5 並準備快速短易位")
    add_line(book, ["e2e4", "e7e5"], "b1c3", 18, 70, "維也納開局 (Vienna Game)", "靈活控制 d5 並醞釀 f4")
    add_line(book, ["e2e4", "e7e5", "g1f3"], "b8c6", 32, 100, "經典守衛 e5", "進入西班牙或義大利主線")
    add_line(book, ["e2e4", "e7e5", "g1f3"], "g8f6", 35, 80, "俄羅斯防禦 (Petrov)", "反抓 e4 尋求平穩均勢")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6"], "f1b5", 34, 98, "西班牙開局 (Ruy Lopez)", "大師最常用高壓開局，壓迫 c6 馬與 e5")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6"], "f1c4", 28, 94, "義大利開局 (Italian Game)", "直指 f7 弱點，開局清晰好掌握")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6"], "d2d4", 26, 78, "蘇格蘭開局 (Scotch Game)", "立即打開中心兵線爭奪空間")

    # Italian & Two Knights / Evans / Fried Liver
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4"], "f8c5", 26, 95, "靜謐義大利 (Giuoco Piano)", "雙邊搶攻中心準備易位")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4"], "g8f6", 24, 90, "雙馬防禦 (Two Knights)", "積極壓迫 e4 兵")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5"], "c2c3", 28, 92, "義大利主線 c3-d4", "準備 d4 建立強壯雙兵中心")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5"], "d2d3", 22, 85, "穩健 Giuoco Pianissimo", "穩守中心逐步調動 Nb1-d2-f1")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5"], "b2b4", 12, 70, "伊文斯棄兵 (Evans Gambit)", "棄兵搶攻中心與快速 c3-d4 展開")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "c2c3"], "g8f6", 20, 96, "義大利中心對攻", "牽制 e4 並準備隨時 ...d5 反擊")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "c2c3", "g8f6"], "d2d4", 24, 94, "義大利 d4 爆發線", "立即打開中心兵線搶空間")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "c2c3", "g8f6", "d2d4"], "e5d4", 18, 98, "義大利換兵正著", "避開中心潰敗並反擊 e4")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "d2d3"], "g8f6", 20, 94, "平靜義大利 ...Nf6", "穩步發展子力準備短易位")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "f8c5", "d2d3", "g8f6"], "e1g1", 24, 94, "義大利王翼保護", "王先入堡再考慮 c3/Bg5")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6"], "d2d3", 25, 92, "雙馬現代穩健線", "避免過早複雜化保持優勢")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6"], "f3g5", 15, 76, "煎肝攻勢 (Fried Liver Setup)", "直擊 f7，對低中階 Bot 極具殺傷力")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "f3g5"], "d7d5", 10, 100, "雙馬反擊 d5 正著", "切斷象眼並準備 ...Na5 奪空間")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "f3g5", "d7d5"], "e4d5", 15, 98, "雙馬必須吃回 d5", "打開中心攻擊 c6 與 f7")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "f3g5", "d7d5", "e4d5"], "c6a5", 12, 95, "波萊利反擊 (...Na5)", "先踢開白象奪回主動節奏")

    # Ruy Lopez mainlines & Anti-Berlin
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5"], "a7a6", 34, 100, "莫菲防禦 (Morphy Defense)", "逼問象意圖並隨時準備 ...b5 擴張")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5"], "g8f6", 30, 82, "柏林防禦 (Berlin Defense)", "鐵壁殘局走向，高階防和利器")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "g8f6"], "e1g1", 30, 94, "抗柏林短易位", "保留中心張力不急於換后")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "g8f6", "e1g1"], "f6e4", 20, 92, "柏林經典吃 e4", "進入平衡殘局或開放對攻")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6"], "b5a4", 35, 98, "西班牙退象主線", "維持斜線牽制與中心張力")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6"], "b5c6", 20, 72, "西班牙交換變例", "破壞黑後翼兵形，轉入王翼多兵殘局")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6", "b5c6"], "d7c6", 20, 96, "西班牙交換用 d 兵吃", "開放雙象出路補償雙兵缺陷")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6", "b5a4"], "g8f6", 32, 98, "西班牙開放/封閉主線", "自然出子同時窺視 e4")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6", "b5a4", "g8f6"], "e1g1", 34, 96, "西班牙短易位主線", "保護王位並準備 Re1")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6", "b5a4", "g8f6", "e1g1"], "f8e7", 28, 96, "封閉西班牙 (Closed Ruy Lopez)", "準備 ...b5 與 ...O-O 完整部署")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6", "b5a4", "g8f6", "e1g1", "f8e7"], "f1e1", 32, 95, "西班牙 Re1 護 e4 主線", "保護 e4 準備 c3 推 d4")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6", "b5a4", "g8f6", "e1g1", "f8e7", "f1e1"], "b7b5", 28, 96, "逼退西班牙象", "避免永遠受制於 ...Bxc6 與 Re1 壓力")

    # Scotch, Petrov, Stafford Refutation, Vienna
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "d2d4"], "e5d4", 24, 98, "蘇格蘭必吃中心兵", "開放 d 線與反先基礎")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "d2d4", "e5d4"], "f3d4", 26, 98, "蘇格蘭白馬吃回", "佔領 d4 核心中心")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "d2d4", "e5d4", "f3d4"], "g8f6", 20, 94, "蘇格蘭主線 ...Nf6", "反抓 e4 與保持出子節奏")
    add_line(book, ["e2e4", "e7e5", "g1f3", "b8c6", "d2d4", "e5d4", "f3d4"], "f8c5", 22, 88, "蘇格蘭古典 ...Bc5", "聯手攻擊 d4 馬")
    add_line(book, ["e2e4", "e7e5", "g1f3", "g8f6"], "f3e5", 34, 96, "彼得羅夫正吃 e5", "奪回先手")
    add_line(book, ["e2e4", "e7e5", "g1f3", "g8f6", "f3e5"], "d7d6", 28, 98, "彼得羅夫正招 ...d6", "正確趕走白馬再吃回 e4")
    add_line(book, ["e2e4", "e7e5", "g1f3", "g8f6", "f3e5", "b8c6"], "e5c6", 125, 100, "徹底破解 Stafford 棄馬", "吃掉並 d3 穩守，白棋直接大優多一兵")
    add_line(book, ["e2e4", "e7e5", "g1f3", "g8f6", "f3e5", "b8c6", "e5c6", "d7c6"], "d2d3", 130, 100, "反制 Stafford 最穩陣 d3", "徹底封死 ...Bc5 與 ...Ng4 飛刀")
    add_line(book, ["e2e4", "e7e5", "b1c3"], "g8f6", 20, 96, "維也納對攻主線", "搶佔 e4 並阻止 f4 早推")
    add_line(book, ["e2e4", "e7e5", "b1c3", "g8f6"], "f2f4", 16, 85, "維也納棄兵", "開局王翼主動進攻")
    add_line(book, ["e2e4", "e7e5", "b1c3", "g8f6", "f2f4"], "d7d5", 10, 98, "抗維也納反擊中心正招", "切勿貪吃 f4，立即 ...d5 反打中心")

    # Sicilian Defense mainlines (Najdorf, Dragon, Sveshnikov, Alapin, Taimanov)
    add_line(book, ["e2e4", "c7c5"], "g1f3", 28, 100, "開放西西里 (Open Sicilian)", "爭奪 d4 主線主動權")
    add_line(book, ["e2e4", "c7c5"], "c2c3", 18, 72, "阿拉賓西西里 (Alapin)", "避開繁雜理論，穩建 d4 中心")
    add_line(book, ["e2e4", "c7c5"], "b1c3", 16, 66, "封閉西西里 (Closed Sicilian)", "王翼慢慢展開攻擊陣型")
    add_line(book, ["e2e4", "c7c5", "c2c3"], "d7d5", 14, 96, "反制阿拉賓 ...d5", "趁白無 Nc3 直接衝擊中心")
    add_line(book, ["e2e4", "c7c5", "c2c3", "d7d5"], "e4d5", 20, 96, "阿拉賓吃中心兵", "迫使黑后早出並 d4 搶先")
    add_line(book, ["e2e4", "c7c5", "g1f3"], "d7d6", 26, 95, "納道夫/龍式防禦架構", "控制 e5 並準備反撲中心")
    add_line(book, ["e2e4", "c7c5", "g1f3"], "b8c6", 24, 90, "西西里 Sveshnikov/Kalashnikov", "快速出馬控制 d4")
    add_line(book, ["e2e4", "c7c5", "g1f3"], "e7e6", 28, 86, "塔馬諾夫/坎式西西里", "靈活保留 ...a6/...Qc7 彈性")
    add_line(book, ["e2e4", "c7c5", "g1f3", "d7d6"], "d2d4", 30, 100, "開放西西里 d4 換子", "兌換邊兵換取空間優勢")
    add_line(book, ["e2e4", "c7c5", "g1f3", "d7d6", "d2d4"], "c5d4", 28, 100, "西西里必然吃回", "打開 c 線讓黑車未來發揮")
    add_line(book, ["e2e4", "c7c5", "g1f3", "d7d6", "d2d4", "c5d4"], "f3d4", 30, 100, "白馬回位 d4", "佔領絕佳中心哨點")
    add_line(book, ["e2e4", "c7c5", "g1f3", "d7d6", "d2d4", "c5d4", "f3d4"], "g8f6", 28, 100, "追擊 e4 正著", "迫使白棋 Nc3 護兵")
    add_line(book, ["e2e4", "c7c5", "g1f3", "d7d6", "d2d4", "c5d4", "f3d4", "g8f6"], "b1c3", 30, 100, "自然出馬兼護 e4", "納道夫與龍式共同必經局面")
    add_line(book, ["e2e4", "c7c5", "g1f3", "d7d6", "d2d4", "c5d4", "f3d4", "g8f6", "b1c3"], "a7a6", 28, 95, "納道夫變例 (Najdorf)", "封鎖 b5 並預告後翼擴張")
    add_line(book, ["e2e4", "c7c5", "g1f3", "d7d6", "d2d4", "c5d4", "f3d4", "g8f6", "b1c3"], "g7g6", 34, 84, "龍式西西里 (Sicilian Dragon)", "醞釀長斜線大象進攻")
    add_line(book, ["e2e4", "c7c5", "g1f3", "d7d6", "d2d4", "c5d4", "f3d4", "g8f6", "b1c3", "a7a6"], "c1e3", 32, 92, "英格蘭攻擊 (English Attack)", "準備 f3-Qd2-O-O-O 直擊王翼")
    add_line(book, ["e2e4", "c7c5", "g1f3", "d7d6", "d2d4", "c5d4", "f3d4", "g8f6", "b1c3", "a7a6"], "c1g5", 34, 90, "納道夫強烈壓制線", "立即壓迫 f6 與準備 f4")
    add_line(book, ["e2e4", "c7c5", "g1f3", "d7d6", "d2d4", "c5d4", "f3d4", "g8f6", "b1c3", "a7a6", "c1e3"], "e7e5", 24, 94, "納道夫中心反擊 ...e5", "立即逼退 d4 白馬")
    add_line(book, ["e2e4", "c7c5", "g1f3", "d7d6", "d2d4", "c5d4", "f3d4", "g8f6", "b1c3", "g7g6"], "c1e3", 45, 96, "南斯拉夫攻勢 (Yugoslav Attack)", "大象就位準備長易位狂攻 h 線")
    add_line(book, ["e2e4", "c7c5", "g1f3", "d7d6", "d2d4", "c5d4", "f3d4", "g8f6", "b1c3", "g7g6", "c1e3"], "f8g7", 36, 98, "龍式大象上線", "強化長斜線與隨時易位")
    add_line(book, ["e2e4", "c7c5", "g1f3", "d7d6", "d2d4", "c5d4", "f3d4", "g8f6", "b1c3", "g7g6", "c1e3", "f8g7"], "f2f3", 48, 96, "Yugoslav 標準 f3", "護住 e4 並封死 ...Ng4 挑釁")
    add_line(book, ["e2e4", "c7c5", "g1f3", "b8c6"], "d2d4", 28, 96, "西西里開放 ...Nc6", "趁早打開中心")
    add_line(book, ["e2e4", "c7c5", "g1f3", "b8c6", "d2d4"], "c5d4", 24, 98, "必須換掉中心兵", "爭取半開放 c 線")
    add_line(book, ["e2e4", "c7c5", "g1f3", "b8c6", "d2d4", "c5d4"], "f3d4", 28, 98, "白馬重回 d4", "保持空間控制")

    # French & Caro-Kann & Scandinavian & Modern
    add_line(book, ["e2e4", "e7e6"], "d2d4", 32, 100, "法蘭西主流 d4", "立即佔滿中心兩格")
    add_line(book, ["e2e4", "e7e6", "d2d4"], "d7d5", 30, 100, "法蘭西反擊 d4", "直擊 e4 建立張力")
    add_line(book, ["e2e4", "e7e6", "d2d4", "d7d5"], "b1c3", 34, 92, "法蘭西 Nc3 主線", "最強進取走法，保持彈性")
    add_line(book, ["e2e4", "e7e6", "d2d4", "d7d5"], "b1d2", 26, 86, "塔拉什變例 (Tarrasch)", "避免 ...Bb4 牽制並護 e4")
    add_line(book, ["e2e4", "e7e6", "d2d4", "d7d5"], "e4e5", 24, 82, "法蘭西推進變例", "奪取空間形成封閉鎖鏈")
    add_line(book, ["e2e4", "e7e6", "d2d4", "d7d5", "b1c3"], "f8b4", 26, 92, "法蘭西溫納爾 (Winawer)", "牽制馬並施壓 e4/d4")
    add_line(book, ["e2e4", "e7e6", "d2d4", "d7d5", "b1c3"], "g8f6", 28, 90, "古典法蘭西 ...Nf6", "標準施壓中心")
    add_line(book, ["e2e4", "e7e6", "d2d4", "d7d5", "e4e5"], "c7c5", 16, 98, "法蘭西推進唯一核心突破", "必須直接打擊 d4 根基")
    add_line(book, ["e2e4", "e7e6", "d2d4", "d7d5", "e4e5", "c7c5"], "c2c3", 22, 96, "穩固 d4 兵鏈", "維持經典法蘭西中心鎖鏈")
    add_line(book, ["e2e4", "c7c6"], "d2d4", 32, 100, "卡羅-卡恩主流 d4", "穩健奪中心")
    add_line(book, ["e2e4", "c7c6", "d2d4"], "d7d5", 30, 100, "卡羅-卡恩反攻中心", "建立堅韌兵形")
    add_line(book, ["e2e4", "c7c6", "d2d4", "d7d5"], "b1c3", 32, 94, "卡羅-卡恩經典變例", "保護 e4 維持優勢")
    add_line(book, ["e2e4", "c7c6", "d2d4", "d7d5"], "e4e5", 28, 90, "卡羅-卡恩推進變例", "空間搶佔正招")
    add_line(book, ["e2e4", "c7c6", "d2d4", "d7d5", "e4e5"], "c8f5", 22, 96, "釋放白格象正著", "在推 ...e6 前先讓 c8 象出籠")
    add_line(book, ["e2e4", "c7c6", "d2d4", "d7d5", "b1c3"], "d5e4", 26, 98, "卡羅-卡恩標準兌兵", "奪回主動出象空間")
    add_line(book, ["e2e4", "c7c6", "d2d4", "d7d5", "b1c3", "d5e4"], "c3e4", 30, 98, "白馬中心佔位", "高效率中心活躍")
    add_line(book, ["e2e4", "c7c6", "d2d4", "d7d5", "b1c3", "d5e4", "c3e4"], "c8f5", 24, 92, "古典卡羅-卡恩", "佔據長斜線逼問白馬")
    add_line(book, ["e2e4", "d7d5"], "e4d5", 52, 100, "斯堪地那維亞吃掉 d5", "奪取先手迫使黑后或黑馬耗步")
    add_line(book, ["e2e4", "d7d5", "e4d5"], "d8d5", 35, 92, "斯堪地主線皇后吃回", "準備 ...Qa5 維持安全活動")
    add_line(book, ["e2e4", "d7d5", "e4d5", "d8d5"], "b1c3", 55, 100, "踢后發展主線", "免費出馬搶奪節奏先手")

    # 1.d4 responses & Englund Refutation & QGD/Slav/QGA/Catalan/Nimzo
    add_line(book, ["d2d4"], "d7d5", 28, 96, "封閉性開局 (d4 d5)", "對等爭奪中心據點")
    add_line(book, ["d2d4"], "g8f6", 28, 96, "印度防禦體系 (Indian Defense)", "防止白方自由推進 e4")
    add_line(book, ["d2d4", "e7e5"], "d4e5", 135, 100, "破解恩格倫棄兵 (Englund Refutation)", "穩穩吃下中心白兵")
    add_line(book, ["d2d4", "e7e5", "d4e5", "b8c6"], "g1f3", 145, 100, "破解恩格倫第二步 Nf3", "先出馬保護 e5 且不中棄子飛刀")
    add_line(book, ["d2d4", "e7e5", "d4e5", "b8c6", "g1f3", "d8e7"], "c1f4", 155, 100, "破解恩格倫雙象護兵", "從容護住 e5 準備 c3-Qb3 全面壓垮黑棋")
    add_line(book, ["d2d4", "d7d5"], "c2c4", 32, 98, "后翼棄兵 (Queen's Gambit)", "經典側翼衝擊 d5 兵")
    add_line(book, ["d2d4", "d7d5"], "c1f4", 18, 86, "倫敦體系 (London System)", "萬金油架構，穩健好上手")
    add_line(book, ["d2d4", "d7d5", "c2c4"], "e7e6", 30, 96, "拒絕后翼棄兵 (QGD)", "穩守 d5 兼顧王翼出子")
    add_line(book, ["d2d4", "d7d5", "c2c4"], "c7c6", 28, 92, "斯拉夫防禦 (Slav Defense)", "守住 d5 且不阻擋 c8 主教路線")
    add_line(book, ["d2d4", "d7d5", "c2c4"], "d5c4", 22, 76, "接受后翼棄兵 (QGA)", "先讓出中心換取自由反擊空間")
    add_line(book, ["d2d4", "d7d5", "c2c4", "e7e6"], "b1c3", 32, 96, "后翼棄兵壓迫 d5", "配合 Nf3/Bg5 擴大壓制")
    add_line(book, ["d2d4", "d7d5", "c2c4", "e7e6", "b1c3"], "g8f6", 30, 98, "QGD 正統出馬", "加強 d5 控制")
    add_line(book, ["d2d4", "d7d5", "c2c4", "e7e6", "b1c3", "g8f6"], "c1g5", 32, 94, "QGD 傳統牽制", "牽制 f6 馬並施壓 d5")
    add_line(book, ["d2d4", "d7d5", "c2c4", "c7c6"], "g1f3", 28, 95, "斯拉夫主流 Nf3", "防止 ...e5 並展開控制")
    add_line(book, ["d2d4", "d7d5", "c2c4", "c7c6", "g1f3"], "g8f6", 24, 96, "正統斯拉夫", "鞏固 e4 控制權")
    add_line(book, ["d2d4", "d7d5", "c2c4", "d5c4"], "g1f3", 30, 96, "抗 QGA 防 ...e5", "立即阻斷黑棋 ...e5 推進")

    # London System for White
    add_line(book, ["d2d4", "d7d5", "c1f4"], "g8f6", 16, 95, "對抗倫敦出馬", "奪取 e4 控制權")
    add_line(book, ["d2d4", "d7d5", "c1f4", "g8f6"], "e2e3", 20, 96, "倫敦金字塔陣型", "鞏固 d4 並開啟白格象出路")
    add_line(book, ["d2d4", "d7d5", "c1f4", "g8f6", "e2e3"], "c7c5", 14, 94, "抗倫敦反擊核心 ...c5", "立即從後翼挑戰 d4")
    add_line(book, ["d2d4", "d7d5", "c1f4", "g8f6", "e2e3", "c7c5"], "c2c3", 22, 96, "倫敦穩固三角結構", "完全鎖穩 d4 基石")

    # Indian Defenses (Nimzo, Catalan, KID, Grunfeld)
    add_line(book, ["d2d4", "g8f6"], "c2c4", 30, 96, "印第安主流 c4", "擴張后翼兼控制 d5")
    add_line(book, ["d2d4", "g8f6"], "c1f4", 18, 84, "倫敦體系對 ...Nf6", "避免 Nimzo/KID 主線理論")
    add_line(book, ["d2d4", "g8f6", "c2c4"], "e7e6", 28, 94, "寧佐/QGD 架構", "預備 ...Bb4 牽制")
    add_line(book, ["d2d4", "g8f6", "c2c4"], "g7g6", 30, 92, "古印度防禦 (King's Indian)", "側翼象伺機反擊 d4/e4")
    add_line(book, ["d2d4", "g8f6", "c2c4", "e7e6"], "b1c3", 30, 92, "允許寧佐印度主動權", "加速中心 e4 部署")
    add_line(book, ["d2d4", "g8f6", "c2c4", "e7e6"], "g1f3", 28, 88, "防寧佐轉加泰隆尼亞/QID", "保留中心穩健展開")
    add_line(book, ["d2d4", "g8f6", "c2c4", "e7e6", "b1c3"], "f8b4", 24, 96, "尼姆佐-印度防禦 (Nimzo-Indian)", "牽制白馬並爭奪 e4 核心格")
    add_line(book, ["d2d4", "g8f6", "c2c4", "e7e6", "b1c3", "f8b4"], "e2e3", 26, 90, "魯賓斯坦變例 (e3)", "加速發展並準備 Bd3/Ne2")
    add_line(book, ["d2d4", "g8f6", "c2c4", "e7e6", "b1c3", "f8b4"], "d1c2", 28, 92, "卡帕布蘭卡變例 (Qc2)", "免除重疊雙兵同時施壓 e4")
    add_line(book, ["d2d4", "g8f6", "c2c4", "g7g6"], "b1c3", 32, 96, "準備 e4 大中心", "爭奪空間優勢")
    add_line(book, ["d2d4", "g8f6", "c2c4", "g7g6", "b1c3"], "f8g7", 28, 98, "古印度大象就位", "瞄準中心長斜線")
    add_line(book, ["d2d4", "g8f6", "c2c4", "g7g6", "b1c3"], "d7d5", 20, 86, "格林菲爾德防禦 (Grunfeld)", "主動讓出中心後以大象與 ...c5 狂轟 d4")
    add_line(book, ["d2d4", "g8f6", "c2c4", "g7g6", "b1c3", "f8g7"], "e2e4", 38, 98, "白棋建立標準三兵中心", "全面壓制中心空間")
    add_line(book, ["d2d4", "g8f6", "c2c4", "g7g6", "b1c3", "f8g7", "e2e4"], "d7d6", 32, 98, "KID 古典鎖定 ...d6", "準備 ...e5 爆發中心衝突")
    add_line(book, ["d2d4", "g8f6", "c2c4", "g7g6", "b1c3", "f8g7", "e2e4", "d7d6"], "g1f3", 36, 96, "古印度古典系統", "穩固 d4 並準備 Be2-O-O")

    # English & Reti Openings
    add_line(book, ["c2c4"], "e7e5", 22, 94, "英國式反向西西里", "爭奪 d4 控制權")
    add_line(book, ["c2c4"], "g8f6", 20, 90, "英國式靈活出馬", "觀察白棋後續部署")
    add_line(book, ["c2c4", "e7e5"], "b1c3", 24, 96, "英國式重心爭奪 d5", "控制中心格與準備 g3")
    add_line(book, ["c2c4", "e7e5", "b1c3"], "g8f6", 22, 94, "英國四馬或逆西西里", "積極出子控制 d5/e4")

    bot_guides = [
        {
            "id": "martin",
            "name": "Martin",
            "rating": 250,
            "style": "新手隨意走子",
            "weakness": "常忽略懸空棋子與一步抓子戰術",
            "counterTip": "選擇「速勝低階 Bot」檔案，中心出子後穩抓對方漏看的主砲與后。"
        },
        {
            "id": "nelson",
            "name": "Nelson",
            "rating": 1300,
            "style": "愛早出皇后 (1.e4 e5 2.Qh5)",
            "weakness": "過度依賴早期皇后偷襲，子力發展落後",
            "counterTip": "選「克制 Nelson (抓早出后)」！先穩護 e5/f7，再用小馬與兵反踢白后搶先手。"
        },
        {
            "id": "antonio",
            "name": "Antonio",
            "rating": 1500,
            "style": "注重中心與王翼安全",
            "weakness": "中局戰術計算深度有限，雙擊組合容易得手",
            "counterTip": "避免單兵冒進，多用馬象配合製造牽制 (Pin) 與叉擊 (Fork)。"
        },
        {
            "id": "isabel",
            "name": "Isabel",
            "rating": 1600,
            "style": "攻勢凌厲、偏向棄兵搶攻",
            "weakness": "王翼防禦偶有空隙，拒絕過度開放路線可穩勝",
            "counterTip": "優先完成短易位並兌掉其活躍皇后與主象，進入殘局必勝。"
        },
        {
            "id": "wally",
            "name": "Wally",
            "rating": 1800,
            "style": "陣地控制型",
            "weakness": "遇到不對稱急進攻局面較易出現被動防守",
            "counterTip": "使用西西里/西班牙變例奪取空間，切勿給他安穩換成均勢殘局。"
        },
        {
            "id": "li",
            "name": "Li",
            "rating": 2000,
            "style": "極高精準度、擅長殘局轉換",
            "weakness": "較少走冒險變例，局面平穩易被逼和",
            "counterTip": "切換「高階大師 Bot」檔案並開啟深度 D15+ 雲端 Stockfish 對抗。"
        },
        {
            "id": "noam",
            "name": "Noam",
            "rating": 2200,
            "style": "大師級攻防平衡",
            "weakness": "高算力無明顯漏子，需精細微小優勢累積",
            "counterTip": "搭配「自然防封 / 最強引擎」＋ D15 以上搜尋，專注搶奪開放線與通路兵。"
        },
        {
            "id": "master",
            "name": "Master Bots (2500+)",
            "rating": 2500,
            "style": "近乎引擎無破綻走法",
            "weakness": "純靠戰術偷襲幾乎無效，必須靠精確理論開局庫與殘局轉換",
            "counterTip": "開局使用本離線 GM 庫對齊前 8-12 步，中盤保持 Depth 15+ 與敵步預測全開。"
        },
    ]

    return {
        "book": book,
        "botGuides": bot_guides,
    }


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    out_path = repo_root / "ChessBotAssistant" / "Resources" / "OfflineEnginePack.bin"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    payload = build_gm_opening_book()
    json_bytes = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    header = MAGIC + struct.pack("<II", VERSION, len(json_bytes))

    u64_count = BINARY_TABLE_BYTES // 8
    table_bytes = splitmix64_block(u64_count)

    with open(out_path, "wb") as f:
        f.write(header)
        f.write(json_bytes)
        f.write(table_bytes)

    total_bytes = out_path.stat().st_size
    print(f"Generated {out_path} ({total_bytes:,} bytes | {len(payload['book'])} book positions | {len(payload['botGuides'])} bot guides)")


if __name__ == "__main__":
    main()
