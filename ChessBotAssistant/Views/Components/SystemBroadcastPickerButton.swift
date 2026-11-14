import ReplayKit
import SwiftUI
import UIKit

struct SystemBroadcastPickerButton: View {
    let isActive: Bool
    var compact: Bool = false
    var onUnavailableExtension: (() -> Void)? = nil

    @State private var triggerBroadcastPicker: (() -> Void)?

    static let cachedExtensionBundleID: String? = resolvedBroadcastExtensionBundleID()

    static func resolvedBroadcastExtensionBundleID() -> String? {
        guard let plugInsURL = Bundle.main.builtInPlugInsURL else { return nil }
        let appexURL = plugInsURL.appendingPathComponent("ChessBroadcastExtension.appex")
        if FileManager.default.fileExists(atPath: appexURL.path),
           let bundleID = Bundle(url: appexURL)?.bundleIdentifier {
            return bundleID
        }
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: plugInsURL,
            includingPropertiesForKeys: nil
        ) {
            for itemURL in contents where itemURL.pathExtension == "appex" {
                if let bundleID = Bundle(url: itemURL)?.bundleIdentifier {
                    return bundleID
                }
            }
        }
        return nil
    }

    var body: some View {
        let extensionBundleID = Self.cachedExtensionBundleID

        if compact && extensionBundleID == nil {
            EmptyView()
        } else {
            Button {
                if extensionBundleID != nil {
                    triggerBroadcastPicker?()
                } else {
                    onUnavailableExtension?()
                }
            } label: {
                if compact {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isActive ? Color.green : Color.red)
                            .frame(width: 7, height: 7)
                        Text(isActive ? "直播中" : "直播")
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(isActive ? Color.green.opacity(0.22) : Color.red.opacity(0.20))
                    .foregroundColor(isActive ? .green : Color(red: 1.0, green: 0.45, blue: 0.45))
                    .clipShape(Capsule())
                } else {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(isActive ? Color.green : (extensionBundleID != nil ? Color.red : Color.orange))
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                            )

                        Text(
                            extensionBundleID == nil
                                ? "⚠️ 免外掛版不支援螢幕直播（請改用上方懸浮窗 + 截圖識別）"
                                : (isActive ? "螢幕實時識別運作中 (點此停止或切換)" : "🔴 啟動螢幕實時識別 (免截圖直連 Chess.com)")
                        )
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                        Spacer(minLength: 0)

                        Image(systemName: extensionBundleID == nil ? "exclamationmark.triangle.fill" : "record.circle")
                            .font(.subheadline.bold())
                            .foregroundColor(
                                extensionBundleID == nil
                                    ? .orange
                                    : (isActive ? .green : Color(red: 1.0, green: 0.42, blue: 0.42))
                            )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                extensionBundleID == nil
                                    ? Color.orange.opacity(0.18)
                                    : (isActive
                                        ? Color.green.opacity(0.22)
                                        : Color(red: 0.55, green: 0.14, blue: 0.16).opacity(0.55))
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                extensionBundleID == nil
                                    ? Color.orange.opacity(0.55)
                                    : (isActive ? Color.green.opacity(0.65) : Color.red.opacity(0.55)),
                                lineWidth: 1
                            )
                    )
                }
            }
            .buttonStyle(.plain)
            .background(
                BroadcastPickerTriggerBridge(
                    preferredExtension: extensionBundleID,
                    onReady: { trigger in
                        DispatchQueue.main.async {
                            self.triggerBroadcastPicker = trigger
                        }
                    }
                )
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            )
            .frame(maxWidth: compact ? nil : .infinity)
        }
    }
}

private struct BroadcastPickerTriggerBridge: UIViewRepresentable {
    let preferredExtension: String?
    let onReady: (@escaping () -> Void) -> Void

    func makeUIView(context: Context) -> BroadcastBridgeHostView {
        let view = BroadcastBridgeHostView()
        view.configure(preferredExtension: preferredExtension)
        onReady { [weak view] in
            view?.triggerSystemPicker()
        }
        return view
    }

    func updateUIView(_ uiView: BroadcastBridgeHostView, context: Context) {
        uiView.configure(preferredExtension: preferredExtension)
    }
}

private final class BroadcastBridgeHostView: UIView {
    private let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))

    override init(frame: CGRect) {
        super.init(frame: frame)
        picker.showsMicrophoneButton = false
        picker.alpha = 0.01
        addSubview(picker)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(preferredExtension: String?) {
        picker.preferredExtension = preferredExtension
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        picker.frame = bounds.isEmpty ? CGRect(x: 0, y: 0, width: 1, height: 1) : bounds
    }

    func triggerSystemPicker() {
        guard let button = findButton(in: picker) else { return }
        let hasTouchUpInside = button.allTargets.contains { target in
            !(button.actions(forTarget: target, forControlEvent: .touchUpInside)?.isEmpty ?? true)
        }
        button.sendActions(for: hasTouchUpInside ? .touchUpInside : .allTouchEvents)
    }

    private func findButton(in root: UIView) -> UIButton? {
        for subview in root.subviews {
            if let button = subview as? UIButton {
                return button
            }
            if let nested = findButton(in: subview) {
                return nested
            }
        }
        return nil
    }
}
