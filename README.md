# Remote Desktop: macOS Host & iOS Controller

A low-latency, secure remote screen-viewing and control system for macOS and iOS built with WebRTC, ScreenCaptureKit, and TypeScript.

```
remote-desktop/
├── signaling-server/    # Agent A: WebSocket Signaling & TURN Broker (Node.js + TS)
├── macos-host/          # Agent B: ScreenCaptureKit + WebRTC Host (Swift / SwiftUI)
├── ios-client/          # Agent C: WebRTC iOS Controller App (Swift / SwiftUI)
└── docs/                # Architecture & Protocol Contracts
```

---

## Quick Start & System Integration Guide

### Step 1: Start the Signaling Server

```bash
cd signaling-server
npm install
npm run dev
```
- **Server runs on**: `http://localhost:8080`
- **Signaling WebSocket**: `ws://localhost:8080/ws`
- **Health Check**: `http://localhost:8080/health`

To verify the signaling server and test suite:
```bash
npm test
npm run test:e2e
```

---

### Step 2: Start the macOS Host App

In a separate terminal window:
```bash
cd macos-host
swift run RemoteHost
```

- When prompted on first launch:
  1. **Screen Recording**: Allow in System Settings → Privacy & Security → Screen Recording.
  2. **Accessibility**: Allow in System Settings → Privacy & Security → Accessibility (needed for mouse/keyboard event injection).
- A menu-bar icon (`display.and.arrow.down`) will appear.
- Click the menu-bar icon → **"Pair New Device..."** to open the pairing window displaying the 6-digit code and QR code.

> **Tip (Custom Signaling URL)**:
> If running on a remote host or different machine on the LAN, pass `SIGNALING_URL`:
> ```bash
> SIGNALING_URL="ws://<YOUR-SERVER-IP>:8080/ws" swift run RemoteHost
> ```

---

### Step 3: Run the iOS Controller App

#### Option A: Run Automated Tests
```bash
cd ios-client
swift run TestRunner
```

#### Option B: Run on Physical iPhone / Simulator
1. Open `ios-client/` in Xcode or build using `xcodebuild`.
2. Launch the app on your iPhone.
3. Point the iPhone camera at the Mac screen to scan the QR code (or enter the 6-digit code manually).
4. On your Mac, an on-screen approval prompt will appear: **"Alex's iPhone wants to pair. Approve / Deny"**.
5. Click **Approve**.
6. The Mac screen immediately begins streaming live to the iPhone with touch interaction and keyboard control enabled!
7. A persistent **"Remote Control Active"** indicator overlay will float on the Mac screen while connected.

---

## Network Setups & Over-the-Internet Testing

### Setup 1: Local / LAN Testing (Same Wi-Fi)
1. Find your Mac's LAN IP (e.g. `ipconfig getifaddr en0` -> `192.168.1.100`).
2. Start signaling server: `PORT=8080 npm run dev`
3. Point both apps to: `SIGNALING_URL="ws://192.168.1.100:8080/ws"`

### Setup 2: Remote / Internet Testing (Mac on Home Wi-Fi, iPhone on Cellular)
1. Deploy the Signaling Server to Fly.io, Railway, or tunnel with Cloudflare/ngrok:
   ```bash
   ngrok http 8080
   # Gives wss://<subdomain>.ngrok-free.app/ws
   ```
2. Set `SIGNALING_URL="wss://<subdomain>.ngrok-free.app/ws"` on both Host and Controller.
3. Configure `TURN_PROVIDER_API_KEY` (e.g., from Metered.ca Open Relay free tier) in `signaling-server/.env` so connections succeed across symmetric NAT and cellular firewalls.

---

## End-to-End QA Checklist

- [x] **Signaling & Pairing Handshake**: 6-digit pairing code generation, camera QR scanning, approval flow, and JWT token issuance.
- [x] **Session Resumption**: Force-quitting and reopening reconnects via `resume_session` without re-pairing.
- [x] **Live Video Stream**: Hardware-accelerated ScreenCaptureKit capture -> WebRTC H.264 stream -> Metal `RTCMTLVideoView` rendering.
- [x] **Touch Control**: Taps, right-clicks (2-finger tap), drags (long press + drag), and scrolling (2-finger drag) mapped to normalized coordinates.
- [x] **Keyboard & Shortcuts**: iOS software keyboard input and macOS shortcuts (`⌘ Tab`, `⌘ C`, `⌘ V`, `⌘ Space`, `Esc`, arrow keys).
- [x] **Security & Trust**: Persistent on-screen indicator badge ("Remote Control Active") shown 100% of the active session.
- [x] **Network Recovery**: `NWPathMonitor` automatic reconnection and ICE restart on network handoff.
