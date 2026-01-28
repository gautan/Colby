# Performance Test Suite

API under test: `https://mywsqa.barcapint.com/BLA/api-v1/preferences`

## Test Scripts

| Script | Tool | Best For |
|--------|------|----------|
| `k6-load-test.js` | k6 | Comprehensive load testing |
| `curl-test.sh` | curl/bash | Quick functional tests |
| `locustfile.py` | Locust | Interactive load testing |

---

## Quick Start

### Option 1: k6 (Recommended for Load Testing)

```bash
# Install k6
brew install k6

# Run basic test
k6 run k6-load-test.js

# Run with custom parameters
k6 run --vus 50 --duration 5m k6-load-test.js

# Run with environment variables
BASE_URL=https://mywsqa.barcapint.com PROXY_USER=kamanyas k6 run k6-load-test.js

# Run specific scenario
k6 run --env SCENARIO=smoke k6-load-test.js
```

### Option 2: cURL Script (Quick Tests)

```bash
# Run all tests
./curl-test.sh all

# Run functional tests only
./curl-test.sh functional

# Run security tests only
./curl-test.sh security

# Run load test
CONCURRENT_USERS=50 REQUESTS_PER_USER=100 ./curl-test.sh load

# Run stress test
./curl-test.sh stress
```

### Option 3: Locust (Interactive Web UI)

```bash
# Install locust
pip install locust

# Run with web UI
locust -f locustfile.py --host=https://mywsqa.barcapint.com
# Open http://localhost:8089

# Run headless
locust -f locustfile.py --host=https://mywsqa.barcapint.com \
    --headless -u 100 -r 10 -t 5m

# Run with HTML report
locust -f locustfile.py --host=https://mywsqa.barcapint.com \
    --headless -u 100 -r 10 -t 5m --html=results/report.html
```

---

## Test Scenarios

### Success Scenarios
- ✅ Normal valid request
- ✅ Request with extra data fields
- ✅ Unicode characters in payload
- ✅ Special characters in payload

### Validation Failure Scenarios
- ❌ Missing required field (`data.level3`)
- ❌ Wrong data type (number instead of string)
- ❌ Null value
- ❌ Empty payload
- ❌ Empty object `{}`
- ❌ Malformed JSON
- ❌ Large payload (>1MB)

### Authentication Failure Scenarios
- 🔐 Missing `Proxy-Remote-User` header
- 🔐 Invalid/non-existent user
- 🔐 Empty user header

### Security Test Scenarios
- 🛡️ SQL injection attempt
- 🛡️ XSS attempt
- 🛡️ Path traversal attempt
- 🛡️ Very long string (DoS)

### Edge Case Scenarios
- ⚡ Timeout handling
- ⚡ Concurrent rapid requests
- ⚡ Rate limiting behavior
- ⚡ Wrong HTTP method (GET instead of POST)
- ⚡ Wrong Content-Type header

---

## Test Types

| Type | Purpose | Duration | Users |
|------|---------|----------|-------|
| **Smoke** | Verify system works | 30s | 1 |
| **Load** | Normal traffic | 15m | 50-100 |
| **Stress** | Find breaking point | 20m | 100-400 |
| **Spike** | Sudden traffic burst | 2m | 500 |
| **Soak** | Memory leaks, stability | 30m+ | 50 |

---

## Expected Results

### API Contract

**Request:**
```http
POST /BLA/api-v1/preferences HTTP/1.1
Host: mywsqa.barcapint.com
Content-Type: application/json
Proxy-Remote-User: kamanyas

{
  "data": {
    "level3": "data"
  }
}
```

**Expected Responses:**

| Status | Condition |
|--------|-----------|
| 200 | Valid request |
| 400 | Invalid payload / Malformed JSON |
| 401 | Missing authentication |
| 403 | Invalid/unauthorized user |
| 413 | Payload too large |
| 422 | Validation error |
| 429 | Rate limited |
| 500 | Server error (bug) |

---

## Thresholds

| Metric | Target |
|--------|--------|
| P95 Response Time | < 2000ms |
| P99 Response Time | < 5000ms |
| Error Rate | < 5% |
| Success Rate | > 95% |

---

## Results

Results are saved in the `results/` directory:
- `summary.json` - JSON metrics
- `summary.html` - HTML report
- `failures.csv` - Failed requests log
- `report_*.txt` - Text summary

---

## Troubleshooting

### Connection Refused
```bash
# Check if API is accessible
curl -v https://mywsqa.barcapint.com/BLA/api-v1/preferences \
  -H "Content-Type: application/json" \
  -H "Proxy-Remote-User: kamanyas" \
  -d '{"data": {"level3": "data"}}'
```

### SSL Certificate Issues
```bash
# k6: Disable SSL verification
k6 run --insecure-skip-tls-verify k6-load-test.js

# curl: Use -k flag
curl -k https://...
```

### Timeout Issues
```bash
# Increase timeout
k6 run --http-timeout 60s k6-load-test.js
```
