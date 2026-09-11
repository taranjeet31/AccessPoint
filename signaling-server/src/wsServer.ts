import { WebSocketServer, WebSocket, type RawData } from 'ws';
import type { Server } from 'http';
import { DeviceRegistry } from './deviceRegistry.js';
import { PairingManager } from './pairing.js';
import { RelayManager } from './relay.js';
import { TurnManager } from './turn.js';
import { InboundMessageSchema, type InboundMessage, type OutboundMessage } from './messages.js';
import { logger } from './logger.js';

export interface WebSocketServerOptions {
  server?: Server;
  path?: string;
  noServer?: boolean;
}

export class SignalingWebSocketServer {
  public wss: WebSocketServer;
  public registry: DeviceRegistry;
  public pairingManager: PairingManager;
  public relayManager: RelayManager;
  public turnManager: TurnManager;
  private heartbeatInterval: NodeJS.Timeout | null = null;

  constructor(options?: WebSocketServerOptions) {
    this.registry = new DeviceRegistry();
    this.pairingManager = new PairingManager(this.registry);
    this.relayManager = new RelayManager(this.registry);
    this.turnManager = new TurnManager();

    this.wss = new WebSocketServer({
      server: options?.server,
      path: options?.path ?? '/ws',
      noServer: options?.noServer,
    });

    this.setupServer();
    this.setupHeartbeat();
  }

  private setupServer(): void {
    this.wss.on('connection', (ws: WebSocket) => {
      // Mark as alive for heartbeat
      (ws as unknown as { isAlive: boolean }).isAlive = true;

      ws.on('pong', () => {
        (ws as unknown as { isAlive: boolean }).isAlive = true;
      });

      logger.debug('New WebSocket connection established');

      ws.on('message', async (raw: RawData) => {
        try {
          await this.handleMessage(ws, raw);
        } catch (err) {
          logger.error({ err }, 'Unhandled error processing WebSocket message');
          this.sendError(ws, 'INVALID_MESSAGE', 'Internal server error processing message');
        }
      });

      ws.on('close', (code, reason) => {
        this.handleDisconnect(ws, code, reason.toString());
      });

      ws.on('error', (err) => {
        logger.error({ err }, 'WebSocket connection error');
      });
    });
  }

  private setupHeartbeat(): void {
    this.heartbeatInterval = setInterval(() => {
      this.wss.clients.forEach((ws) => {
        const socketWithAlive = ws as unknown as { isAlive: boolean };
        if (socketWithAlive.isAlive === false) {
          logger.debug('Terminating inactive WebSocket client');
          return ws.terminate();
        }
        socketWithAlive.isAlive = false;
        ws.ping();
      });
    }, 30000);
  }

