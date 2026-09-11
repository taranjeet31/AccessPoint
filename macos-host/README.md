# macOS Remote Host App

The macOS Host Menu Bar Application captures the Mac screen using `ScreenCaptureKit`, streams it out over WebRTC, receives remote touch/mouse/keyboard control inputs from an iOS Controller app, and synthesizes `CGEvent` system events.

## Architecture

- **`RemoteHostApp.swift`**: Menu-bar accessory application lifecycle (`LSUIElement = true`).
- **`MenuBarController.swift`**: `NSStatusItem` controller coordinating signaling, WebRTC, capture, permissions, and pairing UI.
- **`ScreenCaptureManager.swift`**: Hardware-accelerated screen capture via `ScreenCaptureKit` (`SCStream`, `SCContentFilter`) outputting `CMSampleBuffer` frames.
- **`WebRTCClient.swift`**: WebRTC connection answerer (`libwebrtc` via `stasel/WebRTC`), custom video source frame capturer, and `"control"` data channel handler.
- **`InputInjector.swift`**: Translates normalized `[0.0, 1.0]` coordinates to macOS display points and injects mouse moves/clicks/drags, scrolls, modifier keys, and synthesized Unicode text via `CGEvent`.
- **`PairingView.swift`**: Native SwiftUI pairing interface with 6-digit code, countdown timer, native QR code (`CIFilter.qrCodeGenerator`), and pair approval prompt.
- **`SessionIndicatorWindow.swift`**: Persistent, floating on-screen indicator badge ("Remote Control Active") shown whenever a remote controller is connected.
- **`KeychainStore.swift`**: Secure persistence of session `authToken` in macOS Keychain (`Security.framework`).
- **`PermissionManager.swift`**: Checks and triggers system prompts for Screen Recording and Accessibility permissions.

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon or Intel Mac
- Accessibility permission (for mouse/keyboard control injection)
- Screen Recording permission (for ScreenCaptureKit)

## Building & Running

### Build executable
```bash
swift build
```

### Run tests
```bash
swift run TestRunner
```

### Launch Host App
```bash
swift run RemoteHost
```
