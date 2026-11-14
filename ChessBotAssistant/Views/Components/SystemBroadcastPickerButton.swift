import ReplayKit
import SwiftUI
import UIKit

struct SystemBroadcastPickerButton: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(isActive ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                    )

                Text(isActive ? "螢幕實時識別運作中 (點此停止或切換)" : "🔴 啟動螢幕實時識別 (免截圖直連 Chess.com)")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                Image(systemName: "record.circle")
                    .font(.subheadline.bold())
                    .foregroundColor(isActive ? .green : Color(red: 1.0, green: 0.42, blue: 0.42))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isActive
                            ? Color.green.opacity(0.22)
                            : Color(red: 0.55, green: 0.14, blue: 0.16).opacity(0.55)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isActive ? Color.green.opacity(0.65) : Color.red.opacity(0.55), lineWidth: 1)
            )

            BroadcastPickerHitOverlay()
                .opacity(0.02)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BroadcastPickerHitOverlay: UIViewRepresentable {
    func makeUIView(context: Context) -> BroadcastHitContainerView {
        BroadcastHitContainerView()
    }

    func updateUIView(_ uiView: BroadcastHitContainerView, context: Context) {
        uiView.setNeedsLayout()
    }
}

private final class BroadcastHitContainerView: UIView {
    private let picker = RPSystemBroadcastPickerView(frame: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)
        picker.preferredExtension = "com.example.ChessBotAssistant.BroadcastExtension"
        picker.showsMicrophoneButton = false
        addSubview(picker)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        picker.frame = bounds
        for subview in picker.subviews {
            subview.frame = picker.bounds
            if let button = subview as? UIButton {
                button.setImage(nil, for: .normal)
                button.setTitle(nil, for: .normal)
            }
        }
    }
}
