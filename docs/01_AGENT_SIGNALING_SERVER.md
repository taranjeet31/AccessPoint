# Agent A — Signaling Server

**Read `00_PROJECT_CONTEXT_AND_PROTOCOL.md` in full before starting.** Everything you build must match section 4.1 and 4.4 of that file exactly — you are the only agent that both other agents depend on, and they are building against the message contract, not your code.

## Your job, in one sentence

Build and deploy a small WebSocket server that lets a Mac and an iPhone find each other, pair, exchange WebRTC connection info, and get TURN credentials — and otherwise stays out of the way (no video/input ever touches this server).

## Tech stack

- Node.js 20+, TypeScript
- `ws` for the WebSocket server (not Socket.IO — we want raw control over the message shape, no extra framing)
- `express` for a tiny HTTP surface (health check only)
- `jsonwebtoken` for issuing/verifying `authToken`
- `nanoid` for device IDs and pairing codes
- `pino` for structured logging
- In-memory state (a couple of `Map`s) for v1 — this is a single-instance server for now; do not add Redis/DB unless asked, it's unneeded complexity at this scale
- TURN credentials: use a managed provider so you don't have to operate `coturn` yourself yet. Metered.ca's "Open Relay" free tier or Twilio's Network Traversal Service both expose an API that returns short-lived TURN credentials — pick one, put the API key in an env var, and implement `request_turn_credentials` as a thin proxy to it.

## File structure to create

```
signaling-server/
├── src/
│   ├── index.ts              # entrypoint: HTTP server + WS upgrade
│   ├── wsServer.ts           # WebSocket connection handling
│   ├── deviceRegistry.ts     # in-memory maps: deviceId -> ws connection, pairing state
│   ├── pairing.ts            # pairing code generation/validation, approve/deny flow
│   ├── relay.ts              # offer/answer/ice_candidate relay logic
│   , auth.ts               # JWT issuing/verification for authToken
│   ├── turn.ts                # fetches/proxies TURN credentials from provider
│   ├── messages.ts            # TypeScript types for every message in the protocol doc
│   └── logger.ts
├── test/
│   └── pairing.test.ts
├── Dockerfile
├── package.json
├── tsconfig.json
└── .env.example
```

## Step-by-step build order

### Step 1 — Scaffold
- `npm init`, TypeScript config targeting Node 20, `ws`, `express`, `jsonwebtoken`, `nanoid`, `pino`, `dotenv`.
- `src/index.ts`: an Express app with a single `GET /health` returning `200 ok`, and an HTTP server that Express and the WebSocket server share (so both run on one port — simplifies deployment).
- Confirm it boots locally and `curl localhost:PORT/health` works before writing any WebSocket code.

### Step 2 — Message types
- In `messages.ts`, write TypeScript discriminated union types for every message listed in section 4.1 of the protocol doc, both directions. This is your single source of truth for parsing — every inbound message gets validated against these types (reject anything that doesn't match with an `error` message, don't silently ignore malformed input).

### Step 3 — Device registry
- `deviceRegistry.ts`: a `Map<deviceId, { ws: WebSocket, role: 'host'|'controller', deviceName: string }>`.
- On WebSocket connection, wait for a `register` message before doing anything else; reject any other first message.
- On socket close, remove the device from the registry and, if it was mid-session with a peer, send that peer a `peer_disconnected`.

### Step 4 — Pairing flow
- `pairing.ts`: a `Map<code, { hostDeviceId, expiresAt }>`. Codes are 6-digit numeric, generated with `nanoid`'s custom alphabet, expire after 5 minutes.
- Implement the exact 5-step flow from protocol doc section 4.1: `create_pairing_code` → `pairing_code`; `pair` → `pair_request` to host; `approve_pair`/`deny_pair` → `paired` (both sides) or `pair_denied`.
- On `paired`, call into `auth.ts` to mint an `authToken` (JWT) whose payload is `{hostDeviceId, controllerDeviceId}`, signed with a server-side secret from env, long expiry (e.g. 1 year — re-pairing should be rare, not routine).
- Implement `resume_session`: verify the JWT, confirm both device IDs match the token payload, and if valid treat it as equivalent to a fresh `paired` message (skip the approve/deny prompt on the host **transport-wise**, but the host app itself still shows its own UI toast per section 4.4 — that's the host agent's job, not yours).

### Step 5 — Relay logic
- `relay.ts`: for `offer`, `answer`, `ice_candidate` — look up `targetDeviceId` in the registry, and if found and online, forward the message verbatim to that device's socket with a `fromDeviceId` field added. If not found/offline, reply to the sender with `error: PEER_OFFLINE`.
- This file should contain zero WebRTC-specific logic — you are a dumb pipe. Do not attempt to parse or validate SDP content.

### Step 6 — TURN credentials
- `turn.ts`: on `request_turn_credentials`, call your chosen provider's API server-side (never expose the provider's permanent API key to clients) and return short-lived credentials via the `turn_credentials` message.
- Cache and reuse credentials for a given device within their TTL rather than hitting the provider API on every request.

### Step 7 — Logging & error handling
- Every inbound message gets logged at debug level with deviceId and type (never log SDP or ICE candidate contents at info level — they're not secret exactly, but there's no reason to spam logs with them).
- Wrap all message handling in try/catch; a malformed message from one client must never crash the process or affect other connected clients.

### Step 8 — Tests
- Unit test the pairing state machine directly (no real WebSocket needed — inject fake socket objects) covering: normal pairing success, expired code, wrong code, deny, resume with valid token, resume with tampered/expired token.
- A manual integration test script using two `wscat` sessions is enough for the relay path at this stage — full end-to-end is what Agent B/C integration testing (see `04_INTEGRATION_AND_QA.md`) will cover.

### Step 9 — Deployment
- `Dockerfile`: multi-stage build (build TypeScript, then a slim runtime image running compiled JS).
- Deploy target: Fly.io or Railway are both good fits for a small always-on WebSocket service with minimal ops — pick either; both give you TLS termination for free so you only need to bind plain `ws://` internally and it becomes `wss://` externally.
- Env vars needed: `PORT`, `JWT_SECRET`, `TURN_PROVIDER_API_KEY`, `NODE_ENV`.
- Confirm `wss://<your-fly-app>.fly.dev/ws` is reachable from outside before handing off to Agent B/C for integration.

## Acceptance criteria (what "done" means for this agent)

- [ ] Two separate `wscat -c wss://.../ws` sessions can complete the full pairing handshake by hand-typing the JSON messages from the protocol doc.
- [ ] Killing one wscat session sends `peer_disconnected` to the other.
- [ ] An expired or wrong pairing code returns the correct `error` code.
- [ ] `resume_session` with a valid stored token succeeds without repeating the pairing-code step.
- [ ] `request_turn_credentials` returns real, usable TURN credentials (verify with `trickle-ice` test page or similar, not just "the API didn't error").
- [ ] Server survives a malformed/garbage message on one connection without dropping other connections.
