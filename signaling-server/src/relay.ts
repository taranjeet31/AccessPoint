import { DeviceRegistry } from './deviceRegistry.js';
import { logger } from './logger.js';
import type { ErrorCode } from './messages.js';

export class RelayManager {
  constructor(private registry: DeviceRegistry) {}

  /**
   * Relays an SDP offer from sender to target device.
   */
  public relayOffer(
    fromDeviceId: string,
    targetDeviceId: string,
    sdp: string
  ): { success: boolean; errorCode?: ErrorCode; message?: string } {
    const target = this.registry.getByDeviceId(targetDeviceId);
    if (!target) {
      logger.debug({ fromDeviceId, targetDeviceId }, 'Relay offer failed: target is offline');
      return { success: false, errorCode: 'PEER_OFFLINE', message: 'Target device is offline' };
    }

    const sent = this.registry.sendTo(targetDeviceId, {
      type: 'offer',
      fromDeviceId,
      sdp,
    });

    if (!sent) {
      return { success: false, errorCode: 'PEER_OFFLINE', message: 'Failed to deliver offer to target device' };
    }

    logger.debug({ fromDeviceId, targetDeviceId }, 'Relayed SDP offer');
    return { success: true };
  }

  /**
   * Relays an SDP answer from sender to target device.
   */
  public relayAnswer(
    fromDeviceId: string,
    targetDeviceId: string,
    sdp: string
  ): { success: boolean; errorCode?: ErrorCode; message?: string } {
    const target = this.registry.getByDeviceId(targetDeviceId);
    if (!target) {
      logger.debug({ fromDeviceId, targetDeviceId }, 'Relay answer failed: target is offline');
      return { success: false, errorCode: 'PEER_OFFLINE', message: 'Target device is offline' };
    }

    const sent = this.registry.sendTo(targetDeviceId, {
      type: 'answer',
      fromDeviceId,
      sdp,
    });

    if (!sent) {
      return { success: false, errorCode: 'PEER_OFFLINE', message: 'Failed to deliver answer to target device' };
    }

    logger.debug({ fromDeviceId, targetDeviceId }, 'Relayed SDP answer');
    return { success: true };
  }

  /**
   * Relays an ICE candidate from sender to target device.
   */
  public relayIceCandidate(
    fromDeviceId: string,
    targetDeviceId: string,
    candidate: Record<string, unknown>
  ): { success: boolean; errorCode?: ErrorCode; message?: string } {
    const target = this.registry.getByDeviceId(targetDeviceId);
    if (!target) {
      logger.debug({ fromDeviceId, targetDeviceId }, 'Relay ICE candidate failed: target is offline');
      return { success: false, errorCode: 'PEER_OFFLINE', message: 'Target device is offline' };
    }

    const sent = this.registry.sendTo(targetDeviceId, {
      type: 'ice_candidate',
      fromDeviceId,
      candidate,
    });

    if (!sent) {
      return { success: false, errorCode: 'PEER_OFFLINE', message: 'Failed to deliver ICE candidate to target device' };
    }

    logger.debug({ fromDeviceId, targetDeviceId }, 'Relayed ICE candidate');
    return { success: true };
  }

  /**
   * Handles explicit end of session.
   */
  public handleEndSession(fromDeviceId: string, targetDeviceId: string): void {
    this.registry.unlinkPeers(fromDeviceId);
    const target = this.registry.getByDeviceId(targetDeviceId);
    if (target) {
      this.registry.sendTo(targetDeviceId, {
        type: 'peer_disconnected',
        peerDeviceId: fromDeviceId,
      });
    }
    logger.info({ fromDeviceId, targetDeviceId }, 'Session ended explicitly');
  }
}
