import { spawn, ChildProcess } from 'child_process';
import { WebSocket } from 'ws';

const SIGNALING_PORT = 8899;
const SIGNALING_URL = `ws://localhost:${SIGNALING_PORT}/ws`;

interface TestStep {
  name: string;
  run: () => Promise<void>;
}

async function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

class TestClient {
  public ws!: WebSocket;
  private messageQueue: any[] = [];
  private messageWaiters: ((msg: any) => void)[] = [];

  constructor(public role: 'host' | 'controller', public deviceId: string, public deviceName: string) {}

  public connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(SIGNALING_URL);
      this.ws.on('open', () => {
        // Register immediately
        this.send({
          type: 'register',
          role: this.role,
          deviceId: this.deviceId,
          deviceName: this.deviceName,
        });
        resolve();
      });

      this.ws.on('message', (data) => {
        const parsed = JSON.parse(data.toString());
        if (this.messageWaiters.length > 0) {
          const waiter = this.messageWaiters.shift()!;
          waiter(parsed);
        } else {
          this.messageQueue.push(parsed);
        }
      });

      this.ws.on('error', reject);
    });
  }

  public send(msg: any) {
    this.ws.send(JSON.stringify(msg));
  }

  public waitForMessage(timeoutMs = 5000): Promise<any> {
    return new Promise((resolve, reject) => {
      if (this.messageQueue.length > 0) {
        return resolve(this.messageQueue.shift());
      }
      const timer = setTimeout(() => {
        const idx = this.messageWaiters.indexOf(resolve);
        if (idx !== -1) this.messageWaiters.splice(idx, 1);
        reject(new Error(`Timeout waiting for message on ${this.role} (${this.deviceId})`));
      }, timeoutMs);

      this.messageWaiters.push((msg) => {
        clearTimeout(timer);
        resolve(msg);
      });
    });
  }

  public close() {
    this.ws.close();
  }
}

