import SwiftUI
import RemoteControllerCore

public struct ControlBarView: View {
    @Binding public var isKeyboardActive: Bool
    public let onSendShortcut: (MacShortcut) -> Void
    public let onDisconnect: () -> Void

    public init(
        isKeyboardActive: Binding<Bool>,
        onSendShortcut: @escaping (MacShortcut) -> Void,
        onDisconnect: @escaping () -> Void
    ) {
        self._isKeyboardActive = isKeyboardActive
        self.onSendShortcut = onSendShortcut
        self.onDisconnect = onDisconnect
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Keyboard toggle button
                Button(action: {
                    isKeyboardActive.toggle()
                }) {
                    Image(systemName: isKeyboardActive ? "keyboard.chevron.compact.down" : "keyboard")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isKeyboardActive ? .accentColor : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(isKeyboardActive ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                        .cornerRadius(8)
                }

                // Standard Shortcuts
                Group {
                    shortcutButton(.escape)
                    shortcutButton(.tab)
                    shortcutButton(.cmdTab)
                    shortcutButton(.cmdC)
                    shortcutButton(.cmdV)
                    shortcutButton(.cmdZ)
                    shortcutButton(.cmdSpace)
                    shortcutButton(.upArrow)
                    shortcutButton(.downArrow)
                    shortcutButton(.leftArrow)
                    shortcutButton(.rightArrow)
                }

                Divider()
                    .frame(height: 20)
                    .background(Color.white.opacity(0.3))

                // Disconnect button
                Button(action: onDisconnect) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                        Text("Disconnect")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.1).opacity(0.92))
                .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 12)
    }

    private func shortcutButton(_ shortcut: MacShortcut) -> some View {
        Button(action: {
            onSendShortcut(shortcut)
        }) {
            Text(shortcut.label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
        }
    }
}