  /**
   * Dispatches inbound WebSocket message.
   */
  public async handleMessage(ws: WebSocket, rawData: RawData): Promise<void> {
    const rawString = rawData.toString();
    let json: unknown;

    try {
      json = JSON.parse(rawString);
    } catch {
      logger.warn({ raw: rawString.slice(0, 100) }, 'Invalid JSON received');
      this.sendError(ws, 'INVALID_MESSAGE', 'Malformed JSON payload');
      return;
    }

    const parseResult = InboundMessageSchema.safeParse(json);
    if (!parseResult.success) {
      logger.warn({ errors: parseResult.error.format() }, 'Message failed schema validation');
      this.sendError(
        ws,
        'INVALID_MESSAGE',
        `Validation failed: ${parseResult.error.errors.map((e) => `${e.path.join('.')}: ${e.message}`).join(', ')}`
      );
      return;
    }

    const message: InboundMessage = parseResult.data;
    const existingDevice = this.registry.getBySocket(ws);

    // If socket is not registered yet, only 'register' is allowed
    if (!existingDevice && message.type !== 'register') {
      logger.warn({ messageType: message.type }, 'Unregistered socket attempted to send message');
      this.sendError(ws, 'UNREGISTERED', 'Device must register before sending other messages');
      return;
    }

    logger.debug(
      {
        type: message.type,
        deviceId: existingDevice?.deviceId || (message.type === 'register' ? message.deviceId : 'unknown'),
      },
      'Processing inbound message'
    );

    switch (message.type) {
      case 'register': {
        this.registry.register(message.deviceId, message.role, message.deviceName, ws);
        this.send(ws, {
          type: 'registered',
          deviceId: message.deviceId,
        });
        break;
      }

      case 'create_pairing_code': {
        if (!existingDevice) return;
        const res = this.pairingManager.createPairingCode(existingDevice.deviceId);
        if ('error' in res) {
          this.sendError(ws, res.error, res.message);
        } else {
          this.send(ws, {
            type: 'pairing_code',
            code: res.code,
            expiresInSec: res.expiresInSec,
          });
        }
        break;
      }

      case 'pair': {
        if (!existingDevice) return;
        const res = this.pairingManager.handlePairRequest(
          existingDevice.deviceId,
          message.deviceName || existingDevice.deviceName,
          message.code
        );
        if (!res.success && res.errorCode) {
          this.sendError(ws, res.errorCode, res.message || 'Pairing failed');
        }
        break;
      }

      case 'approve_pair': {
        if (!existingDevice) return;
        const res = this.pairingManager.handleApprovePair(existingDevice.deviceId, message.peerDeviceId);
        if (!res.success && res.errorCode) {
          this.sendError(ws, res.errorCode, res.message || 'Approval failed');
        }
        break;
      }

      case 'deny_pair': {
        if (!existingDevice) return;
        const res = this.pairingManager.handleDenyPair(existingDevice.deviceId, message.peerDeviceId);
        if (!res.success && res.errorCode) {
          this.sendError(ws, res.errorCode, res.message || 'Deny failed');
        }
        break;
      }

      case 'resume_session': {
        if (!existingDevice) return;
        const res = this.pairingManager.handleResumeSession(
          existingDevice.deviceId,
          message.peerDeviceId,
          message.authToken
        );
        if (!res.success && res.errorCode) {
          this.sendError(ws, res.errorCode, res.message || 'Resume session failed');
        }
        break;
      }

      case 'offer': {
        if (!existingDevice) return;
        const res = this.relayManager.relayOffer(existingDevice.deviceId, message.targetDeviceId, message.sdp);
        if (!res.success && res.errorCode) {
          this.sendError(ws, res.errorCode, res.message || 'Offer relay failed');
        }
        break;
      }

      case 'answer': {
        if (!existingDevice) return;
        const res = this.relayManager.relayAnswer(existingDevice.deviceId, message.targetDeviceId, message.sdp);
        if (!res.success && res.errorCode) {
          this.sendError(ws, res.errorCode, res.message || 'Answer relay failed');
        }
        break;
      }

      case 'ice_candidate': {
        if (!existingDevice) return;
        const res = this.relayManager.relayIceCandidate(
          existingDevice.deviceId,
          message.targetDeviceId,
          message.candidate
        );
        if (!res.success && res.errorCode) {
          this.sendError(ws, res.errorCode, res.message || 'ICE candidate relay failed');
        }
        break;
      }

      case 'end_session': {
        if (!existingDevice) return;
        this.relayManager.handleEndSession(existingDevice.deviceId, message.targetDeviceId);
        break;
      }

      case 'request_turn_credentials': {
        const credentials = await this.turnManager.getTurnCredentials();
        this.send(ws, credentials);
        break;
      }
    }
  }

  private handleDisconnect(ws: WebSocket, code: number, reason: string): void {
    const dev = this.registry.unregisterBySocket(ws);
    if (dev) {
      logger.info({ deviceId: dev.deviceId, code, reason }, 'Device disconnected');

      // If device had an active peer session, notify peer
      if (dev.activePeerDeviceId) {
        this.registry.sendTo(dev.activePeerDeviceId, {
          type: 'peer_disconnected',
          peerDeviceId: dev.deviceId,
        });
      }

      // Clean up any pairing codes/requests
      this.pairingManager.handleDeviceDisconnect(dev.deviceId);
    }
  }

  private send(ws: WebSocket, message: OutboundMessage): void {
    this.registry.sendRaw(ws, message);
  }

  private sendError(ws: WebSocket, code: OutboundMessage extends { code: infer C } ? C : string, message: string): void {
    this.registry.sendRaw(ws, {
      type: 'error',
      code: code as never,
      message,
    });
  }

  public close(): Promise<void> {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
    }
    this.pairingManager.destroy();
    return new Promise((resolve) => {
      this.wss.close(() => resolve());
    });
  }
}
