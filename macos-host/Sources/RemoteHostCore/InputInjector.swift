import Foundation
import CoreGraphics
import ApplicationServices
import AppKit

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

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

    private var targetWindowFrame: CGRect?
    private var targetAppProcessID: pid_t?

    public func setTargetWindow(frame: CGRect?, processID: pid_t?) {
        self.targetWindowFrame = frame
        self.targetAppProcessID = processID
    }

    public func activateTargetAppIfNeeded() {
        guard let pid = targetAppProcessID else { return }
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    public func convertNormalizedPoint(x: Double, y: Double) -> CGPoint {
        let clampedX = min(max(x, 0.0), 1.0)
        let clampedY = min(max(y, 0.0), 1.0)

        if let winFrame = targetWindowFrame {
            let localPoint = CGPoint(
                x: clampedX * winFrame.width,
                y: clampedY * winFrame.height
            )
            return CGPoint(
                x: winFrame.origin.x + localPoint.x,
                y: winFrame.origin.y + localPoint.y
            )
        }

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
            activateTargetAppIfNeeded()
            injectMouseMove(x: x, y: y)

        case .mouseDown(let button, let x, let y):
            activateTargetAppIfNeeded()
            injectMouseDown(button: button, x: x, y: y)

        case .mouseUp(let button, let x, let y):
            activateTargetAppIfNeeded()
            injectMouseUp(button: button, x: x, y: y)

        case .scroll(let dx, let dy):
            activateTargetAppIfNeeded()
            injectScroll(dx: dx, dy: dy)

        case .keyDown(let keyCode, let modifiers):
            activateTargetAppIfNeeded()
            injectKey(keyCode: keyCode, modifiers: modifiers, isDown: true)

        case .keyUp(let keyCode, let modifiers):
            activateTargetAppIfNeeded()
            injectKey(keyCode: keyCode, modifiers: modifiers, isDown: false)

        case .textInput(let text):
            activateTargetAppIfNeeded()
            injectTextInput(text: text)

        case .windowInfo(_, let frameX, let frameY, let frameWidth, let frameHeight):
            let frame = CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
            self.targetWindowFrame = frame

        case .windowAction(let windowID, let action):
            performWindowAction(windowID: windowID, action: action)

        case .appList, .selectWindow, .selectScreen:
            break
        }
    }

    // MARK: - Window Actions (AXUIElement)

    public func performWindowAction(windowID: UInt32, action: String) {
        var pid: pid_t = targetAppProcessID ?? 0
        if pid == 0 {
            let options = CGWindowListOption(arrayLiteral: .optionIncludingWindow)
            if let infoList = CGWindowListCopyWindowInfo(options, CGWindowID(windowID)) as? [[String: Any]],
               let info = infoList.first,
               let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t {
                pid = ownerPID
            }
        }
        guard pid > 0 else { return }

        let axApp = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement] else { return }

        var targetAXWindow: AXUIElement?
        for axWindow in windows {
            var axWinID: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &axWinID) == .success, axWinID == CGWindowID(windowID) {
                targetAXWindow = axWindow
                break
            }
        }

        if targetAXWindow == nil {
            targetAXWindow = windows.first
        }

        guard let axWindow = targetAXWindow else { return }

        switch action.lowercased() {
        case "close":
            var closeButton: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &closeButton) == .success,
               let button = closeButton {
                AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
            }
        case "minimize":
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        case "zoom":
            var zoomButton: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, kAXZoomButtonAttribute as CFString, &zoomButton) == .success,
               let button = zoomButton {
                AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
            }
        case "resize_fill":
            if let mainScreen = NSScreen.main {
                let frame = mainScreen.visibleFrame
                var position = frame.origin
                position.y = mainScreen.frame.height - (frame.origin.y + frame.size.height)
                var size = frame.size

                if let sizeVal = AXValueCreate(.cgSize, &size) {
                    AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeVal)
                }
                if let posVal = AXValueCreate(.cgPoint, &position) {
                    AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posVal)
                }
            }
        case "resize_center":
            if let mainScreen = NSScreen.main {
                let screenFrame = mainScreen.visibleFrame
                let targetWidth: CGFloat = min(screenFrame.width * 0.8, 1200)
                let targetHeight: CGFloat = min(screenFrame.height * 0.8, 800)
                var size = CGSize(width: targetWidth, height: targetHeight)
                
                var position = CGPoint(
                    x: screenFrame.origin.x + (screenFrame.width - targetWidth) / 2,
                    y: (mainScreen.frame.height - (screenFrame.origin.y + screenFrame.size.height)) + (screenFrame.height - targetHeight) / 2
                )
                
                if let sizeVal = AXValueCreate(.cgSize, &size) {
                    AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeVal)
                }
                if let posVal = AXValueCreate(.cgPoint, &position) {
                    AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posVal)
                }
            }
        default:
            break
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
