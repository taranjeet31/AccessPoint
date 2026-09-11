import jwt from 'jsonwebtoken';
import { logger } from './logger.js';

const JWT_SECRET = process.env.JWT_SECRET || 'dev-insecure-jwt-secret-change-in-production';
const TOKEN_EXPIRY = '365d';

export interface AuthTokenPayload {
  hostDeviceId: string;
  controllerDeviceId: string;
}

/**
 * Issues a long-lived JWT auth token for an approved host-controller pairing.
 */
export function issueAuthToken(hostDeviceId: string, controllerDeviceId: string): string {
  const payload: AuthTokenPayload = {
    hostDeviceId,
    controllerDeviceId,
  };
  return jwt.sign(payload, JWT_SECRET, { expiresIn: TOKEN_EXPIRY });
}

/**
 * Verifies a JWT auth token and returns the payload if valid.
 */
export function verifyAuthToken(token: string): AuthTokenPayload | null {
  try {
    const decoded = jwt.verify(token, JWT_SECRET) as jwt.JwtPayload & AuthTokenPayload;
    if (decoded && decoded.hostDeviceId && decoded.controllerDeviceId) {
      return {
        hostDeviceId: decoded.hostDeviceId,
        controllerDeviceId: decoded.controllerDeviceId,
      };
    }
    return null;
  } catch (err) {
    logger.debug({ err, token: token.slice(0, 10) + '...' }, 'Failed to verify auth token');
    return null;
  }
}
