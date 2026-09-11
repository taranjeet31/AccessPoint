import { logger } from './logger.js';
import type { TurnCredentialsMessage } from './messages.js';

interface CachedCredentials {
  message: TurnCredentialsMessage;
  expiresAt: number;
}

export class TurnManager {
  private cachedCredentials: CachedCredentials | null = null;
  private providerUrl = process.env.TURN_PROVIDER_URL;
  private providerApiKey = process.env.TURN_PROVIDER_API_KEY;

  /**
   * Fetches or generates short-lived TURN credentials.
   */
  public async getTurnCredentials(): Promise<TurnCredentialsMessage> {
    const now = Date.now();

    // Return cached credentials if still valid (with a 60s buffer)
    if (this.cachedCredentials && this.cachedCredentials.expiresAt > now + 60 * 1000) {
      logger.debug('Returning cached TURN credentials');
      return this.cachedCredentials.message;
    }

    // Try fetching from external TURN provider if configured
    if (this.providerUrl) {
      try {
        const creds = await this.fetchFromProvider();
        if (creds) {
          const ttlSec = creds.ttlSec || 3600;
          this.cachedCredentials = {
            message: creds,
            expiresAt: now + ttlSec * 1000,
          };
          logger.info({ urls: creds.urls, ttlSec }, 'Fetched fresh TURN credentials from provider');
          return creds;
        }
      } catch (err) {
        logger.error({ err }, 'Failed to fetch credentials from TURN provider, falling back to default STUN/TURN');
      }
    }

    // Fallback STUN/TURN configuration for development / default setups
    const fallbackMessage: TurnCredentialsMessage = {
      type: 'turn_credentials',
      urls: [
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
        'stun:stun2.l.google.com:19302',
        'stun:stun.relay.metered.ca:80',
      ],
      username: 'openrelayproject',
      credential: 'openrelayproject',
      ttlSec: 86400,
    };

    return fallbackMessage;
  }

  /**
   * Fetches credentials from configured TURN provider (e.g. Metered.ca, Twilio, or standard TURN REST service).
   */
  private async fetchFromProvider(): Promise<TurnCredentialsMessage | null> {
    if (!this.providerUrl) return null;

    let requestUrl = this.providerUrl;
    if (this.providerApiKey && !requestUrl.includes('apiKey=')) {
      const delimiter = requestUrl.includes('?') ? '&' : '?';
      requestUrl = `${requestUrl}${delimiter}apiKey=${encodeURIComponent(this.providerApiKey)}`;
    }

    const response = await fetch(requestUrl, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
      },
    });

    if (!response.ok) {
      throw new Error(`TURN provider responded with status ${response.status}: ${await response.text()}`);
    }

    const data = (await response.json()) as any;

    // Handle Metered.ca format: array of ice servers [{ urls: [...], username: '...', credential: '...' }]
    if (Array.isArray(data)) {
      const allUrls: string[] = [];
      let username = '';
      let credential = '';

      for (const item of data) {
        if (typeof item.urls === 'string') {
          allUrls.push(item.urls);
        } else if (Array.isArray(item.urls)) {
          allUrls.push(...item.urls);
        }
        if (item.username) username = item.username;
        if (item.credential) credential = item.credential;
      }

      return {
        type: 'turn_credentials',
        urls: allUrls,
        username,
        credential,
        ttlSec: 3600,
      };
    }

    // Handle standard object format
    if (data && (data.urls || data.iceServers)) {
      const iceServers = data.iceServers || [data];
      const urls: string[] = [];
      let username = data.username || '';
      let credential = data.credential || data.password || '';

      for (const server of iceServers) {
        if (typeof server.urls === 'string') {
          urls.push(server.urls);
        } else if (Array.isArray(server.urls)) {
          urls.push(...server.urls);
        } else if (server.url) {
          urls.push(server.url);
        }
        if (server.username) username = server.username;
        if (server.credential || server.password) credential = server.credential || server.password;
      }

      return {
        type: 'turn_credentials',
        urls,
        username,
        credential,
        ttlSec: data.ttl || data.ttlSec || 3600,
      };
    }

    return null;
  }
}
