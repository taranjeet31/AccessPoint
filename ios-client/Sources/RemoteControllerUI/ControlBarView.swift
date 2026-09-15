import SwiftUI
import RemoteControllerCore

public enum InteractionMode: String, CaseIterable, Identifiable, Sendable {
    case touch = "Touch"
    case pointer = "Pointer"
    case scroll = "Scroll"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .touch: return "hand.tap.fill"
        case .pointer: return "cursorarrow"
        case .scroll: return "arrow.up.and.down.circle"
        }
    }
}

public struct ControlBarView: View {
    @Binding public var isKeyboardActive: Bool
    @Binding public var interactionMode: InteractionMode
    public let onSendShortcut: (MacShortcut) -> Void
    public let onOpenAppPicker: (() -> Void)?
    public let onDisconnect: () -> Void

    public init(
        isKeyboardActive: Binding<Bool>,
        interactionMode: Binding<InteractionMode> = .constant(.touch),
        onSendShortcut: @escaping (MacShortcut) -> Void,
        onOpenAppPicker: (() -> Void)? = nil,
        onDisconnect: @escaping () -> Void
    ) {
        self._isKeyboardActive = isKeyboardActive
        self._interactionMode = interactionMode
        self.onSendShortcut = onSendShortcut
        self.onOpenAppPicker = onOpenAppPicker
        self.onDisconnect = onDisconnect
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Apps picker button
                if let onOpenAppPicker = onOpenAppPicker {
                    Button(action: onOpenAppPicker) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.grid.2x2.fill")
                            Text("Apps")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(8)
                    }
                }

                // Mode Picker
                HStack(spacing: 2) {
                    ForEach(InteractionMode.allCases) { mode in
                        Button(action: { interactionMode = mode }) {
                            HStack(spacing: 3) {
                                Image(systemName: mode.iconName)
                                    .font(.system(size: 10, weight: .bold))
                                Text(mode.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(interactionMode == mode ? .white : .white.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(interactionMode == mode ? Color.white.opacity(0.25) : Color.clear)
                            .cornerRadius(6)
                        }
                    }
                }
                .padding(2)
                .background(Color.white.opacity(0.12))
                .cornerRadius(8)

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
