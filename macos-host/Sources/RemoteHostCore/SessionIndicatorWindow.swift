import AppKit
import SwiftUI

public struct SessionIndicatorView: View {
    public let peerName: String
    public let onDisconnect: () -> Void

    @State private var isPulsing = false

    public init(peerName: String, onDisconnect: @escaping () -> Void) {
        self.peerName = peerName
        self.onDisconnect = onDisconnect
    }

    public var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .scaleEffect(isPulsing ? 1.3 : 0.9)
                .opacity(isPulsing ? 1.0 : 0.6)
                .animation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
                .onAppear {
                    isPulsing = true
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Remote Control Active")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                Text("Controlled by \(peerName)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(white: 0.8))
            }

            Button(action: onDisconnect) {
                Text("End")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.15).opacity(0.95))
                .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(0.5), lineWidth: 1)
        )
        .padding(8)
    }
}

public final class SessionIndicatorWindow: @unchecked Sendable {
    public static let shared = SessionIndicatorWindow()

    private var panel: NSPanel?

    public init() {}

    @MainActor
    public func show(peerName: String, onDisconnect: @escaping () -> Void) {
        if panel == nil {
            let newPanel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 60),
                styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                backing: .buffered,
                defer: false
            )
            newPanel.isFloatingPanel = true
            newPanel.level = .floating
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = true
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newPanel.isMovableByWindowBackground = true
            self.panel = newPanel
        }

        guard let panel = panel else { return }

        let contentView = SessionIndicatorView(peerName: peerName, onDisconnect: onDisconnect)
        panel.contentView = NSHostingView(rootView: contentView)

        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.maxX - 310
            let y = screenRect.maxY - 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
    }

    @MainActor
    public func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}