async function main() {
  console.log('🚀 Starting Full-System End-to-End Integration Test Suite...\n');

  // 1. Start Signaling Server
  console.log('1️⃣ Starting Signaling Server on port', SIGNALING_PORT, '...');
  const serverProcess = spawn('npx', ['tsx', 'src/index.ts'], {
    cwd: process.cwd(),
    env: { ...process.env, PORT: String(SIGNALING_PORT), LOG_LEVEL: 'warn' },
    stdio: 'inherit',
  });

  // Wait for server to start
  await sleep(1500);

  // Verify health check
  try {
    const healthRes = await fetch(`http://localhost:${SIGNALING_PORT}/health`);
    const healthData = await healthRes.json();
    console.log('   ✓ Health check responded:', JSON.stringify(healthData));
  } catch (err) {
    console.error('   ❌ Failed to connect to health endpoint:', err);
    serverProcess.kill();
    process.exit(1);
  }

  let hostClient: TestClient;
  let ctrlClient: TestClient;
  let issuedAuthToken = '';

  const steps: TestStep[] = [
    {
      name: 'Register Host & Controller',
      run: async () => {
        hostClient = new TestClient('host', 'mac-host-e2e', "Alex's MacBook Pro");
        ctrlClient = new TestClient('controller', 'ios-ctrl-e2e', "Alex's iPhone");

        await hostClient.connect();
        const hostReg = await hostClient.waitForMessage();
        if (hostReg.type !== 'registered' || hostReg.deviceId !== 'mac-host-e2e') {
          throw new Error(`Unexpected host reg: ${JSON.stringify(hostReg)}`);
        }

        await ctrlClient.connect();
        const ctrlReg = await ctrlClient.waitForMessage();
        if (ctrlReg.type !== 'registered' || ctrlReg.deviceId !== 'ios-ctrl-e2e') {
          throw new Error(`Unexpected ctrl reg: ${JSON.stringify(ctrlReg)}`);
        }
      },
    },
    {
      name: 'Pairing Flow: Code Generation, Approval & Token Issuance',
      run: async () => {
        // Host requests pairing code
        hostClient.send({ type: 'create_pairing_code' });
        const codeMsg = await hostClient.waitForMessage();
        if (codeMsg.type !== 'pairing_code' || !codeMsg.code || codeMsg.expiresInSec !== 300) {
          throw new Error(`Invalid code response: ${JSON.stringify(codeMsg)}`);
        }
        const pairingCode = codeMsg.code;

        // Controller sends pair request
        ctrlClient.send({
          type: 'pair',
          code: pairingCode,
          deviceId: ctrlClient.deviceId,
          deviceName: ctrlClient.deviceName,
        });

        // Host receives pair_request
        const pairReq = await hostClient.waitForMessage();
        if (pairReq.type !== 'pair_request' || pairReq.fromDeviceId !== ctrlClient.deviceId) {
          throw new Error(`Invalid pair request: ${JSON.stringify(pairReq)}`);
        }

        // Host approves pairing
        hostClient.send({
          type: 'approve_pair',
          peerDeviceId: ctrlClient.deviceId,
        });

        // Both receive paired message
        const hostPaired = await hostClient.waitForMessage();
        const ctrlPaired = await ctrlClient.waitForMessage();

        if (hostPaired.type !== 'paired' || ctrlPaired.type !== 'paired') {
          throw new Error('Did not receive paired messages');
        }
        if (!hostPaired.authToken || hostPaired.authToken !== ctrlPaired.authToken) {
          throw new Error('Mismatched authTokens');
        }
        issuedAuthToken = hostPaired.authToken;
      },
    },
    {
      name: 'WebRTC Signaling Relay: SDP Offer, Answer, and ICE Candidate',
      run: async () => {
        // Controller sends offer
        const mockOfferSdp = 'v=0\r\no=- 1001 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\n';
        ctrlClient.send({
          type: 'offer',
          targetDeviceId: hostClient.deviceId,
          sdp: mockOfferSdp,
        });

        const relayedOffer = await hostClient.waitForMessage();
        if (relayedOffer.type !== 'offer' || relayedOffer.fromDeviceId !== ctrlClient.deviceId) {
          throw new Error(`Invalid relayed offer: ${JSON.stringify(relayedOffer)}`);
        }

        // Host sends answer
        const mockAnswerSdp = 'v=0\r\no=- 1002 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\n';
        hostClient.send({
          type: 'answer',
          targetDeviceId: ctrlClient.deviceId,
          sdp: mockAnswerSdp,
        });

        const relayedAnswer = await ctrlClient.waitForMessage();
        if (relayedAnswer.type !== 'answer' || relayedAnswer.fromDeviceId !== hostClient.deviceId) {
          throw new Error(`Invalid relayed answer: ${JSON.stringify(relayedAnswer)}`);
        }

        // Controller sends ICE candidate
        const mockCandidate = { candidate: 'candidate:1 1 UDP 2130706431 192.168.1.1 50000 typ host', sdpMid: '0', sdpMLineIndex: 0 };
        ctrlClient.send({
          type: 'ice_candidate',
          targetDeviceId: hostClient.deviceId,
          candidate: mockCandidate,
        });

        const relayedIce = await hostClient.waitForMessage();
        if (relayedIce.type !== 'ice_candidate' || relayedIce.fromDeviceId !== ctrlClient.deviceId) {
          throw new Error(`Invalid relayed ICE candidate: ${JSON.stringify(relayedIce)}`);
        }
      },
    },
    {
      name: 'TURN Credentials Retrieval',
      run: async () => {
        ctrlClient.send({ type: 'request_turn_credentials' });
        const credsMsg = await ctrlClient.waitForMessage();
        if (credsMsg.type !== 'turn_credentials' || !Array.isArray(credsMsg.urls) || credsMsg.urls.length === 0) {
          throw new Error(`Invalid turn credentials: ${JSON.stringify(credsMsg)}`);
        }
      },
    },
    {
      name: 'Session Disconnection & Peer Notification',
      run: async () => {
        ctrlClient.close();
        const disconnectMsg = await hostClient.waitForMessage();
        if (disconnectMsg.type !== 'peer_disconnected' || disconnectMsg.peerDeviceId !== ctrlClient.deviceId) {
          throw new Error(`Invalid peer_disconnected notification: ${JSON.stringify(disconnectMsg)}`);
        }
      },
    },
    {
      name: 'Session Resumption using Stored JWT Auth Token',
      run: async () => {
        const reconnectedCtrl = new TestClient('controller', 'ios-ctrl-e2e', "Alex's iPhone");
        await reconnectedCtrl.connect();
        await reconnectedCtrl.waitForMessage(); // registered

        // Send resume_session with authToken
        reconnectedCtrl.send({
          type: 'resume_session',
          authToken: issuedAuthToken,
          peerDeviceId: hostClient.deviceId,
        });

        const ctrlResumed = await reconnectedCtrl.waitForMessage();
        const hostResumed = await hostClient.waitForMessage();

        if (ctrlResumed.type !== 'paired' || hostResumed.type !== 'paired') {
          throw new Error('Failed to resume session with stored token');
        }

        reconnectedCtrl.close();
        hostClient.close();
      },
    },
  ];

  let passed = 0;
  for (let i = 0; i < steps.length; i++) {
    const step = steps[i];
    process.stdout.write(`  [${i + 1}/${steps.length}] ${step.name}... `);
    try {
      await step.run();
      console.log('✅ PASSED');
      passed++;
    } catch (err) {
      console.log('❌ FAILED');
      console.error('    Error:', err);
    }
  }

  serverProcess.kill('SIGTERM');

  console.log(`\n=================================================`);
  console.log(`📊 Integration Result: ${passed}/${steps.length} Steps Passed`);
  console.log(`=================================================\n`);

  if (passed === steps.length) {
    console.log('🎉 Full End-to-End System Integration Verified Successfully!');
    process.exit(0);
  } else {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error('Fatal test error:', err);
  process.exit(1);
});
