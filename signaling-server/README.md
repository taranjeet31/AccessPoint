# WebRTC Signaling Server

Signaling, pairing, and TURN credential broker for macOS Host and iOS Controller remote desktop sessions.

## Features

- **Strict Protocol Compliance**: Implements the exact message shapes from `docs/00_PROJECT_CONTEXT_AND_PROTOCOL.md`.
- **In-Memory Pairing State Machine**: 6-digit expiring pairing codes (5-minute TTL) with explicit approve/deny flow.
- **Resumable Sessions**: Secure long-lived JWT `authToken` issuance and verification.
- **Transparent WebRTC Relay**: Zero-inspection relay for `offer`, `answer`, `ice_candidate`, and session lifecycle events.
- **TURN Credentials Service**: Proxies and caches short-lived credentials from managed providers (Metered.ca / Open Relay / Twilio) with fallback STUN/TURN support.
- **Structured Logging & Resilience**: Pino logger with redacted sensitive payloads, malformed JSON protection, and ping/pong heartbeats.
- **Zero-Dependency Docker Container**: Multi-stage lightweight Alpine image ready for Fly.io / Railway / Render.

## Quick Start

### 1. Install dependencies
```bash
npm install
```

### 2. Configure environment
```bash
cp .env.example .env
```

### 3. Run development server
```bash
npm run dev
```

The server starts on `http://localhost:8080` with:
- **WebSocket Signaling Endpoint**: `ws://localhost:8080/ws`
- **HTTP Health Check**: `http://localhost:8080/health`

### 4. Run tests
```bash
npm test
```

### 5. Build for production
```bash
npm run build
npm start
```

## Docker Deployment

Build and run with Docker:
```bash
docker build -t signaling-server .
docker run -p 8080:8080 -e JWT_SECRET=your_jwt_secret signaling-server
```
