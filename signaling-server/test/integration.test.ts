import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import http from 'http';
import express from 'express';
import { WebSocket } from 'ws';
import { SignalingWebSocketServer } from '../src/wsServer.js';
import type { OutboundMessage } from '../src/messages.js';

describe('End-to-End WebSocket Integration Tests', () => {
  let server: http.Server;
  let wsServer: SignalingWebSocketServer;
  let port: number;
  let serverUrl: string;

  beforeAll(async () => {
    const app = express();
    server = http.createServer(app);
    wsServer = new SignalingWebSocketServer({ server, path: '/ws' });

    app.get('/health', (_req, res) => {
      res.status(200).json({ status: 'ok', connections: wsServer.registry.count });
    });

    await new Promise<void>((resolve) => {
      server.listen(0, () => {
        const address = server.address();
        if (typeof address === 'object' && address) {
          port = address.port;
          serverUrl = `ws://localhost:${port}/ws`;
        }
        resolve();
      });
    });
  });

  afterAll(async () => {
    await wsServer.close();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  });

  function createClient(): Promise<{
    ws: WebSocket;
    nextMessage: () => Promise<OutboundMessage>;
    close: () => void;
  }> {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(serverUrl);
      const queue: OutboundMessage[] = [];
      const waiters: ((msg: OutboundMessage) => void)[] = [];

      ws.on('open', () => {
        resolve({
          ws,
          nextMessage: () => {
            return new Promise((res) => {
              if (queue.length > 0) {
                res(queue.shift()!);
              } else {
                waiters.push(res);
              }
            });
          },
          close: () => ws.close(),
        });
      });

      ws.on('message', (data) => {
        const parsed = JSON.parse(data.toString()) as OutboundMessage;
        if (waiters.length > 0) {
          const waiter = waiters.shift()!;
          waiter(parsed);
        } else {
          queue.push(parsed);
        }
      });

      ws.on('error', reject);
    });
  }

  it('performs full end-to-end pairing, relay, resume, and disconnect over real WebSockets', async () => {
    // 1. Check HTTP Health check
    const healthRes = await fetch(`http://localhost:${port}/health`);
    const healthJson = await healthRes.json();
    expect(healthJson.status).toBe('ok');

    // 2. Connect Host and Controller
    const hostClient = await createClient();
    const ctrlClient = await createClient();

    // Register host
    hostClient.ws.send(JSON.stringify({
      type: 'register',
      role: 'host',
      deviceId: 'macbook-e2e-1',
      deviceName: 'Alex’s Mac Studio',
    }));
    const hostRegMsg = await hostClient.nextMessage();
    expect(hostRegMsg).toEqual({ type: 'registered', deviceId: 'macbook-e2e-1' });

    // Register controller
    ctrlClient.ws.send(JSON.stringify({
      type: 'register',
      role: 'controller',
      deviceId: 'iphone-e2e-1',
      deviceName: 'Alex’s iPhone 16 Pro',
    }));
    const ctrlRegMsg = await ctrlClient.nextMessage();
    expect(ctrlRegMsg).toEqual({ type: 'registered', deviceId: 'iphone-e2e-1' });

    // 3. Host creates pairing code
    hostClient.ws.send(JSON.stringify({ type: 'create_pairing_code' }));
    const pairCodeMsg = (await hostClient.nextMessage()) as any;
    expect(pairCodeMsg.type).toBe('pairing_code');
    expect(pairCodeMsg.code).toHaveLength(6);

    // 4. Controller pairs with code
    ctrlClient.ws.send(JSON.stringify({
      type: 'pair',
      code: pairCodeMsg.code,
      deviceId: 'iphone-e2e-1',
      deviceName: 'Alex’s iPhone 16 Pro',
    }));

    // Host receives pair_request
    const pairReqMsg = (await hostClient.nextMessage()) as any;
    expect(pairReqMsg).toEqual({
      type: 'pair_request',
      fromDeviceId: 'iphone-e2e-1',
      fromDeviceName: 'Alex’s iPhone 16 Pro',
    });

    // 5. Host approves pairing
    hostClient.ws.send(JSON.stringify({
      type: 'approve_pair',
      peerDeviceId: 'iphone-e2e-1',
    }));

    // Both receive paired message
    const hostPairedMsg = (await hostClient.nextMessage()) as any;
    const ctrlPairedMsg = (await ctrlClient.nextMessage()) as any;

    expect(hostPairedMsg.type).toBe('paired');
    expect(hostPairedMsg.peerDeviceId).toBe('iphone-e2e-1');
    expect(hostPairedMsg.authToken).toBeDefined();

    expect(ctrlPairedMsg.type).toBe('paired');
    expect(ctrlPairedMsg.peerDeviceId).toBe('macbook-e2e-1');
    expect(ctrlPairedMsg.authToken).toBeDefined();

    const storedAuthToken = ctrlPairedMsg.authToken;

    // 6. WebRTC Relay: Controller sends offer
    const offerSdp = 'v=0\r\no=- 42 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n';
    ctrlClient.ws.send(JSON.stringify({
      type: 'offer',
      targetDeviceId: 'macbook-e2e-1',
      sdp: offerSdp,
    }));
    const relayedOffer = (await hostClient.nextMessage()) as any;
    expect(relayedOffer).toEqual({
      type: 'offer',
      fromDeviceId: 'iphone-e2e-1',
      sdp: offerSdp,
    });

    // WebRTC Relay: Host sends answer
    const answerSdp = 'v=0\r\no=- 43 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n';
    hostClient.ws.send(JSON.stringify({
      type: 'answer',
      targetDeviceId: 'iphone-e2e-1',
      sdp: answerSdp,
    }));
    const relayedAnswer = (await ctrlClient.nextMessage()) as any;
    expect(relayedAnswer).toEqual({
      type: 'answer',
      fromDeviceId: 'macbook-e2e-1',
      sdp: answerSdp,
    });

    // WebRTC Relay: Controller sends ice candidate
    const candidateObj = { candidate: 'candidate:1 1 UDP 2130706431 192.168.1.50 50000 typ host', sdpMid: '0', sdpMLineIndex: 0 };
    ctrlClient.ws.send(JSON.stringify({
      type: 'ice_candidate',
      targetDeviceId: 'macbook-e2e-1',
      candidate: candidateObj,
    }));
    const relayedCandidate = (await hostClient.nextMessage()) as any;
    expect(relayedCandidate).toEqual({
      type: 'ice_candidate',
      fromDeviceId: 'iphone-e2e-1',
      candidate: candidateObj,
    });

    // 7. Request TURN credentials
    ctrlClient.ws.send(JSON.stringify({ type: 'request_turn_credentials' }));
    const turnMsg = (await ctrlClient.nextMessage()) as any;
    expect(turnMsg.type).toBe('turn_credentials');
    expect(turnMsg.urls.length).toBeGreaterThan(0);

    // 8. Controller disconnects -> Host receives peer_disconnected
    ctrlClient.close();
    const disconnectMsg = (await hostClient.nextMessage()) as any;
    expect(disconnectMsg).toEqual({
      type: 'peer_disconnected',
      peerDeviceId: 'iphone-e2e-1',
    });

    // 9. Controller reconnects and resumes session using stored authToken
    const ctrlReconnected = await createClient();
    ctrlReconnected.ws.send(JSON.stringify({
      type: 'register',
      role: 'controller',
      deviceId: 'iphone-e2e-1',
      deviceName: 'Alex’s iPhone 16 Pro',
    }));
    await ctrlReconnected.nextMessage(); // registered

    ctrlReconnected.ws.send(JSON.stringify({
      type: 'resume_session',
      authToken: storedAuthToken,
      peerDeviceId: 'macbook-e2e-1',
    }));

    const ctrlResumedMsg = (await ctrlReconnected.nextMessage()) as any;
    const hostResumedMsg = (await hostClient.nextMessage()) as any;

    expect(ctrlResumedMsg.type).toBe('paired');
    expect(ctrlResumedMsg.peerDeviceId).toBe('macbook-e2e-1');

    expect(hostResumedMsg.type).toBe('paired');
    expect(hostResumedMsg.peerDeviceId).toBe('iphone-e2e-1');

    // 10. Malformed payload resiliency test
    ctrlReconnected.ws.send('GARBAGE_PAYLOAD');
    const errMsg = (await ctrlReconnected.nextMessage()) as any;
    expect(errMsg.type).toBe('error');
    expect(errMsg.code).toBe('INVALID_MESSAGE');

    // Verify socket connection remains alive and functional after error
    ctrlReconnected.ws.send(JSON.stringify({ type: 'request_turn_credentials' }));
    const turnAfterError = (await ctrlReconnected.nextMessage()) as any;
    expect(turnAfterError.type).toBe('turn_credentials');

    // Cleanup
    hostClient.close();
    ctrlReconnected.close();
  });
});
