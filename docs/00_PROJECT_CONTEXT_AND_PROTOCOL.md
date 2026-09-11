# Project context & shared protocol — read this before anything else

Every agent working on this project reads this file first, then reads only their own numbered task file (`01_AGENT_SIGNALING_SERVER.md`, `02_AGENT_MACOS_HOST.md`, or `03_AGENT_IOS_CLIENT.md`). This file is the contract between the three pieces. If you think a contract needs to change, update this file and flag it — do not silently diverge, since the other two agents are building against exactly what's written here without seeing each other's code.

## 1. What we are building

A remote screen-viewing and remote-control system with exactly two endpoints:

- **macOS Host** — a Mac that shows its screen to, and accepts mouse/keyboard/touch input from, a paired iPhone. Runs continuously in the background (menu bar app).
- **iOS Controller** — an iPhone app that connects to a paired Mac, displays its screen live, and sends control input back.

It must work over the internet (not just LAN), so we route connection setup through a signaling server we operate, and stream video/input peer-to-peer over WebRTC, falling back to a TURN relay when a direct connection can't be established (roughly 10–15% of real-world networks, mostly symmetric NAT / restrictive corporate firewalls).

**Explicitly out of scope for this build**: Windows/Linux hosts, Android controller, iPhone-as-host. Don't build toward these; don't add abstraction layers "just in case" — that's wasted effort right now.

## 2. The three components and who builds what

| Component | Agent | Repo folder | Tech |
|---|---|---|---|
| Signaling server | Agent A | `signaling-server/` | Node.js + TypeScript |
| macOS host app | Agent B | `macos-host/` | Swift, SwiftUI, ScreenCaptureKit |
| iOS controller app | Agent C | `ios-client/` | Swift, SwiftUI |

All three talk to each other **only** through the contracts in section 4 below. Agent B and Agent C never call each other directly except via WebRTC once a session is established — everything before that goes through Agent A's server.

## 3. Repo layout

```
remote-desktop/
├── docs/
│   ├── 00_PROJECT_CONTEXT_AND_PROTOCOL.md   <- this file
│   ├── 01_AGENT_SIGNALING_SERVER.md
│   ├── 02_AGENT_MACOS_HOST.md
│   ├── 03_AGENT_IOS_CLIENT.md
│   └── 04_INTEGRATION_AND_QA.md
├── signaling-server/
├── macos-host/
└── ios-client/
```

Each agent works only inside their own top-level folder plus `docs/` (read-only except for their own file, and section 4 of this file if a contract genuinely needs to change).

## 4. Shared contracts (do not diverge from these)

### 4.1 Signaling protocol

Transport: a single WebSocket connection per device, `wss://<signaling-host>/ws`. All messages are JSON text frames with a mandatory `"type"` field.

**Device → Server:**

```json
{"type":"register","role":"host","deviceId":"<uuid>","deviceName":"Alex's MacBook Pro"}
{"type":"register","role":"controller","deviceId":"<uuid>","deviceName":"Alex's iPhone"}
{"type":"create_pairing_code"}
{"type":"pair","code":"482913","deviceId":"<uuid>","deviceName":"Alex's iPhone"}
{"type":"approve_pair","peerDeviceId":"<uuid>"}
{"type":"deny_pair","peerDeviceId":"<uuid>"}
{"type":"resume_session","authToken":"<jwt>","peerDeviceId":"<uuid>"}
{"type":"offer","targetDeviceId":"<uuid>","sdp":"<sdp string>"}
{"type":"answer","targetDeviceId":"<uuid>","sdp":"<sdp string>"}
{"type":"ice_candidate","targetDeviceId":"<uuid>","candidate":{"candidate":"...","sdpMid":"...","sdpMLineIndex":0}}
{"type":"end_session","targetDeviceId":"<uuid>"}
{"type":"request_turn_credentials"}
```

**Server → Device:**

```json
{"type":"registered","deviceId":"<uuid>"}
{"type":"pairing_code","code":"482913","expiresInSec":300}
{"type":"pair_request","fromDeviceId":"<uuid>","fromDeviceName":"Alex's iPhone"}
{"type":"paired","peerDeviceId":"<uuid>","peerDeviceName":"...","authToken":"<jwt>"}
{"type":"pair_denied"}
{"type":"pair_expired"}
{"type":"offer","fromDeviceId":"<uuid>","sdp":"..."}
{"type":"answer","fromDeviceId":"<uuid>","sdp":"..."}
{"type":"ice_candidate","fromDeviceId":"<uuid>","candidate":{...}}
{"type":"peer_disconnected","peerDeviceId":"<uuid>"}
{"type":"turn_credentials","urls":["turn:...","turns:..."],"username":"...","credential":"...","ttlSec":3600}
{"type":"error","code":"INVALID_CODE"|"CODE_EXPIRED"|"NOT_PAIRED"|"PEER_OFFLINE"|"BAD_TOKEN","message":"human readable"}
```

