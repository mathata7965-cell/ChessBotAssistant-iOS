import SwiftUI

struct PiPPreviewCardView: View {
    @ObservedObject var pipManager: PiPOverlayManager
    let isAutoSyncEnabled: Bool
    var isBroadcastActive: Bool = false
    var isScanning: Bool = false
    let onTogglePiP: () -> Void
    let onToggleAutoSync: () -> Void
    var onScanNow: (() -> Void)? = nil
    var onUnavailableBroadcast: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            // Live sample buffer host layer (must stay visible in hierarchy for iOS PiP)
            PiPBufferHostView(displayLayer: pipManager.displayLayer)
                .frame(width: 72, height: 48)
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

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(pipManager.isPiPActive ? "懸浮窗運作中" : "懸浮窗與實時同步")
                        .font(.caption.bold())
                        .foregroundColor(.white)

                    if pipManager.isPiPActive || isAutoSyncEnabled || isBroadcastActive {
                        Circle()
                            .fill(Color(red: 0.35, green: 0.88, blue: 0.42))
                            .frame(width: 6, height: 6)
                    }

                    Spacer()

                    Text("⏯掃描 ⏩走步 ⏪悔步")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(white: 0.62))
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Button {
                        onTogglePiP()
                    } label: {
                        Label(
                            pipManager.isPiPActive ? "關閉懸浮" : "啟動懸浮",
                            systemImage: pipManager.isPiPActive ? "pip.exit" : "pip.enter"
                        )
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            pipManager.isPiPActive
                                ? Color.red.opacity(0.24)
                                : Color(red: 0.50, green: 0.72, blue: 0.30)
                        )
                        .foregroundColor(pipManager.isPiPActive ? .red : Color(red: 0.06, green: 0.10, blue: 0.05))
                        .clipShape(Capsule())
                    }

                    if let onScanNow {
                        Button {
                            onScanNow()
                        } label: {
                            HStack(spacing: 3) {
                                if isScanning {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                } else {
                                    Text("⚡")
                                }
                                Text("讀截圖")
                            }
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.cyan.opacity(0.18))
                            .foregroundColor(.cyan)
                            .clipShape(Capsule())
                        }
                    }

                    Button {
                        onToggleAutoSync()
                    } label: {
                        Text(isAutoSyncEnabled ? "自動:開" : "自動:關")
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                isAutoSyncEnabled
                                    ? Color.cyan.opacity(0.18)
                                    : Color.white.opacity(0.10)
                            )
                            .foregroundColor(isAutoSyncEnabled ? .cyan : Color(white: 0.78))
                            .clipShape(Capsule())
                    }

                    SystemBroadcastPickerButton(
                        isActive: isBroadcastActive,
                        compact: true,
                        onUnavailableExtension: onUnavailableBroadcast
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(9)
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
