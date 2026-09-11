import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { EventEmitter } from 'events';
import { SignalingWebSocketServer } from '../src/wsServer.js';
import { issueAuthToken, verifyAuthToken } from '../src/auth.js';
import type { OutboundMessage } from '../src/messages.js';

// Mock WebSocket class for testing without network sockets
class MockWebSocket extends EventEmitter {
  public readyState = 1; // OPEN
  public sentMessages: OutboundMessage[] = [];
  public isAlive = true;

  send(data: string): void {
    const parsed = JSON.parse(data) as OutboundMessage;
    this.sentMessages.push(parsed);
  }

  close(_code?: number, _reason?: string): void {
    this.readyState = 3; // CLOSED
    this.emit('close', _code || 1000, _reason || '');
  }

  terminate(): void {
    this.close(1006, 'Terminated');
  }

  ping(): void {
    this.emit('pong');
  }

  getLastMessage(): OutboundMessage | undefined {
    return this.sentMessages[this.sentMessages.length - 1];
  }

  clearMessages(): void {
    this.sentMessages = [];
  }
}

describe('Signaling Server Tests', () => {
  let server: SignalingWebSocketServer;

  beforeEach(() => {
    // Create server with no HTTP binding for unit testing
    server = new SignalingWebSocketServer({ noServer: true });
  });

  afterEach(async () => {
    await server.close();
  });

  describe('Device Registration', () => {
    it('registers host and controller successfully', async () => {
      const hostWs = new MockWebSocket();
      const ctrlWs = new MockWebSocket();

      await server.handleMessage(
        hostWs as any,
        Buffer.from(JSON.stringify({
          type: 'register',
          role: 'host',
          deviceId: 'host-1',
          deviceName: 'Alex’s MacBook Pro',
        }))
      );

      expect(hostWs.getLastMessage()).toEqual({
        type: 'registered',
        deviceId: 'host-1',
      });

      await server.handleMessage(
        ctrlWs as any,
        Buffer.from(JSON.stringify({
          type: 'register',
          role: 'controller',
          deviceId: 'ctrl-1',
          deviceName: 'Alex’s iPhone',
        }))
      );

      expect(ctrlWs.getLastMessage()).toEqual({
        type: 'registered',
        deviceId: 'ctrl-1',
      });

      expect(server.registry.count).toBe(2);
    });

    it('rejects unauthenticated message before registration', async () => {
      const ws = new MockWebSocket();

      await server.handleMessage(
        ws as any,
        Buffer.from(JSON.stringify({
          type: 'create_pairing_code',
        }))
      );

      const msg = ws.getLastMessage();
      expect(msg?.type).toBe('error');
      if (msg && msg.type === 'error') {
        expect(msg.code).toBe('UNREGISTERED');
      }
    });

    it('handles malformed JSON gracefully', async () => {
      const ws = new MockWebSocket();

      await server.handleMessage(ws as any, Buffer.from('NOT_VALID_JSON{foo'));

      const msg = ws.getLastMessage();
      expect(msg?.type).toBe('error');
      if (msg && msg.type === 'error') {
        expect(msg.code).toBe('INVALID_MESSAGE');
      }
    });

    it('handles invalid schema message gracefully', async () => {
      const ws = new MockWebSocket();

      await server.handleMessage(
        ws as any,
        Buffer.from(JSON.stringify({
          type: 'register',
          role: 'invalid_role',
          deviceId: 'dev-1',
        }))
      );

      const msg = ws.getLastMessage();
      expect(msg?.type).toBe('error');
      if (msg && msg.type === 'error') {
        expect(msg.code).toBe('INVALID_MESSAGE');
      }
    });
  });

  describe('Pairing Flow', () => {
    let hostWs: MockWebSocket;
    let ctrlWs: MockWebSocket;

    beforeEach(async () => {
      hostWs = new MockWebSocket();
      ctrlWs = new MockWebSocket();

      await server.handleMessage(
        hostWs as any,
        Buffer.from(JSON.stringify({
          type: 'register',
          role: 'host',
          deviceId: 'mac-host-1',
          deviceName: 'MacBook Pro',
        }))
      );

      await server.handleMessage(
        ctrlWs as any,
        Buffer.from(JSON.stringify({
          type: 'register',
          role: 'controller',
          deviceId: 'iphone-ctrl-1',
          deviceName: 'iPhone 15',
        }))
      );

      hostWs.clearMessages();
      ctrlWs.clearMessages();
    });

    it('creates 6-digit pairing code and expires in 300s', async () => {
      await server.handleMessage(
        hostWs as any,
        Buffer.from(JSON.stringify({
          type: 'create_pairing_code',
        }))
      );

      const msg = hostWs.getLastMessage();
      expect(msg?.type).toBe('pairing_code');
      if (msg && msg.type === 'pairing_code') {
        expect(msg.code).toMatch(/^\d{6}$/);
        expect(msg.expiresInSec).toBe(300);
      }
    });

    it('rejects pairing with invalid code', async () => {
      await server.handleMessage(
        ctrlWs as any,
        Buffer.from(JSON.stringify({
          type: 'pair',
          code: '000000',
          deviceId: 'iphone-ctrl-1',
          deviceName: 'iPhone 15',
        }))
      );

      const msg = ctrlWs.getLastMessage();
      expect(msg?.type).toBe('error');
      if (msg && msg.type === 'error') {
        expect(msg.code).toBe('INVALID_CODE');
      }
    });

    it('completes approval pairing flow successfully', async () => {
      // 1. Host creates code
      await server.handleMessage(
        hostWs as any,
        Buffer.from(JSON.stringify({
          type: 'create_pairing_code',
        }))
      );
      const codeMsg = hostWs.getLastMessage();
      expect(codeMsg?.type).toBe('pairing_code');
      const code = (codeMsg as any).code;

      // 2. Controller sends pair request with code
      await server.handleMessage(
        ctrlWs as any,
        Buffer.from(JSON.stringify({
          type: 'pair',
          code,
          deviceId: 'iphone-ctrl-1',
          deviceName: 'iPhone 15',
        }))
      );

      // Host receives pair_request
      const hostPairReq = hostWs.getLastMessage();
      expect(hostPairReq).toEqual({
        type: 'pair_request',
        fromDeviceId: 'iphone-ctrl-1',
        fromDeviceName: 'iPhone 15',
      });

      // 3. Host approves pair
      await server.handleMessage(
        hostWs as any,
        Buffer.from(JSON.stringify({
          type: 'approve_pair',
          peerDeviceId: 'iphone-ctrl-1',
        }))
      );

      // Both receive paired message with valid auth token
      const hostPaired = hostWs.getLastMessage();
      expect(hostPaired?.type).toBe('paired');
      if (hostPaired && hostPaired.type === 'paired') {
        expect(hostPaired.peerDeviceId).toBe('iphone-ctrl-1');
        expect(hostPaired.peerDeviceName).toBe('iPhone 15');
        expect(hostPaired.authToken).toBeDefined();

        const verified = verifyAuthToken(hostPaired.authToken);
        expect(verified).toEqual({
          hostDeviceId: 'mac-host-1',
          controllerDeviceId: 'iphone-ctrl-1',
        });
      }

      const ctrlPaired = ctrlWs.getLastMessage();
      expect(ctrlPaired?.type).toBe('paired');
      if (ctrlPaired && ctrlPaired.type === 'paired') {
        expect(ctrlPaired.peerDeviceId).toBe('mac-host-1');
        expect(ctrlPaired.peerDeviceName).toBe('MacBook Pro');
        expect(ctrlPaired.authToken).toBeDefined();
      }
    });

    it('completes deny pairing flow', async () => {
      // 1. Host creates code
      await server.handleMessage(
        hostWs as any,
        Buffer.from(JSON.stringify({
          type: 'create_pairing_code',
        }))
      );
      const code = (hostWs.getLastMessage() as any).code;

      // 2. Controller requests pair
      await server.handleMessage(
        ctrlWs as any,
        Buffer.from(JSON.stringify({
          type: 'pair',
          code,
          deviceId: 'iphone-ctrl-1',
          deviceName: 'iPhone 15',
        }))
      );

      // 3. Host denies pair
      await server.handleMessage(
        hostWs as any,
        Buffer.from(JSON.stringify({
          type: 'deny_pair',
          peerDeviceId: 'iphone-ctrl-1',
        }))
      );

      // Controller receives pair_denied
      const ctrlMsg = ctrlWs.getLastMessage();
      expect(ctrlMsg).toEqual({
        type: 'pair_denied',
      });
    });
  });

  describe('Session Resume', () => {
    let hostWs: MockWebSocket;
    let ctrlWs: MockWebSocket;
    let validToken: string;

    beforeEach(async () => {
      hostWs = new MockWebSocket();
      ctrlWs = new MockWebSocket();

      await server.handleMessage(
        hostWs as any,
        Buffer.from(JSON.stringify({
          type: 'register',
          role: 'host',
          deviceId: 'mac-host-1',
          deviceName: 'MacBook Pro',
        }))
      );

      await server.handleMessage(
        ctrlWs as any,
        Buffer.from(JSON.stringify({
          type: 'register',
          role: 'controller',
          deviceId: 'iphone-ctrl-1',
          deviceName: 'iPhone 15',
        }))
      );

      validToken = issueAuthToken('mac-host-1', 'iphone-ctrl-1');
      hostWs.clearMessages();
      ctrlWs.clearMessages();
    });

    it('resumes session with valid authToken without repeating pairing code flow', async () => {
      await server.handleMessage(
        ctrlWs as any,
        Buffer.from(JSON.stringify({
          type: 'resume_session',
          authToken: validToken,
          peerDeviceId: 'mac-host-1',
        }))
      );

      const ctrlMsg = ctrlWs.getLastMessage();
      expect(ctrlMsg?.type).toBe('paired');
      if (ctrlMsg && ctrlMsg.type === 'paired') {
        expect(ctrlMsg.peerDeviceId).toBe('mac-host-1');
        expect(ctrlMsg.peerDeviceName).toBe('MacBook Pro');
      }

      const hostMsg = hostWs.getLastMessage();
      expect(hostMsg?.type).toBe('paired');
      if (hostMsg && hostMsg.type === 'paired') {
        expect(hostMsg.peerDeviceId).toBe('iphone-ctrl-1');
        expect(hostMsg.peerDeviceName).toBe('iPhone 15');
      }
    });

    it('rejects resume_session with invalid/tampered token', async () => {
      await server.handleMessage(
        ctrlWs as any,
        Buffer.from(JSON.stringify({
          type: 'resume_session',
          authToken: 'bad-tampered-token-123',
          peerDeviceId: 'mac-host-1',
        }))
      );

      const ctrlMsg = ctrlWs.getLastMessage();
      expect(ctrlMsg?.type).toBe('error');
      if (ctrlMsg && ctrlMsg.type === 'error') {
        expect(ctrlMsg.code).toBe('BAD_TOKEN');
      }
    });

    it('rejects resume_session when peer device is offline', async () => {
      // Disconnect host
      server.registry.unregisterBySocket(hostWs as any);

      await server.handleMessage(
        ctrlWs as any,
        Buffer.from(JSON.stringify({
          type: 'resume_session',
          authToken: validToken,
          peerDeviceId: 'mac-host-1',
        }))
      );

      const ctrlMsg = ctrlWs.getLastMessage();
      expect(ctrlMsg?.type).toBe('error');
      if (ctrlMsg && ctrlMsg.type === 'error') {
        expect(ctrlMsg.code).toBe('PEER_OFFLINE');
      }
    });
  });

  describe('WebRTC Relay', () => {
    let hostWs: MockWebSocket;
    let ctrlWs: MockWebSocket;

    beforeEach(async () => {
      hostWs = new MockWebSocket();
      ctrlWs = new MockWebSocket();

      await server.handleMessage(
        hostWs as any,
        Buffer.from(JSON.stringify({
          type: 'register',
          role: 'host',
          deviceId: 'mac-host-1',
          deviceName: 'MacBook Pro',
        }))
      );

      await server.handleMessage(
        ctrlWs as any,
        Buffer.from(JSON.stringify({
          type: 'register',
          role: 'controller',
          deviceId: 'iphone-ctrl-1',
          deviceName: 'iPhone 15',
        }))
      );

      hostWs.clearMessages();
      ctrlWs.clearMessages();
    });

    it('relays offer from controller to host', async () => {
      const mockSdp = 'v=0\r\no=- 123456 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n';
      await server.handleMessage(
        ctrlWs as any,
        Buffer.from(JSON.stringify({
          type: 'offer',
          targetDeviceId: 'mac-host-1',
          sdp: mockSdp,
        }))
      );

      const hostMsg = hostWs.getLastMessage();
      expect(hostMsg).toEqual({
        type: 'offer',
        fromDeviceId: 'iphone-ctrl-1',
        sdp: mockSdp,
      });
    });

    it('relays answer from host to controller', async () => {
      const mockSdp = 'v=0\r\no=- 654321 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n';
      await server.handleMessage(
        hostWs as any,
        Buffer.from(JSON.stringify({
          type: 'answer',
          targetDeviceId: 'iphone-ctrl-1',
          sdp: mockSdp,
        }))
      );

      const ctrlMsg = ctrlWs.getLastMessage();
      expect(ctrlMsg).toEqual({
        type: 'answer',
        fromDeviceId: 'mac-host-1',
        sdp: mockSdp,
      });
    });

    it('relays ice_candidate between peers', async () => {
      const mockCandidate = {
        candidate: 'candidate:842163049 1 udp 1677729535 192.168.1.100 56143 typ host',
        sdpMid: '0',
        sdpMLineIndex: 0,
      };

      await server.handleMessage(
        ctrlWs as any,
        Buffer.from(JSON.stringify({
          type: 'ice_candidate',
          targetDeviceId: 'mac-host-1',
          candidate: mockCandidate,
        }))
      );

      const hostMsg = hostWs.getLastMessage();
      expect(hostMsg).toEqual({
        type: 'ice_candidate',
        fromDeviceId: 'iphone-ctrl-1',
        candidate: mockCandidate,
      });
    });

    it('handles explicit end_session and notifies target', async () => {
      await server.handleMessage(
        ctrlWs as any,
        Buffer.from(JSON.stringify({
          type: 'end_session',
          targetDeviceId: 'mac-host-1',
        }))
      );

      const hostMsg = hostWs.getLastMessage();
      expect(hostMsg).toEqual({
        type: 'peer_disconnected',
        peerDeviceId: 'iphone-ctrl-1',
      });
    });
  });

  describe('TURN Credentials', () => {
    it('returns TURN/STUN credentials upon request', async () => {
      const ws = new MockWebSocket();
      await server.handleMessage(
        ws as any,
        Buffer.from(JSON.stringify({
          type: 'register',
          role: 'host',
          deviceId: 'host-turn-test',
          deviceName: 'Mac',
        }))
      );

      ws.clearMessages();

      await server.handleMessage(
        ws as any,
        Buffer.from(JSON.stringify({
          type: 'request_turn_credentials',
        }))
      );

      const msg = ws.getLastMessage();
      expect(msg?.type).toBe('turn_credentials');
      if (msg && msg.type === 'turn_credentials') {
        expect(Array.isArray(msg.urls)).toBe(true);
        expect(msg.urls.length).toBeGreaterThan(0);
        expect(msg.username).toBeDefined();
        expect(msg.credential).toBeDefined();
        expect(msg.ttlSec).toBeGreaterThan(0);
      }
    });
  });
});
