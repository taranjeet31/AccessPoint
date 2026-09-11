import Foundation
import CoreGraphics
import ApplicationServices

public final class InputInjector: @unchecked Sendable {
    public static let shared = InputInjector()

    private var displayWidth: Int = 1920
    private var displayHeight: Int = 1080
    private var displayScale: Double = 2.0

    private var isLeftMouseDown = false
    private var isRightMouseDown = false

    public init() {}

    public func updateDisplayInfo(widthPx: Int, heightPx: Int, scaleFactor: Double) {
        self.displayWidth = widthPx
        self.displayHeight = heightPx
        self.displayScale = scaleFactor > 0 ? scaleFactor : 1.0
    }

    public var screenWidthPoints: Double {
        return Double(displayWidth) / displayScale
    }

    public var screenHeightPoints: Double {
        return Double(displayHeight) / displayScale
    }

    public func convertNormalizedPoint(x: Double, y: Double) -> CGPoint {
        let clampedX = min(max(x, 0.0), 1.0)
        let clampedY = min(max(y, 0.0), 1.0)
        return CGPoint(
            x: clampedX * screenWidthPoints,
            y: clampedY * screenHeightPoints
        )
    }

    public func handleControlMessage(_ message: ControlChannelMessage) {
        guard PermissionManager.shared.isAccessibilityGranted else {
            // Drop event if accessibility not granted
            return
        }

        switch message {
        case .displayInfo(let widthPx, let heightPx, let scaleFactor):
            updateDisplayInfo(widthPx: widthPx, heightPx: heightPx, scaleFactor: scaleFactor)

        case .mouseMove(let x, let y):
            injectMouseMove(x: x, y: y)

        case .mouseDown(let button, let x, let y):
            injectMouseDown(button: button, x: x, y: y)

        case .mouseUp(let button, let x, let y):
            injectMouseUp(button: button, x: x, y: y)

        case .scroll(let dx, let dy):
            injectScroll(dx: dx, dy: dy)

        case .keyDown(let keyCode, let modifiers):
            injectKey(keyCode: keyCode, modifiers: modifiers, isDown: true)

        case .keyUp(let keyCode, let modifiers):
            injectKey(keyCode: keyCode, modifiers: modifiers, isDown: false)

        case .textInput(let text):
            injectTextInput(text: text)
        }
    }

    // MARK: - Mouse Injection

    public func injectMouseMove(x: Double, y: Double) {
        let point = convertNormalizedPoint(x: x, y: y)
        let eventType: CGEventType
        let mouseButton: CGMouseButton

        if isLeftMouseDown {
            eventType = .leftMouseDragged
            mouseButton = .left
        } else if isRightMouseDown {
            eventType = .rightMouseDragged
            mouseButton = .right
        } else {
            eventType = .mouseMoved
            mouseButton = .left
        }

        if let event = CGEvent(
            mouseEventSource: nil,
            mouseType: eventType,
            mouseCursorPosition: point,
            mouseButton: mouseButton
        ) {
            event.post(tap: .cghidEventTap)
        }
    }

    public func injectMouseDown(button: String, x: Double, y: Double) {
        let point = convertNormalizedPoint(x: x, y: y)
        let eventType: CGEventType
        let mouseButton: CGMouseButton

        switch button.lowercased() {
        case "right":
            eventType = .rightMouseDown
            mouseButton = .right
            isRightMouseDown = true
        case "center", "middle", "other":
            eventType = .otherMouseDown
            mouseButton = .center
        default:
            eventType = .leftMouseDown
            mouseButton = .left
            isLeftMouseDown = true
        }

        if let event = CGEvent(
            mouseEventSource: nil,
            mouseType: eventType,
            mouseCursorPosition: point,
            mouseButton: mouseButton
        ) {
            event.post(tap: .cghidEventTap)
        }
    }

    public func injectMouseUp(button: String, x: Double, y: Double) {
        let point = convertNormalizedPoint(x: x, y: y)
        let eventType: CGEventType
        let mouseButton: CGMouseButton

        switch button.lowercased() {
        case "right":
            eventType = .rightMouseUp
            mouseButton = .right
            isRightMouseDown = false
        case "center", "middle", "other":
            eventType = .otherMouseUp
            mouseButton = .center
        default:
            eventType = .leftMouseUp
            mouseButton = .left
            isLeftMouseDown = false
        }

        if let event = CGEvent(
            mouseEventSource: nil,
            mouseType: eventType,
            mouseCursorPosition: point,
            mouseButton: mouseButton
        ) {
            event.post(tap: .cghidEventTap)
        }
    }

    public func injectScroll(dx: Double, dy: Double) {
        // Convert normalized scroll delta to pixel delta
        let pixelDy = Int32(dy * screenHeightPoints * 5.0)
        let pixelDx = Int32(dx * screenWidthPoints * 5.0)

        if let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: pixelDy,
            wheel2: pixelDx,
            wheel3: 0
        ) {
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Keyboard Injection

    public func mapModifiers(_ modifiers: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for mod in modifiers {
            switch mod.lowercased() {
            case "shift":
                flags.insert(.maskShift)
            case "control", "ctrl":
                flags.insert(.maskControl)
            case "option", "opt", "alt":
                flags.insert(.maskAlternate)
            case "command", "cmd":
                flags.insert(.maskCommand)
            case "capslock", "caps":
                flags.insert(.maskAlphaShift)
            default:
                break
            }
        }
        return flags
    }

    public func injectKey(keyCode: UInt16, modifiers: [String], isDown: Bool) {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(keyCode),
            keyDown: isDown
        ) else { return }

        let flags = mapModifiers(modifiers)
        if !flags.isEmpty {
            event.flags = flags
        }
        event.post(tap: .cghidEventTap)
    }

    public func injectTextInput(text: String) {
        let utf16Chars = Array(text.utf16)
        guard !utf16Chars.isEmpty else { return }

        // Create a dummy keydown and keyup with Unicode string attached
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
            return
        }

        keyDown.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        keyUp.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
