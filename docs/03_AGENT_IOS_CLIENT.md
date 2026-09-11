# Agent C — iOS Controller App

**Read `00_PROJECT_CONTEXT_AND_PROTOCOL.md` in full before starting.** You are building the viewing/controlling side. You never write signaling server or macOS code, and only assume the WebRTC/data-channel contract in section 4.2–4.3 of that file about what the Mac does.

## Your job, in one sentence

An iPhone app that pairs with a Mac, displays its screen live with low latency, and translates touches and typed text into control input sent back to the Mac.

## Tech stack

- Swift, SwiftUI
- WebRTC via Swift Package Manager — `stasel/WebRTC` (same package as the macOS agent, for consistency and to guarantee wire compatibility)
- `URLSessionWebSocketTask` for signaling
- `AVFoundation` for QR code scanning (pairing)
- `RTCMTLVideoView` (comes with the WebRTC package) wrapped in a `UIViewRepresentable` for rendering

## Project structure to create

```
ios-client/
└── RemoteController/
    ├── RemoteControllerApp.swift
    ├── PairingScanView.swift        # QR scan or manual code entry
    ├── SignalingClient.swift        # WebSocket client, mirrors Agent B's but role "controller"
    ├── WebRTCClient.swift           # PeerConnection setup (as OFFERER), data channel creation
    ├── VideoStreamView.swift        # UIViewRepresentable wrapping RTCMTLVideoView
    ├── RemoteScreenView.swift       # main screen: video + gesture overlay + control bar
    ├── GestureController.swift      # touch -> normalized coords -> data channel messages
    ├── SoftKeyboardBridge.swift     # hidden UITextField capturing system keyboard -> text_input
    ├── ControlBarView.swift         # on-screen buttons: esc, cmd+tab, cmd+c/v, arrow keys, disconnect
    ├── KeychainStore.swift          # authToken storage, mirrors Agent B's approach
    └── Models/
        └── ProtocolMessages.swift   # Swift structs/enums mirroring the JSON contract exactly
```

## Step-by-step build order

### Step 1 — App shell and pairing UI (no networking yet)
- Standard SwiftUI app, single main flow: if no saved pairing exists, show `PairingScanView`; if one exists, go straight to `RemoteScreenView`.
- `PairingScanView.swift`: use `AVCaptureSession` + `AVCaptureMetadataOutput` to scan a QR code (falls back to a manual 6-digit text entry field, since not every pairing will happen with both devices in the same room able to scan).
- **Acceptance**: scanning a QR code (or typing a code) captures the string; no server interaction yet, just log it.

### Step 2 — Signaling client
- `SignalingClient.swift`: same shape as Agent B's, but registers with role `"controller"`. Connects to the same deployed signaling server URL.
- On having a pairing code (from Step 1), send `pair` with that code and the device's own generated `deviceId`/`deviceName`. Handle `paired` (store `authToken` + peer's `deviceId` in Keychain), `pair_denied`, and `pair_expired` with appropriate UI feedback.
- On subsequent launches with a stored token, send `resume_session` instead of going through `PairingScanView` again.
- **Acceptance**: pairing against Agent A's real deployed server (using Agent B's app or a stub host) results in a stored token and a "paired" UI state.

### Step 3 — WebRTC peer connection as offerer
- `WebRTCClient.swift`: per the protocol doc, **the controller always creates the offer**. After `paired`/`resume_session` succeeds: create the peer connection, create the `"control"` data channel yourself (label exactly `"control"`, ordered), create an offer, set local description, send `offer` via signaling, then handle the incoming `answer` and relayed `ice_candidate` messages.
- Fetch TURN credentials via `request_turn_credentials` before building the ICE server list — don't hardcode only STUN, or connections across CGNAT/cellular will silently fail.
- Handle the incoming video track in `onTrack` and hand it to `VideoStreamView`.
- **Acceptance**: against Agent B's app (or a stub), the offer/answer/ICE exchange completes and `RTCPeerConnection` reaches `connected` state.

### Step 4 — Video rendering
- `VideoStreamView.swift`: wrap `RTCMTLVideoView` in `UIViewRepresentable`, attach the received `RTCVideoTrack` to it.
- Handle aspect ratio correctly — the Mac's display aspect ratio will rarely match the iPhone's screen, so letterbox/pillarbox rather than stretching.
- **Acceptance**: live Mac screen video renders smoothly on the iPhone over a real internet connection.

