# iOS Remote Controller App

The iOS Controller App pairs with a macOS Host, displays its live screen with low-latency hardware-accelerated WebRTC rendering (`RTCMTLVideoView`), translates touch interactions into normalized display events, and supports software typing and macOS shortcuts.

## Architecture

- **`RemoteControllerApp.swift`**: SwiftUI app entrypoint and coordinator managing session state, pairing routing, and WebRTC lifecycle.
- **`PairingScanView.swift`**: Native QR code scanner using `AVFoundation` (`AVCaptureSession`) with fallback manual 6-digit code entry.
- **`SignalingClient.swift`**: Native WebSocket client (`URLSessionWebSocketTask`) registering as `role: "controller"`.
- **`WebRTCClient.swift`**: WebRTC Peer Connection as **OFFERER** (`stasel/WebRTC`), data channel initiator (`"control"` channel), and remote video track consumer.
- **`VideoStreamView.swift`**: Hardware-accelerated Metal video rendering via `RTCMTLVideoView`.
- **`GestureController.swift`**: Translates touches to normalized `[0.0, 1.0]` coordinates relative to the letterboxed/pillarboxed video content rect.
- **`SoftKeyboardBridge.swift`**: Hidden `UITextField` capturing the native iOS software keyboard without a visible text box, translating typing to `text_input` messages and backspace/enter keys.
- **`ControlBarView.swift`**: Floating glass toolbar with macOS shortcuts (Esc, Tab, Cmd+Tab, Cmd+C, Cmd+V, Cmd+Z, Cmd+Space, Arrow keys, Keyboard toggle, Disconnect).
- **`NetworkMonitor.swift`**: Monitors network interface transitions (Wi-Fi <-> Cellular) using `NWPathMonitor` and triggers automatic signaling reconnection and WebRTC ICE restarts.
- **`KeychainStore.swift`**: Secure persistence of session `authToken` and paired `peerDeviceId` in iOS Keychain (`Security.framework`).

## Requirements

- iOS 16.0 or later (iPhone & iPad)
- Camera permission (for QR code pairing)
- Internet connection (Wi-Fi or Cellular)

## Building & Running

### Build Swift package
```bash
swift build
```

### Run automated test suite
```bash
swift run TestRunner
```