**Pairing flow (both agents must implement exactly this sequence):**

1. Host sends `create_pairing_code` → server replies `pairing_code`. Host displays it (and a QR code encoding it) in its UI.
2. Controller sends `pair` with that code → server forwards `pair_request` to host.
3. Host UI shows an approve/deny prompt → sends `approve_pair` or `deny_pair`.
4. On approval, server sends `paired` to **both** sides, each containing the other's `peerDeviceId`, plus an `authToken` each device stores locally (Keychain on both platforms) for that specific peer pairing.
5. On future connections, controller sends `resume_session` with the stored token instead of repeating the pairing-code flow. Host still gets a lightweight "X wants to connect" notification and a visible on-screen "being controlled" indicator once a session is live — never a silent, invisible connection.

**Who initiates the WebRTC offer**: the **controller** always creates the offer after receiving `paired` or after a successful `resume_session`. The host is always the answerer. This is fixed so both agents don't have to negotiate glare.

### 4.2 WebRTC session shape

- Exactly one video track: host = sender, controller = receiver only. Host never receives video.
- Exactly one data channel, label `"control"`, `ordered: true`, negotiated automatically (not pre-negotiated with hard-coded IDs).
- Codec preference: H.264 (both platforms hardware-encode/decode H.264 via VideoToolbox, so this avoids software fallback on either side).
- ICE servers: at least one STUN server plus the TURN credentials obtained from the signaling server via `turn_credentials` (see Agent A's file for the provider).

### 4.3 Data channel message schema (JSON per message, sent over the `"control"` channel)

Coordinates are **always normalized to [0.0, 1.0]** relative to the currently streamed display, never raw pixels — this decouples the iPhone's screen size from the Mac's resolution and Retina scale factor.

```json
{"type":"display_info","widthPx":3024,"heightPx":1964,"scaleFactor":2.0}
{"type":"mouse_move","x":0.534,"y":0.221}
{"type":"mouse_down","button":"left","x":0.534,"y":0.221}
{"type":"mouse_up","button":"left","x":0.534,"y":0.221}
{"type":"scroll","dx":0.0,"dy":-0.015}
{"type":"key_down","keyCode":53,"modifiers":["shift"]}
{"type":"key_up","keyCode":53,"modifiers":["shift"]}
{"type":"text_input","text":"hello world"}
```

- `display_info` is sent by the **host** immediately after the data channel opens, and again any time resolution or display selection changes. The controller must not send input before it has received at least one `display_info`.
- `text_input` exists so the iOS software keyboard can send whole strings for normal typing without the controller having to map every iOS key event to a macOS `keyCode`; the host synthesizes the individual key events. `key_down`/`key_up` with explicit `keyCode` are for modifier combos and special keys (arrows, cmd+C, etc.) triggered from a custom on-screen control bar, not the system keyboard.
- `keyCode` values are macOS virtual keycodes (the same integers used by `CGEventCreateKeyboardEvent`).

### 4.4 Auth model (appropriately scoped for a personal/small-scale tool, not enterprise IAM)

- The signaling server issues a JWT-style `authToken` per (host, controller) pairing at pairing time. Both sides store it (Keychain), and present it on `resume_session` to skip re-pairing.
- The host is the trust anchor for **session visibility**, not just connection: even with a valid token, the host always shows a brief "Alex's iPhone connected" toast and a persistent on-screen indicator while a session is active. There is no such thing as a silent remote session in this product.
- Signaling traffic is over `wss://` (TLS) always. Media/data channel traffic is DTLS-SRTP encrypted by WebRTC itself, end to end between the two devices — the signaling server never sees decrypted video or input.

## 5. Definition of done for the whole project (v1)

- [ ] Two paired devices can complete pairing entirely over the internet, on different networks (not same Wi-Fi), verified with real cellular data on the iPhone.
- [ ] Screen video is visible on the iPhone within ~2 seconds of session start, at usable framerate (target ≥ 20fps at consistent bitrate on a normal home connection).
- [ ] Touch on iPhone reliably moves the Mac cursor and clicks/drags the correct on-screen element.
- [ ] Typing via the iOS software keyboard produces correct characters on the Mac, including common modifier shortcuts (cmd+C/V, cmd+Tab) from a control bar.
- [ ] Killing Wi-Fi on the iPhone and switching to cellular mid-session recovers without a full re-pair.
- [ ] The Mac always visibly shows when it's being controlled, and a first-time pairing always requires explicit on-Mac approval.

## 6. Cross-agent order of operations

Agent A should be functionally complete (or at least stub-complete against the exact message contract above) before Agent B and Agent C try to integrate, since both depend on it. Agent B and Agent C can otherwise work in parallel — they only meet at the WebRTC layer, and that layer's shape is fully specified in section 4.2–4.3 above, so neither needs to see the other's code to build against it.
