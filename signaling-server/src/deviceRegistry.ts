import type { WebSocket } from 'ws';
import type { OutboundMessage } from './messages.js';
import { logger } from './logger.js';

export interface DeviceEntry {
  deviceId: string;
  role: 'host' | 'controller';
  deviceName: string;
  ws: WebSocket;
  activePeerDeviceId?: string;
  connectedAt: Date;
}

export class DeviceRegistry {
  private devicesById = new Map<string, DeviceEntry>();
  private devicesBySocket = new Map<WebSocket, string>();

  /**
   * Registers a device with the registry.
   */
  public register(
    deviceId: string,
    role: 'host' | 'controller',
    deviceName: string,
    ws: WebSocket
  ): DeviceEntry {
    // If device was already registered with an old socket, clean up the old socket mapping
    const existing = this.devicesById.get(deviceId);
    if (existing && existing.ws !== ws) {
      this.devicesBySocket.delete(existing.ws);
      try {
        if (existing.ws.readyState === 1 /* OPEN */) {
          existing.ws.close(1000, 'Replaced by new registration');
        }
      } catch (err) {
        logger.debug({ err, deviceId }, 'Error closing previous socket on re-registration');
      }
    }

    const entry: DeviceEntry = {
      deviceId,
      role,
      deviceName,
      ws,
      connectedAt: new Date(),
    };

    this.devicesById.set(deviceId, entry);
    this.devicesBySocket.set(ws, deviceId);

    logger.info({ deviceId, role, deviceName }, 'Device registered');
    return entry;
  }

  /**
   * Unregisters a device by socket.
   */
  public unregisterBySocket(ws: WebSocket): DeviceEntry | undefined {
    const deviceId = this.devicesBySocket.get(ws);
    if (!deviceId) {
      return undefined;
    }

    this.devicesBySocket.delete(ws);
    const entry = this.devicesById.get(deviceId);
    if (entry) {
      this.devicesById.delete(deviceId);
      // If there was an active peer, unlink it
      if (entry.activePeerDeviceId) {
        const peer = this.devicesById.get(entry.activePeerDeviceId);
        if (peer && peer.activePeerDeviceId === deviceId) {
          peer.activePeerDeviceId = undefined;
        }
      }
      logger.info({ deviceId, role: entry.role, deviceName: entry.deviceName }, 'Device unregistered');
    }
    return entry;
  }

  /**
   * Retrieves a device entry by deviceId.
   */
  public getByDeviceId(deviceId: string): DeviceEntry | undefined {
    return this.devicesById.get(deviceId);
  }

  /**
   * Retrieves a device entry by WebSocket.
   */
  public getBySocket(ws: WebSocket): DeviceEntry | undefined {
    const deviceId = this.devicesBySocket.get(ws);
    if (!deviceId) return undefined;
    return this.devicesById.get(deviceId);
  }

  /**
   * Links two devices as active session peers.
   */
  public linkPeers(deviceId1: string, deviceId2: string): boolean {
    const dev1 = this.devicesById.get(deviceId1);
    const dev2 = this.devicesById.get(deviceId2);
    if (!dev1 || !dev2) return false;

    dev1.activePeerDeviceId = deviceId2;
    dev2.activePeerDeviceId = deviceId1;
    return true;
  }

  /**
   * Unlinks an active peer session.
   */
  public unlinkPeers(deviceId: string): string | undefined {
    const dev = this.devicesById.get(deviceId);
    if (!dev) return undefined;

    const peerId = dev.activePeerDeviceId;
    dev.activePeerDeviceId = undefined;

    if (peerId) {
      const peer = this.devicesById.get(peerId);
      if (peer && peer.activePeerDeviceId === deviceId) {
        peer.activePeerDeviceId = undefined;
      }
    }

    return peerId;
  }

  /**
   * Sends a JSON message to a registered device by deviceId.
   * Returns true if sent, false otherwise.
   */
  public sendTo(deviceId: string, message: OutboundMessage): boolean {
    const dev = this.devicesById.get(deviceId);
    if (!dev) return false;
    return this.sendRaw(dev.ws, message);
  }

  /**
   * Sends a JSON message directly to a WebSocket connection.
   */
  public sendRaw(ws: WebSocket, message: OutboundMessage): boolean {
    try {
      if (ws.readyState === 1 /* OPEN */) {
        ws.send(JSON.stringify(message));
        return true;
      }
      return false;
    } catch (err) {
      logger.error({ err, messageType: message.type }, 'Failed to send message to socket');
      return false;
    }
  }

  /**
   * Total number of connected devices.
   */
  public get count(): number {
    return this.devicesById.size;
  }

  /**
   * Resets all internal maps.
   */
  public clear(): void {
    this.devicesById.clear();
    this.devicesBySocket.clear();
  }
}
