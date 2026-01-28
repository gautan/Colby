/**
 * K6 Performance Test Script
 * API: https://mywsqa.barcapint.com/BLA/api-v1/preferences
 *
 * Install k6: brew install k6
 * Run: k6 run k6-load-test.js
 * Run with options: k6 run --vus 50 --duration 5m k6-load-test.js
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';
import { randomString, randomIntBetween } from 'https://jslib.k6.io/k6-utils/1.2.0/index.js';

// ============================================
// CONFIGURATION
// ============================================

const BASE_URL = __ENV.BASE_URL || 'https://mywsqa.barcapint.com';
const API_ENDPOINT = '/BLA/api-v1/preferences';
const PROXY_USER = __ENV.PROXY_USER || 'kamanyas';

// Test scenarios
export const options = {
  scenarios: {
    // Smoke test - verify system works
    smoke: {
      executor: 'constant-vus',
      vus: 1,
      duration: '30s',
      startTime: '0s',
      tags: { test_type: 'smoke' },
    },

    // Load test - normal load
    load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 50 },   // Ramp up to 50 users
        { duration: '5m', target: 50 },   // Stay at 50 users
        { duration: '2m', target: 100 },  // Ramp up to 100 users
        { duration: '5m', target: 100 },  // Stay at 100 users
        { duration: '2m', target: 0 },    // Ramp down
      ],
      startTime: '30s',
      tags: { test_type: 'load' },
    },

    // Stress test - find breaking point
    stress: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 100 },
        { duration: '5m', target: 200 },
        { duration: '5m', target: 300 },
        { duration: '5m', target: 400 },
        { duration: '2m', target: 0 },
      ],
      startTime: '17m',
      tags: { test_type: 'stress' },
    },

    // Spike test - sudden traffic spike
    spike: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '10s', target: 500 },  // Instant spike
        { duration: '1m', target: 500 },   // Hold spike
        { duration: '10s', target: 0 },    // Quick drop
      ],
      startTime: '36m',
      tags: { test_type: 'spike' },
    },

    // Soak test - extended duration
    soak: {
      executor: 'constant-vus',
      vus: 50,
      duration: '30m',
      startTime: '38m',
      tags: { test_type: 'soak' },
    },
  },

  thresholds: {
    // Response time thresholds
    http_req_duration: ['p(95)<2000', 'p(99)<5000'],  // 95% < 2s, 99% < 5s
    http_req_failed: ['rate<0.05'],                   // Error rate < 5%

    // Custom metrics thresholds
    'http_req_duration{test_type:smoke}': ['p(95)<1000'],
    'http_req_duration{test_type:load}': ['p(95)<2000'],
    'api_success_rate': ['rate>0.95'],
  },
};

// ============================================
// CUSTOM METRICS
// ============================================

const apiSuccessRate = new Rate('api_success_rate');
const apiErrorCount = new Counter('api_errors');
const apiLatency = new Trend('api_latency');
const timeoutErrors = new Counter('timeout_errors');
const authErrors = new Counter('auth_errors');
const validationErrors = new Counter('validation_errors');
const serverErrors = new Counter('server_errors');

// ============================================
// HELPER FUNCTIONS
// ============================================

function getHeaders(customHeaders = {}) {
  return Object.assign({
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Proxy-Remote-User': PROXY_USER,
  }, customHeaders);
}

function getValidPayload() {
  return JSON.stringify({
    data: {
      level3: 'data'
    }
  });
}

function logError(scenario, response, expectedStatus) {
  console.error(`[${scenario}] Status: ${response.status}, Expected: ${expectedStatus}, Body: ${response.body}`);
}

// ============================================
// TEST SCENARIOS
// ============================================

export default function () {
  // Randomly select a test scenario
  const scenarios = [
    { weight: 60, fn: successScenario },
    { weight: 10, fn: invalidPayloadScenario },
    { weight: 5, fn: missingHeaderScenario },
    { weight: 5, fn: invalidUserScenario },
    { weight: 5, fn: emptyPayloadScenario },
    { weight: 5, fn: largePayloadScenario },
    { weight: 5, fn: malformedJsonScenario },
    { weight: 5, fn: slowConnectionScenario },
  ];

  const totalWeight = scenarios.reduce((sum, s) => sum + s.weight, 0);
  let random = Math.random() * totalWeight;

  for (const scenario of scenarios) {
    random -= scenario.weight;
    if (random <= 0) {
      scenario.fn();
      break;
    }
  }

  sleep(randomIntBetween(1, 3));
}

// ============================================
// SUCCESS SCENARIO (Normal Request)
// ============================================

function successScenario() {
  group('Success Scenario', function () {
    const payload = getValidPayload();
    const headers = getHeaders();

    const response = http.post(`${BASE_URL}${API_ENDPOINT}`, payload, {
      headers: headers,
      timeout: '30s',
    });

    const success = check(response, {
      'status is 200': (r) => r.status === 200,
      'response time < 2s': (r) => r.timings.duration < 2000,
      'has response body': (r) => r.body && r.body.length > 0,
      'content-type is json': (r) => r.headers['Content-Type'] && r.headers['Content-Type'].includes('application/json'),
    });

    apiSuccessRate.add(success);
    apiLatency.add(response.timings.duration);

    if (!success) {
      apiErrorCount.add(1);
      logError('Success', response, 200);
    }
  });
}

// ============================================
// FAILURE SCENARIO: Invalid Payload
// ============================================

function invalidPayloadScenario() {
  group('Invalid Payload Scenario', function () {
    const invalidPayloads = [
      // Missing required field
      JSON.stringify({ data: {} }),

      // Wrong data type
      JSON.stringify({ data: { level3: 123 } }),

      // Invalid structure
      JSON.stringify({ data: { level3: { nested: 'invalid' } } }),

      // Null value
      JSON.stringify({ data: { level3: null } }),

      // Array instead of object
      JSON.stringify({ data: ['level3', 'data'] }),

      // Extra unexpected fields
      JSON.stringify({ data: { level3: 'data', extra: 'field' }, unexpected: true }),
    ];

    const payload = invalidPayloads[randomIntBetween(0, invalidPayloads.length - 1)];
    const headers = getHeaders();

    const response = http.post(`${BASE_URL}${API_ENDPOINT}`, payload, {
      headers: headers,
      timeout: '30s',
    });

    const expectedFailure = check(response, {
      'returns 400 or 422 for invalid payload': (r) => r.status === 400 || r.status === 422,
      'has error message': (r) => {
        try {
          const body = JSON.parse(r.body);
          return body.error || body.message || body.errors;
        } catch (e) {
          return false;
        }
      },
    });

    if (!expectedFailure) {
      validationErrors.add(1);
      logError('Invalid Payload', response, '400/422');
    }
  });
}

// ============================================
// FAILURE SCENARIO: Missing Header
// ============================================

function missingHeaderScenario() {
  group('Missing Header Scenario', function () {
    const payload = getValidPayload();

    // Missing Proxy-Remote-User header
    const headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    const response = http.post(`${BASE_URL}${API_ENDPOINT}`, payload, {
      headers: headers,
      timeout: '30s',
    });

    const expectedFailure = check(response, {
      'returns 401 or 403 for missing auth header': (r) => r.status === 401 || r.status === 403,
    });

    if (!expectedFailure && response.status === 200) {
      // If it returns 200 without auth header, that might be a security issue
      console.warn('[Security] Request succeeded without Proxy-Remote-User header');
    }

    if (response.status === 401 || response.status === 403) {
      authErrors.add(1);
    }
  });
}

// ============================================
// FAILURE SCENARIO: Invalid User
// ============================================

function invalidUserScenario() {
  group('Invalid User Scenario', function () {
    const payload = getValidPayload();

    const invalidUsers = [
      '',                           // Empty
      'nonexistent_user',           // Non-existent
      'admin\'; DROP TABLE users;', // SQL injection attempt
      '<script>alert(1)</script>',  // XSS attempt
      '../../../etc/passwd',        // Path traversal
      'a'.repeat(10000),            // Very long string
    ];

    const headers = getHeaders({
      'Proxy-Remote-User': invalidUsers[randomIntBetween(0, invalidUsers.length - 1)],
    });

    const response = http.post(`${BASE_URL}${API_ENDPOINT}`, payload, {
      headers: headers,
      timeout: '30s',
    });

    check(response, {
      'returns 401/403 for invalid user': (r) => r.status === 401 || r.status === 403 || r.status === 400,
      'handles invalid input safely': (r) => r.status !== 500,
    });

    if (response.status === 401 || response.status === 403) {
      authErrors.add(1);
    }
    if (response.status >= 500) {
      serverErrors.add(1);
      logError('Invalid User', response, '401/403');
    }
  });
}

// ============================================
// FAILURE SCENARIO: Empty Payload
// ============================================

function emptyPayloadScenario() {
  group('Empty Payload Scenario', function () {
    const headers = getHeaders();

    const emptyPayloads = [
      '',           // Completely empty
      '{}',         // Empty object
      'null',       // Null
      '[]',         // Empty array
    ];

    const payload = emptyPayloads[randomIntBetween(0, emptyPayloads.length - 1)];

    const response = http.post(`${BASE_URL}${API_ENDPOINT}`, payload, {
      headers: headers,
      timeout: '30s',
    });

    check(response, {
      'returns 400 for empty payload': (r) => r.status === 400,
      'does not crash server': (r) => r.status !== 500,
    });

    if (response.status >= 500) {
      serverErrors.add(1);
      logError('Empty Payload', response, 400);
    }
  });
}

// ============================================
// FAILURE SCENARIO: Large Payload
// ============================================

function largePayloadScenario() {
  group('Large Payload Scenario', function () {
    // Create a large payload (1MB)
    const largeData = 'x'.repeat(1024 * 1024);
    const payload = JSON.stringify({
      data: {
        level3: largeData,
      }
    });

    const headers = getHeaders();

    const response = http.post(`${BASE_URL}${API_ENDPOINT}`, payload, {
      headers: headers,
      timeout: '60s',
    });

    check(response, {
      'returns 413 for large payload': (r) => r.status === 413 || r.status === 400,
      'does not timeout': (r) => r.status !== 0,
      'server handles gracefully': (r) => r.status !== 500,
    });

    if (response.status >= 500) {
      serverErrors.add(1);
      logError('Large Payload', response, 413);
    }
  });
}

// ============================================
// FAILURE SCENARIO: Malformed JSON
// ============================================

function malformedJsonScenario() {
  group('Malformed JSON Scenario', function () {
    const malformedPayloads = [
      '{"data": {level3: "data"}}',           // Missing quotes
      '{"data": {"level3": "data",}}',        // Trailing comma
      '{data: {"level3": "data"}}',           // Missing quotes on key
      '{"data": {"level3": "data"}',          // Missing closing brace
      "{'data': {'level3': 'data'}}",         // Single quotes
      '{"data": undefined}',                   // Undefined value
      '{"data": {"level3": "data"}} extra',   // Extra content
    ];

    const payload = malformedPayloads[randomIntBetween(0, malformedPayloads.length - 1)];
    const headers = getHeaders();

    const response = http.post(`${BASE_URL}${API_ENDPOINT}`, payload, {
      headers: headers,
      timeout: '30s',
    });

    check(response, {
      'returns 400 for malformed JSON': (r) => r.status === 400,
      'server handles gracefully': (r) => r.status !== 500,
    });

    if (response.status >= 500) {
      serverErrors.add(1);
      logError('Malformed JSON', response, 400);
    }
  });
}

// ============================================
// FAILURE SCENARIO: Slow Connection / Timeout
// ============================================

function slowConnectionScenario() {
  group('Slow Connection Scenario', function () {
    const payload = getValidPayload();
    const headers = getHeaders();

    // Very short timeout to simulate timeout scenario
    const response = http.post(`${BASE_URL}${API_ENDPOINT}`, payload, {
      headers: headers,
      timeout: '100ms',  // Intentionally short
    });

    if (response.status === 0) {
      timeoutErrors.add(1);
      check(response, {
        'timeout handled': (r) => r.error_code !== undefined,
      });
    }
  });
}

// ============================================
// SETUP & TEARDOWN
// ============================================

export function setup() {
  console.log('============================================');
  console.log('Starting Performance Tests');
  console.log(`Base URL: ${BASE_URL}`);
  console.log(`Endpoint: ${API_ENDPOINT}`);
  console.log(`User: ${PROXY_USER}`);
  console.log('============================================');

  // Verify API is accessible
  const response = http.post(`${BASE_URL}${API_ENDPOINT}`, getValidPayload(), {
    headers: getHeaders(),
    timeout: '30s',
  });

  if (response.status !== 200) {
    console.error(`Setup failed! API returned status: ${response.status}`);
    console.error(`Response: ${response.body}`);
  }

  return { startTime: new Date().toISOString() };
}

export function teardown(data) {
  console.log('============================================');
  console.log('Performance Tests Completed');
  console.log(`Started: ${data.startTime}`);
  console.log(`Ended: ${new Date().toISOString()}`);
  console.log('============================================');
}

// ============================================
// HANDLE SUMMARY
// ============================================

export function handleSummary(data) {
  const summary = {
    timestamp: new Date().toISOString(),
    totalRequests: data.metrics.http_reqs ? data.metrics.http_reqs.values.count : 0,
    failedRequests: data.metrics.http_req_failed ? data.metrics.http_req_failed.values.passes : 0,
    avgResponseTime: data.metrics.http_req_duration ? data.metrics.http_req_duration.values.avg : 0,
    p95ResponseTime: data.metrics.http_req_duration ? data.metrics.http_req_duration.values['p(95)'] : 0,
    p99ResponseTime: data.metrics.http_req_duration ? data.metrics.http_req_duration.values['p(99)'] : 0,
    thresholdsPassed: Object.values(data.root_group.checks).every(c => c.passes > 0),
  };

  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    'results/summary.json': JSON.stringify(data, null, 2),
    'results/summary.html': htmlReport(data),
  };
}

function textSummary(data, options) {
  // K6 built-in text summary
  return '';
}

function htmlReport(data) {
  return `
<!DOCTYPE html>
<html>
<head>
  <title>Performance Test Report</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    .metric { margin: 10px 0; padding: 10px; background: #f5f5f5; }
    .pass { color: green; }
    .fail { color: red; }
  </style>
</head>
<body>
  <h1>Performance Test Report</h1>
  <p>Generated: ${new Date().toISOString()}</p>
  <div class="metric">
    <h3>Request Metrics</h3>
    <p>Total Requests: ${data.metrics.http_reqs?.values?.count || 0}</p>
    <p>Failed Requests: ${data.metrics.http_req_failed?.values?.passes || 0}</p>
    <p>Avg Response Time: ${(data.metrics.http_req_duration?.values?.avg || 0).toFixed(2)}ms</p>
    <p>P95 Response Time: ${(data.metrics.http_req_duration?.values?.['p(95)'] || 0).toFixed(2)}ms</p>
    <p>P99 Response Time: ${(data.metrics.http_req_duration?.values?.['p(99)'] || 0).toFixed(2)}ms</p>
  </div>
</body>
</html>
  `;
}
