# Agent B — macOS Host App

**Read `00_PROJECT_CONTEXT_AND_PROTOCOL.md` in full before starting.** You are building the screen-sharing, input-receiving side. You never write signaling server code and never assume anything about the iPhone app's internals beyond the WebRTC/data-channel contract in section 4.2–4.3 of that file.

## Your job, in one sentence

A macOS menu-bar app that captures the screen, streams it out over WebRTC to a paired iPhone, and injects mouse/keyboard events it receives back — with clear on-screen indication whenever it's being controlled.

## Tech stack

- Swift, SwiftUI for UI, AppKit interop where SwiftUI doesn't cover it (menu bar item, NSStatusItem)
- `ScreenCaptureKit` for screen capture (macOS 13+ target — don't bother supporting older OSes, ScreenCaptureKit is materially better than the legacy APIs and this is a personal/small-scale tool)
- WebRTC via Swift Package Manager — use the `stasel/WebRTC` SPM package (a maintained precompiled build of Google's libwebrtc for Apple platforms); the original CocoaPods GoogleWebRTC is stale, don't use it
- `URLSessionWebSocketTask` for the signaling connection (no extra dependency needed for plain WebSocket)
- `CoreGraphics` (`CGEvent`) for input injection
- `SMAppService` (macOS 13+) for launch-at-login

## Project structure to create

```
macos-host/
└── RemoteHost/
    ├── RemoteHostApp.swift          # @main, menu bar setup
    ├── MenuBarController.swift      # status item, menu, pairing/status UI trigger
    ├── PairingView.swift            # SwiftUI: shows pairing code + QR, approve/deny prompt
    ├── SignalingClient.swift        # WebSocket client implementing section 4.1 messages
    ├── WebRTCClient.swift           # PeerConnection setup, video track, data channel
    ├── ScreenCaptureManager.swift   # ScreenCaptureKit capture -> CMSampleBuffer -> RTCVideoFrame
    ├── InputInjector.swift          # data channel messages -> CGEvent
    ├── SessionIndicatorWindow.swift # persistent on-screen "being controlled" overlay
    ├── KeychainStore.swift          # authToken storage per paired device
    └── Models/
        └── ProtocolMessages.swift   # Swift structs/enums mirroring the JSON contract exactly
```

## Step-by-step build order

### Step 1 — App shell and permissions groundwork
- Create the Xcode project as a regular macOS App (not a background-only agent — see context doc for why: TCC permissions bind to the signed app bundle, and a hidden daemon fights the permission UX).
- Set `LSUIElement = YES` in Info.plist so it runs as a menu-bar-only app with no Dock icon.
- Add `NSStatusItem` via `MenuBarController`, with a menu: "Pair new device", "Status: idle/connected", "Quit".
- Add the two required entitlements/usage strings: Screen Recording usage is requested at runtime via ScreenCaptureKit (no Info.plist string needed on macOS, but the first capture call triggers the system permission dialog — handle the "not authorized yet" case gracefully with a UI prompt pointing the user to System Settings → Privacy & Security → Screen Recording).
- Implement Accessibility permission check via `AXIsProcessTrustedWithOptions` with the prompt option, for CGEvent injection later.
- **Acceptance for this step**: app launches, sits in the menu bar, and correctly detects/prompts for both permissions without doing anything else yet.

### Step 2 — Screen capture, local-only
- In `ScreenCaptureManager.swift`, use `SCShareableContent` to enumerate displays, `SCStream` with an `SCContentFilter` for the chosen display, and a `SCStreamOutput` delegate to receive `CMSampleBuffer` frames.
- For this step only, render frames into a local preview `NSWindow` (an `NSImageView` fed from the sample buffer) — this isolates and proves capture works before any networking is involved.
- Handle display resolution/scale factor changes (user plugs in a monitor) by re-creating the stream filter.
- **Acceptance**: local preview window shows a live, smooth view of the chosen display.

### Step 3 — Signaling client
- `SignalingClient.swift`: wraps `URLSessionWebSocketTask`, connects to the signaling server URL (configurable, but hardcode your deployed Agent A URL for now), sends `register` with role `"host"`, and exposes a delegate/closure-based API for the other message types from protocol doc section 4.1.
- Implement reconnect-with-backoff if the socket drops (exponential backoff, cap around 30s) — this must NOT tear down an active WebRTC session, only the signaling channel.
- `PairingView.swift`: SwiftUI view triggered from the menu bar, calls `create_pairing_code`, displays the 6-digit code plus a QR code (use `CIFilter.qrCodeGenerator` — no third-party library needed) encoding the code. When a `pair_request` arrives, show an approve/deny alert with the requesting device's name.
- On `paired`, store the `authToken` in Keychain (`KeychainStore.swift`) keyed by the peer's `deviceId`.
- **Acceptance**: pairing code displays, and manually driving the flow from Agent A's `wscat` test (pretending to be the iPhone) results in an approve prompt and a stored token.

### Step 4 — WebRTC peer connection + video track
- `WebRTCClient.swift`: create an `RTCPeerConnectionFactory`, configure ICE servers from the `turn_credentials` response plus a public STUN server, create the peer connection as **answerer** (per protocol doc: host never initiates the offer).
- On receiving `offer` via signaling, set remote description, create answer, set local description, send `answer` back, and forward any `ice_candidate` messages both directions.
- Create a custom `RTCVideoCapturer`/`RTCVideoSource` and feed it frames from `ScreenCaptureManager` (convert `CMSampleBuffer` → `RTCVideoFrame` via `RTCCVPixelBuffer`). Add this as the local video track on the peer connection.
- Create the `"control"` data channel is actually created by the controller (data channels can be initiated by either side once connected, but per protocol doc the controller drives session setup) — the host just needs to handle `onDataChannel` when it arrives and hold onto it for both receiving input and sending `display_info`.
- Immediately after the data channel opens, send `display_info` per the exact schema in the protocol doc, and again whenever the captured display's resolution or scale factor changes.
- **Acceptance**: with a minimal stub controller (even a test script using a WebRTC client library), video frames arrive and decode on the other end.

### Step 5 — Input injection
- `InputInjector.swift`: parse incoming data-channel JSON messages per the exact schema in protocol doc section 4.3.
- Convert normalized `x,y` back to real pixel coordinates using the last-sent `display_info` dimensions, then use `CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)` for move/click/drag, `CGEvent(scrollWheelEvent2Source:...)` for scroll, and `CGEvent(keyboardEventSource:virtualKey:keyDown:)` for key events, posting each with `.post(tap: .cghidEventTap)`.
- For `text_input`, iterate characters and synthesize the corresponding key events (handle basic ASCII plus common punctuation; don't try to solve full Unicode/IME input in v1 — flag it as a known limitation).
- Guard every injection call behind the Accessibility-trusted check from Step 1; if not trusted, drop the event and surface a UI warning rather than silently failing.
- **Acceptance**: with the Step 4 stub controller sending synthetic input messages, the Mac cursor moves/clicks and keystrokes land in a text field.

### Step 6 — Session indicator & UX polish
- `SessionIndicatorWindow.swift`: a small always-on-top, click-through `NSWindow` (or a menu bar icon state change plus a brief `NSUserNotification`) that appears the moment a WebRTC connection becomes active and disappears when it ends. This must be impossible to miss — this is a trust-critical UI element, not a nice-to-have.
- Add a "Disconnect" action in the menu bar that tears down the current session on demand.
- Implement `SMAppService.mainApp.register()` behind a "Launch at login" toggle in a simple settings view.

### Step 7 — Robustness
- Handle system sleep/wake: stop the `SCStream` cleanly on sleep, restart on wake, and re-negotiate if the WebRTC connection dropped.
- Handle the display being locked (screen saver / lock screen) — ScreenCaptureKit will stop producing frames; detect this and show a "screen locked" state to the controller rather than a frozen frame (you can send a lightweight data-channel status message for this if useful, though it's not in the v1 protocol — coordinate with Agent C if you add one).
- Reconnect the signaling WebSocket transparently on network changes without requiring the user to re-pair.

## Acceptance criteria (what "done" means for this agent)

- [ ] Fresh install, first launch: prompts for Screen Recording and Accessibility permissions clearly, with instructions if denied.
- [ ] Pairing code + QR both display correctly and match what a real device scanning/entering it receives.
- [ ] A new pairing always requires explicit approval on the Mac; a returning known device reconnects via `resume_session` without that prompt but still shows the session indicator.
- [ ] Live screen video streams out over an actual internet connection (not just localhost) once paired with Agent C's app.
- [ ] Mouse, click, drag, scroll, and typed text from the controller correctly manipulate the Mac.
- [ ] The "being controlled" indicator is visible for the entire duration of every active session, no exceptions.
- [ ] Sleep/wake and brief network drops recover without requiring a full re-pair.
