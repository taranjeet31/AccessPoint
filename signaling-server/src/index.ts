import 'dotenv/config';
import http from 'http';
import express from 'express';
import { SignalingWebSocketServer } from './wsServer.js';
import { logger } from './logger.js';

const PORT = parseInt(process.env.PORT || '8080', 10);

const app = express();
const server = http.createServer(app);

// Initialize WebSocket signaling server sharing the HTTP server
const wsServer = new SignalingWebSocketServer({
  server,
  path: '/ws',
});

// Health check endpoint
app.get('/health', (_req, res) => {
  res.status(200).json({
    status: 'ok',
    uptime: process.uptime(),
    connections: wsServer.registry.count,
    timestamp: new Date().toISOString(),
  });
});

// Start listening
server.listen(PORT, () => {
  logger.info(`Signaling server listening on port ${PORT}`);
  logger.info(`WebSocket endpoint: ws://localhost:${PORT}/ws`);
  logger.info(`Health check: http://localhost:${PORT}/health`);
});

// Graceful shutdown
async function gracefulShutdown(signal: string) {
  logger.info(`Received ${signal}, shutting down gracefully...`);
  await wsServer.close();
  server.close(() => {
    logger.info('HTTP and WebSocket server closed');
    process.exit(0);
  });

  // Force shutdown if taking too long
  setTimeout(() => {
    logger.error('Could not close connections in time, forcefully shutting down');
    process.exit(1);
  }, 5000);
}

process.on('SIGINT', () => gracefulShutdown('SIGINT'));
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));

export { app, server, wsServer };
