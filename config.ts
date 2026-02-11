import * as fs from 'fs';
import * as yaml from 'js-yaml';

export interface ServerConfig {
  port: number;
  target: string;
  verbose: boolean;
}

export interface LoggingConfig {
  level: string;
  format: string;
}

export interface LoggingMiddlewareConfig {
  enabled: boolean;
  logBody: boolean;
  maxBodySize: number;
  excludePaths: string[];
}

export interface AuthMiddlewareConfig {
  enabled: boolean;
  type: 'basic' | 'bearer' | 'api_key';
  users: Record<string, string>;
  apiKeys: string[];
  headerName: string;
}

export interface RateLimitMiddlewareConfig {
  enabled: boolean;
  requestsPerSec: number;
  burstSize: number;
  byIP: boolean;
}

export interface HeadersMiddlewareConfig {
  enabled: boolean;
  addRequest: Record<string, string>;
  removeRequest: string[];
  addResponse: Record<string, string>;
  removeResponse: string[];
}

export interface RewriteRule {
  match: string;
  replace: string;
}

export interface RewriteMiddlewareConfig {
  enabled: boolean;
  rules: RewriteRule[];
}

export interface MiddlewareConfig {
  logging: LoggingMiddlewareConfig;
  auth: AuthMiddlewareConfig;
  rateLimit: RateLimitMiddlewareConfig;
  headers: HeadersMiddlewareConfig;
  rewrite: RewriteMiddlewareConfig;
}

export interface HandlersConfig {
  blockList: string[];
  allowList: string[];
}

export interface Provider {
  name: string;
  host: string;
  port: number;
  region: string;
  useHttps: boolean;
  skipTlsVerify: boolean;
}

export interface Config {
  server: ServerConfig;
  logging: LoggingConfig;
  middleware: MiddlewareConfig;
  handlers: HandlersConfig;
  providers: Record<string, Provider>;
}

const defaultConfig: Config = {
  server: {
    port: 8080,
    target: 'https://httpbin.org',
    verbose: false,
  },
  logging: {
    level: 'info',
    format: 'json',
  },
  middleware: {
    logging: {
      enabled: true,
      logBody: false,
      maxBodySize: 1024,
      excludePaths: [],
    },
    auth: {
      enabled: false,
      type: 'basic',
      users: {},
      apiKeys: [],
      headerName: 'X-API-Key',
    },
    rateLimit: {
      enabled: false,
      requestsPerSec: 100,
      burstSize: 50,
      byIP: true,
    },
    headers: {
      enabled: false,
      addRequest: {},
      removeRequest: [],
      addResponse: {},
      removeResponse: [],
    },
    rewrite: {
      enabled: false,
      rules: [],
    },
  },
  handlers: {
    blockList: [],
    allowList: [],
  },
  providers: {},
};

export function loadConfig(path: string): Config {
  try {
    const fileContents = fs.readFileSync(path, 'utf8');
    const loaded = yaml.load(fileContents) as Partial<Config>;
    return mergeConfig(defaultConfig, loaded);
  } catch (error) {
    console.warn(`Warning: Could not load config file (${path}), using defaults`);
    return defaultConfig;
  }
}

function mergeConfig(defaults: Config, loaded: Partial<Config>): Config {
  // Normalize provider keys to uppercase and apply defaults per provider.
  // Accept both camelCase (useHttps) and snake_case (use_https) to stay
  // compatible with the Go proxy config format.
  const rawProviders = loaded.providers || {};
  const providers: Record<string, Provider> = {};
  for (const [key, value] of Object.entries(rawProviders)) {
    const p = value as Record<string, any>;
    providers[key.toUpperCase()] = {
      name: p.name || key,
      host: p.host || 'localhost',
      port: p.port || 0,
      region: p.region || '',
      useHttps: p.useHttps ?? p.use_https ?? false,
      skipTlsVerify: p.skipTlsVerify ?? p.skip_tls_verify ?? false,
    };
  }

  return {
    server: { ...defaults.server, ...loaded.server },
    logging: { ...defaults.logging, ...loaded.logging },
    middleware: {
      logging: { ...defaults.middleware.logging, ...loaded.middleware?.logging },
      auth: { ...defaults.middleware.auth, ...loaded.middleware?.auth },
      rateLimit: { ...defaults.middleware.rateLimit, ...loaded.middleware?.rateLimit },
      headers: { ...defaults.middleware.headers, ...loaded.middleware?.headers },
      rewrite: { ...defaults.middleware.rewrite, ...loaded.middleware?.rewrite },
    },
    handlers: { ...defaults.handlers, ...loaded.handlers },
    providers,
  };
}
