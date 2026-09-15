# Public Remote Desktop Project Checklist & QA Validation Matrix

This document tracks all required deployment steps, field tests, end-to-end integration use cases, and acceptance criteria before releasing **v1.0** of the Remote Desktop System.

---

## 📍 System Architecture & Components Overview

| Component | Repository Directory | Tech Stack | Status |
|---|---|---|---|
| **Signaling Server** | `signaling-server/` | Node.js, TypeScript, `ws`, Express, JWT, Pino | Code Complete / Needs Cloud Deploy |
| **macOS Host App** | `macos-host/` | Swift, SwiftUI, ScreenCaptureKit, WebRTC, CGEvent | Core Implemented |
| **iOS Controller App** | `ios-client/` | Swift, SwiftUI, AVFoundation, WebRTC, CoreGraphics | Core Implemented |

---

## 1. ☁️ Infrastructure & Cloud Deployment Checklist

- [ ] **Signaling Server Deployment**:
  - [ ] Deploy Dockerized WebSocket server to a cloud provider (e.g. Fly.io, Railway, or AWS EC2).
  - [ ] Configure TLS termination to serve WebSocket traffic over `wss://<signaling-domain>/ws`.
  - [ ] Set required environment variables: `PORT`, `JWT_SECRET`, `TURN_PROVIDER_URL`, `TURN_PROVIDER_API_KEY`, `NODE_ENV=production`.
  - [ ] Verify HTTP health check endpoint returns `200 OK` (`GET /health`).
- [ ] **TURN / STUN Relaying**:
  - [ ] Configure dynamic TURN credentials fetching via Metered.ca or Twilio Network Traversal API in `turn.ts`.
  - [ ] Test TURN server responsiveness using standard WebRTC diagnostic tools (e.g., `trickle-ice`).

---

## 2. 📱 Device Provisioning & Permissions Readiness

- [ ] **macOS Host Device Setup**:
  - [ ] Verify Screen Recording runtime permission prompt on first launch via ScreenCaptureKit.
  - [ ] Verify Accessibility permission check (`AXIsProcessTrustedWithOptions`) with user prompt directing to System Settings.
  - [ ] Confirm menu bar item (`LSUIElement = YES`) operates cleanly without showing a Dock icon.
  - [ ] Test "Launch at login" toggle using `SMAppService.mainApp.register()`.
- [ ] **iOS Controller Device Setup**:
  - [ ] Configure physical iOS device signing in Xcode with an Apple Developer account.
  - [ ] Grant Camera usage permissions for scanning pairing QR codes.
  - [ ] Distribute test builds to physical devices via TestFlight or Direct Device Installation.

---

## 3. 🔐 Pairing, Auth & Session Security Matrix

- [ ] **First-Time Pairing**:
  - [ ] **QR Code Scanning**: Host displays QR code encoding 6-digit pin + device details; iPhone scans and initiates pairing.
  - [ ] **Manual PIN Fallback**: Host displays 6-digit numeric pin; iPhone user manually enters code.
  - [ ] **On-Mac Approval Prompt**: Pairing request generates an explicit approve/deny alert on the Mac.
  - [ ] **Denial Handling**: Denying request sends `pair_denied` to controller and stops session setup.
  - [ ] **Token Persistence**: On approval, both devices securely save the issued JWT `authToken` in Keychain.
- [ ] **Session Resumption**:
  - [ ] Controller re-opens session using `resume_session` with saved JWT without triggering re-pairing PIN screen.
  - [ ] Host surfaces lightweight notification toast on session resumption.
- [ ] **Visual Session Indicator**:
  - [ ] Persistent on-screen "being controlled" overlay window (`SessionIndicatorWindow.swift`) remains visible for 100% of an active session.

---

## 4. 📹 WebRTC Media Streaming & Performance Validation

- [ ] **Cross-Network Traversal**:
  - [ ] Pair & stream video between Mac on home Wi-Fi and iPhone on Cellular (LTE/5G) across distinct networks.
- [ ] **Video Quality & Latency**:
  - [ ] Video stream renders within ~2 seconds of session establishment.
  - [ ] Frame rate meets or exceeds 20 FPS at consistent bitrates.
  - [ ] Glass-to-glass latency target is sub-200ms on broadband networks.
  - [ ] Hardware H.264 encoding/decoding via VideoToolbox operates without software fallback.
- [ ] **Aspect Ratio & Display Info**:
  - [ ] `display_info` JSON message sent immediately over `"control"` data channel upon connection.
  - [ ] Video stream letterboxing/pillarboxing preserves native Mac display aspect ratio on iPhone screen without stretching.

---

## 5. 🖱️ Touch Gestures & Input Injection Accuracy

- [ ] **Touch Gesture Mappings**:
  - [ ] **Single Tap**: Injects `mouse_down` followed immediately by `mouse_up` (left click).
  - [ ] **Long-Press & Drag**: Injects `mouse_down`, continuous `mouse_move`, and `mouse_up` on release (text selection & dragging).
  - [ ] **Two-Finger Drag**: Injects `scroll` wheel events with delta tracking.
  - [ ] **Two-Finger Tap**: Injects right-click (`button: "right"`).
- [ ] **Coordinate Normalization**:
  - [ ] Touch coordinates in `[0.0, 1.0]` range map accurately to Mac cursor position regardless of letterboxing, display resolution, or Retina scale factor.
- [ ] **Keyboard Input**:
  - [ ] Hidden `UITextField` captures software keyboard input and sends `text_input` strings to host.
  - [ ] On-screen shortcut control bar sends accurate virtual keycodes for `Esc`, `Tab`, `Cmd+Tab`, `Cmd+C`, `Cmd+V`, and Arrow keys.

---

## 6. 🌐 Network Resilience & Error Recovery

- [ ] **Network Handoff**:
  - [ ] Switching iPhone mid-session from Wi-Fi to cellular data triggers automatic ICE restart (`NWPathMonitor`) without dropping back to pairing screen.
- [ ] **Signaling Disconnection**:
  - [ ] Reconnect WebSocket background backoff reconnects without tearing down live WebRTC peer connection.
- [ ] **Host Sleep & Display Lock**:
  - [ ] Host system sleep gracefully stops `SCStream` and restarts cleanly upon system wake.
  - [ ] Screen lock state displays informative status overlay on controller rather than freezing.

---

## 7. 🧹 Cleanup & Unpairing

- [ ] **Disconnect Action**: User-initiated disconnect tearing down data channels, media tracks, and WebRTC peer connection cleanly.
- [ ] **Peer Disconnection Notification**: Process termination or socket drop sends `peer_disconnected` message to active peer.
- [ ] **Forget Device / Unpair**: Settings option to clear Keychain JWT token and reset pairing state.
