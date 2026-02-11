import net from 'net';
import express from 'express';
import { createProxyMiddleware, Options } from 'http-proxy-middleware';
import { loadConfig } from './config/config';
import { createLogger } from './logger/logger';
import {
  createLoggingMiddleware,
  createAuthMiddleware,
  createRateLimitMiddleware,
  createRequestHeadersMiddleware,
  createResponseHeadersMiddleware,
  createRewriteMiddleware,
  createProviderMiddleware,
  createProviderRouter,
} from './middleware';
import {
  createBlockListMiddleware,
  createAllowListMiddleware,
  createResponseModifier,
} from './handlers';

// Parse command line arguments
const configPath = process.argv[2] || 'config.yaml';

// Load configuration
const config = loadConfig(configPath);

// Initialize logger
const logger = createLogger(config.logging.level, config.logging.format);

const hasProviders = Object.keys(config.providers).length > 0;

logger.info('Starting proxy server', {
  port: config.server.port,
  mode: hasProviders ? 'reverse-proxy (provider routing)' : 'forward-proxy',
});

// Create Express app
const app = express();

// Trust proxy for correct IP detection
app.set('trust proxy', true);

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    mode: hasProviders ? 'reverse-proxy' : 'forward-proxy',
    providers: Object.keys(config.providers),
  });
});

// Register middleware chain
// 1. Request logging middleware
if (config.middleware.logging.enabled) {
  logger.info('Enabling logging middleware');
  app.use(createLoggingMiddleware(config.middleware.logging, logger));
}

// 2. Block list handler
if (config.handlers.blockList.length > 0) {
  logger.info('Enabling block list handler', { count: config.handlers.blockList.length });
  app.use(createBlockListMiddleware(config.handlers.blockList, logger));
}

// 3. Allow list handler (whitelist mode)
if (config.handlers.allowList.length > 0) {
  logger.info('Enabling allow list handler', { count: config.handlers.allowList.length });
  app.use(createAllowListMiddleware(config.handlers.allowList, logger));
}

// 4. Authentication middleware
if (config.middleware.auth.enabled) {
  logger.info('Enabling authentication middleware', { type: config.middleware.auth.type });
  app.use(createAuthMiddleware(config.middleware.auth, logger));
}

// 5. Rate limiting middleware
if (config.middleware.rateLimit.enabled) {
  logger.info('Enabling rate limiting middleware', {
    requestsPerSec: config.middleware.rateLimit.requestsPerSec,
    burstSize: config.middleware.rateLimit.burstSize,
  });
  app.use(createRateLimitMiddleware(config.middleware.rateLimit, logger));
}

// 6. Request header manipulation middleware
if (config.middleware.headers.enabled) {
  logger.info('Enabling headers middleware');
  app.use(createRequestHeadersMiddleware(config.middleware.headers, logger));
  app.use(createResponseHeadersMiddleware(config.middleware.headers, logger));
}

// 7. URL rewriting middleware
if (config.middleware.rewrite.enabled) {
  logger.info('Enabling URL rewrite middleware', { rules: config.middleware.rewrite.rules.length });
  app.use(createRewriteMiddleware(config.middleware.rewrite, logger));
}

// 8. Provider-based URL rewriting (reverse proxy mode)
if (hasProviders) {
  logger.info('Enabling provider routing', { count: Object.keys(config.providers).length });
  app.use(createProviderMiddleware(config.providers, logger));
}

// 9. Response modifier handler
app.use(createResponseModifier(logger));

// Check if any provider requires skipping TLS verification.
// When true, the proxy is configured with secure:false so that http-proxy
// does not reject self-signed / invalid upstream certificates.
const hasInsecureProvider = Object.values(config.providers).some(p => p.skipTlsVerify);

// Proxy configuration
const proxyOptions: Options = {
  target: config.server.target,
  changeOrigin: true,
  ws: true, // Enable WebSocket proxying
  logger: config.server.verbose ? console : undefined,

  // When any provider skips TLS verification, set secure:false so that
  // http-proxy passes rejectUnauthorized:false to the underlying https request.
  // No custom agent is needed — http-proxy handles this natively.
  secure: hasInsecureProvider ? false : undefined,

  // Dynamic target selection: if a provider middleware resolved a target, use
  // it; otherwise fall back to the default server target.
  router: hasProviders ? createProviderRouter(config.server.target) : undefined,

  on: {
    proxyReq: (proxyReq, req, res) => {
      const expressReq = req as express.Request;
      const target = expressReq.resolvedProvider?.target || config.server.target;

      logger.debug('Proxying request', {
        method: req.method,
        url: req.url,
        target,
      });
    },
    proxyRes: (proxyRes, req, res) => {
      logger.debug('Received response', {
        method: req.method,
        url: req.url,
        status: proxyRes.statusCode,
      });
    },
    error: (err, req, res) => {
      logger.error('Proxy error', {
        error: err.message,
        method: req.method,
        url: req.url,
      });

      if (res && 'writeHead' in res && !res.headersSent) {
        res.writeHead(502, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Bad Gateway', message: err.message }));
      }
    },
  },
};

// Create and use proxy middleware
const proxy = createProxyMiddleware(proxyOptions);
app.use('/', proxy);

// Start server
const server = app.listen(config.server.port, () => {
  logger.info('Proxy server listening', {
    address: `http://localhost:${config.server.port}`,
    target: config.server.target,
    mode: hasProviders ? 'reverse-proxy' : 'forward-proxy',
    providers: hasProviders ? Object.keys(config.providers) : undefined,
  });
});

// Track open connections so we can destroy them on shutdown.
const connections = new Set<net.Socket>();
server.on('connection', (conn) => {
  connections.add(conn);
  conn.on('close', () => connections.delete(conn));
});

const SHUTDOWN_TIMEOUT_MS = 5000;

function shutdown(signal: string) {
  logger.info(`Received ${signal}, shutting down proxy server...`);

  // Stop accepting new connections and wait for in-flight requests to finish.
  server.close(() => {
    logger.info('Server closed gracefully');
    process.exit(0);
  });

  // If in-flight requests don't finish within the timeout, force-close
  // every open socket and exit.
  setTimeout(() => {
    logger.warn('Graceful shutdown timed out, destroying open connections', {
      remaining: connections.size,
    });
    for (const conn of connections) {
      conn.destroy();
    }
    process.exit(1);
  }, SHUTDOWN_TIMEOUT_MS).unref();
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

export { app, server };
