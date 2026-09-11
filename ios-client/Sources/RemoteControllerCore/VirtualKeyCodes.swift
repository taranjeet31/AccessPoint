import Foundation

public struct MacVirtualKeyCode: Sendable, Equatable {
    public let code: UInt16
    public let name: String

    public init(_ code: UInt16, name: String) {
        self.code = code
        self.name = name
    }

    // Standard Special Keys (macOS Virtual Keycodes from Carbon/HIToolbox)
    public static let escape = MacVirtualKeyCode(53, name: "Esc")
    public static let tab = MacVirtualKeyCode(48, name: "Tab")
    public static let returnKey = MacVirtualKeyCode(36, name: "Return")
    public static let delete = MacVirtualKeyCode(51, name: "Backspace")
    public static let forwardDelete = MacVirtualKeyCode(117, name: "Delete")
    public static let space = MacVirtualKeyCode(49, name: "Space")

    // Navigation Arrows
    public static let leftArrow = MacVirtualKeyCode(123, name: "←")
    public static let rightArrow = MacVirtualKeyCode(124, name: "→")
    public static let downArrow = MacVirtualKeyCode(125, name: "↓")
    public static let upArrow = MacVirtualKeyCode(126, name: "↑")

    // ANSI Letter Keys
    public static let a = MacVirtualKeyCode(0, name: "A")
    public static let s = MacVirtualKeyCode(1, name: "S")
    public static let d = MacVirtualKeyCode(2, name: "D")
    public static let f = MacVirtualKeyCode(3, name: "F")
    public static let h = MacVirtualKeyCode(4, name: "H")
    public static let g = MacVirtualKeyCode(5, name: "G")
    public static let z = MacVirtualKeyCode(6, name: "Z")
    public static let x = MacVirtualKeyCode(7, name: "X")
    public static let c = MacVirtualKeyCode(8, name: "C")
    public static let v = MacVirtualKeyCode(9, name: "V")
    public static let b = MacVirtualKeyCode(11, name: "B")
    public static let q = MacVirtualKeyCode(12, name: "Q")
    public static let w = MacVirtualKeyCode(13, name: "W")
}

public struct MacShortcut: Sendable, Equatable {
    public let label: String
    public let icon: String?
    public let keyCode: UInt16
    public let modifiers: [String]

    public init(label: String, icon: String? = nil, keyCode: UInt16, modifiers: [String] = []) {
        self.label = label
        self.icon = icon
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let escape = MacShortcut(label: "Esc", keyCode: MacVirtualKeyCode.escape.code)
    public static let tab = MacShortcut(label: "Tab", keyCode: MacVirtualKeyCode.tab.code)
    public static let cmdTab = MacShortcut(label: "⌘ Tab", keyCode: MacVirtualKeyCode.tab.code, modifiers: ["cmd"])
    public static let cmdC = MacShortcut(label: "⌘ C", keyCode: MacVirtualKeyCode.c.code, modifiers: ["cmd"])
    public static let cmdV = MacShortcut(label: "⌘ V", keyCode: MacVirtualKeyCode.v.code, modifiers: ["cmd"])
    public static let cmdZ = MacShortcut(label: "⌘ Z", keyCode: MacVirtualKeyCode.z.code, modifiers: ["cmd"])
    public static let cmdSpace = MacShortcut(label: "⌘ Space", keyCode: MacVirtualKeyCode.space.code, modifiers: ["cmd"])
    public static let cmdW = MacShortcut(label: "⌘ W", keyCode: MacVirtualKeyCode.w.code, modifiers: ["cmd"])

    public static let upArrow = MacShortcut(label: "↑", keyCode: MacVirtualKeyCode.upArrow.code)
    public static let downArrow = MacShortcut(label: "↓", keyCode: MacVirtualKeyCode.downArrow.code)
    public static let leftArrow = MacShortcut(label: "←", keyCode: MacVirtualKeyCode.leftArrow.code)
    public static let rightArrow = MacShortcut(label: "→", keyCode: MacVirtualKeyCode.rightArrow.code)
}