### Step 5 — Gesture-to-input mapping
- `GestureController.swift`: attach gesture recognizers to the video view's overlay:
  - Single tap → `mouse_down` immediately followed by `mouse_up` at the tapped point (a click).
  - Long-press-and-drag → `mouse_down` at press location, then `mouse_move` messages as the finger moves, `mouse_up` on release (this is how you drag things / select text).
  - Two-finger drag → `scroll` messages using the finger delta.
  - Two-finger tap → treat as a right-click (`mouse_down`/`mouse_up` with `button: "right"`).
- **Critical**: convert touch location from the view's own coordinate space to normalized `[0,1]` coordinates relative to the *video content rect* (not the full view, if letterboxed — account for the black bars from Step 4), before sending. Getting this wrong is the most common bug in this kind of app; test explicitly with the Mac in both a 16:9 external monitor and its native laptop aspect ratio.
- Wait for at least one `display_info` message before enabling any gesture recognizer (per protocol doc — don't send coordinates the host can't interpret yet).
- **Acceptance**: tapping/dragging/scrolling on the iPhone visibly and correctly moves the Mac cursor and interacts with on-screen elements at the right location.

### Step 6 — Keyboard input
- `SoftKeyboardBridge.swift`: use a hidden, off-screen `UITextField` that becomes first responder when the user taps a "keyboard" toggle button, bringing up the system keyboard without showing an ugly visible text field. Listen to `UITextField` delegate callbacks / `NSNotification.Name.UITextFieldTextDidChange` and forward typed characters as `text_input` messages, then clear the field's buffer after each send so it doesn't accumulate.
- `ControlBarView.swift`: a compact row of buttons for things typing can't express — Esc, Tab, Cmd+Tab, Cmd+C, Cmd+V, arrow keys — each sending explicit `key_down`+`key_up` with the correct macOS virtual keycode and modifiers per the protocol doc schema. Keep a small lookup table of the keycodes you need (Esc=53, Tab=48, arrows=123–126, C=8, V=9, Cmd modifier flag, etc.) — verify these against Apple's `Carbon/HIToolbox` `kVK_*` constants rather than guessing.
- **Acceptance**: typing a sentence on the iPhone keyboard produces correct text on the Mac; the control bar's shortcuts trigger the right macOS behavior (copy/paste, app switching).

### Step 7 — Reconnection & network handling
- Detect network path changes (`NWPathMonitor`) and transparently re-establish the signaling WebSocket and, if needed, restart ICE (`restartIce()` on the peer connection) rather than forcing the user through pairing again.
- Show a clear "reconnecting…" state over the video view rather than a frozen last frame with no explanation.
- **Acceptance**: toggling Wi-Fi off and relying on cellular mid-session recovers the connection without dropping back to the pairing screen.

### Step 8 — Polish & distribution prep
- Settings screen: video quality preference (if you exposed bitrate/resolution hints — coordinate with Agent B if adding this beyond v1 scope), disconnect button, unpair/forget-this-Mac option (clears the Keychain token).
- App icon, launch screen, basic onboarding copy explaining the pairing flow for first-time use.
- Set up TestFlight: requires an Apple Developer account (same one used for the Mac app's signing/notarization), App Store Connect record, and a test group for yourself/testers.

## Acceptance criteria (what "done" means for this agent)

- [ ] Pairing via QR scan and via manual code entry both work end to end against the real deployed signaling server.
- [ ] Returning to the app after force-quitting reconnects via `resume_session` without re-pairing.
- [ ] Video renders with correct aspect ratio and no unnecessary latency (aim to visually confirm sub-200ms glass-to-glass feel on a good connection, not a hard measured spec at this stage).
- [ ] Tap/drag/scroll/right-click gestures land at the correct on-screen position on the Mac, verified against both a laptop-native display and an external monitor aspect ratio.
- [ ] Typed text and control-bar shortcuts work correctly.
- [ ] Switching networks mid-session recovers automatically.
- [ ] TestFlight build installs and runs on a physical iPhone (simulator cannot test camera/QR scanning or real network conditions, so physical-device testing is mandatory before considering this agent's work done).
