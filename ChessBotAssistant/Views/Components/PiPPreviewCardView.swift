import SwiftUI

struct PiPPreviewCardView: View {
    @ObservedObject var pipManager: PiPOverlayManager
    let isAutoSyncEnabled: Bool
    let onToggleAutoSync: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Live sample buffer host layer (must stay visible in hierarchy for iOS PiP)
            PiPBufferHostView(displayLayer: pipManager.displayLayer)
                .frame(width: 96, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            pipManager.isPiPActive
                                ? Color(red: 0.35, green: 0.88, blue: 0.42)
                                : Color.white.opacity(0.15),
                            lineWidth: 1.5
                        )
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(pipManager.isPiPActive ? "子母畫面懸浮中" : "子母畫面雙開面板 (PiP)")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)

                    if pipManager.isPiPActive {
                        Circle()
                            .fill(Color(red: 0.35, green: 0.88, blue: 0.42))
                            .frame(width: 7, height: 7)
                    }
                }

                Text("開啟後切到 Chess.com App，在對局畫面「截圖」即自動同步最佳走法")
                    .font(.caption2)
                    .foregroundColor(Color(white: 0.68))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Button {
                        pipManager.togglePiP()
                    } label: {
                        Label(
                            pipManager.isPiPActive ? "關閉懸浮窗" : "啟動懸浮窗",
                            systemImage: pipManager.isPiPActive ? "pip.exit" : "pip.enter"
                        )
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            pipManager.isPiPActive
                                ? Color.red.opacity(0.25)
                                : Color(red: 0.50, green: 0.72, blue: 0.30)
                        )
                        .foregroundColor(pipManager.isPiPActive ? .red : Color(red: 0.06, green: 0.10, blue: 0.05))
                        .clipShape(Capsule())
                    }

                    Button {
                        onToggleAutoSync()
                    } label: {
                        Label(
                            isAutoSyncEnabled ? "截圖同步:開" : "截圖同步:關",
                            systemImage: isAutoSyncEnabled ? "camera.viewfinder" : "camera"
                        )
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            isAutoSyncEnabled
                                ? Color.cyan.opacity(0.20)
                                : Color.white.opacity(0.10)
                        )
                        .foregroundColor(isAutoSyncEnabled ? .cyan : Color(white: 0.80))
                        .clipShape(Capsule())
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.12, green: 0.15, blue: 0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
