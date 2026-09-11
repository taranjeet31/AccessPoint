import Foundation
import CoreGraphics
import ApplicationServices
import AppKit

public final class PermissionManager: @unchecked Sendable {
    public static let shared = PermissionManager()

    public init() {}

    // MARK: - Accessibility Permission (for CGEvent input injection)

    public var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }

    public func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Screen Recording Permission

    public var isScreenRecordingGranted: Bool {
        return CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    public func requestScreenRecordingPermission() -> Bool {
        return CGRequestScreenCaptureAccess()
    }

    public func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
