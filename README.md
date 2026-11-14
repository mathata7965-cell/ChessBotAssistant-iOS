# Chess Bot 輔助大師 (iOS IPA)

專為在官方 **Chess.com iOS App** 進行機器人 (Bot) 對戰設計的雙開輔助面板 App，支援 **子母畫面 (PiP 懸浮窗)**、**截圖自動辨識棋盤**、**即時局勢評估條 (Eval Bar)** 與 **Multi-PV 最佳走法箭頭分析**。

> 注意：僅建議用於官方離線/機器人練習與賽後覆盤學習，請遵守 Chess.com 的 Fair Play 規範，切勿用於真人積分對戰。

## 核心功能

1. **子母畫面懸浮窗 (PiP)**
   - 使用 iOS 原生 `AVPictureInPictureController` 將迷你分析棋盤、最佳走法箭頭與前 3 名推薦步數懸浮於官方 Chess.com App 上方。
2. **截圖自動同步棋盤**
   - 開啟「截圖同步」後切換到 Chess.com App，只要按下手機截圖（側邊鍵+音量鍵），本 App 會在背景自動偵測最新截圖、定位 8×8 棋盤、OCR 判斷黑白視角並辨識 64 格棋子，自動更新懸浮窗箭頭！
3. **混合引擎分析 (Stockfish 16 NNUE + 離線 PeSTO 引擎)**
   - **即時響應**：內建 Swift PeSTO Tapered Alpha-Beta Multi-PV 離線引擎，無網路也能秒算候選步。
   - **雲端升級**：連線時自動向 Lichess Cloud Eval / Stockfish 16 NNUE 取得深度高達 Depth 15+ 的精準評估與續著。
4. **自訂引擎深度、Multi-PV 與手動擺盤/FEN/PGN**
   - 支援 Depth 4–18 調整、1–3 條候選走法箭頭顯示、自動提示開關，以及一鍵貼上 Chess.com PGN/FEN 局面與手動棋盤編輯器。

## 在 Windows 上免費產出 `.ipa`（無需 Mac）

專案已內建 GitHub Actions 工作流程 (`.github/workflows/build-ipa.yml`) 與自動化腳本 `Build-IPA-Cloud.ps1`：

```powershell
cd C:\Users\matha\.gemini\antigravity\scratch\ChessBotAssistant_iOS
powershell -ExecutionPolicy Bypass -File .\Build-IPA-Cloud.ps1
```

編譯完成後，`ChessBotAssistant.ipa` 會自動下載至專案根目錄，接著使用 **Sideloadly**、**AltStore** 或 **SideStore** 即可安裝到 iPhone / iPad。
