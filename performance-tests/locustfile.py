"""
Locust Performance Test Script
API: https://mywsqa.barcapint.com/BLA/api-v1/preferences

Install: pip install locust
Run: locust -f locustfile.py --host=https://mywsqa.barcapint.com
Web UI: http://localhost:8089

Headless mode:
locust -f locustfile.py --host=https://mywsqa.barcapint.com \
    --headless -u 100 -r 10 -t 5m
"""

import json
import random
import string
import time
from locust import HttpUser, task, between, events
from locust.runners import MasterRunner, WorkerRunner

# ============================================
# CONFIGURATION
# ============================================

API_ENDPOINT = "/BLA/api-v1/preferences"
PROXY_USER = "kamanyas"

# ============================================
# METRICS TRACKING
# ============================================

class MetricsCollector:
    def __init__(self):
        self.success_count = 0
        self.failure_count = 0
        self.auth_errors = 0
        self.validation_errors = 0
        self.server_errors = 0
        self.timeout_errors = 0

metrics = MetricsCollector()

# ============================================
# EVENT HANDLERS
# ============================================

@events.request.add_listener
def on_request(request_type, name, response_time, response_length, response, context, exception, **kwargs):
    if exception:
        metrics.failure_count += 1
        if "timeout" in str(exception).lower():
            metrics.timeout_errors += 1
    elif response:
        if response.status_code == 200:
            metrics.success_count += 1
        elif response.status_code in [401, 403]:
            metrics.auth_errors += 1
        elif response.status_code in [400, 422]:
            metrics.validation_errors += 1
        elif response.status_code >= 500:
            metrics.server_errors += 1

@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    print("\n" + "=" * 50)
    print("CUSTOM METRICS SUMMARY")
    print("=" * 50)
    print(f"Success Count: {metrics.success_count}")
    print(f"Failure Count: {metrics.failure_count}")
    print(f"Auth Errors: {metrics.auth_errors}")
    print(f"Validation Errors: {metrics.validation_errors}")
    print(f"Server Errors: {metrics.server_errors}")
    print(f"Timeout Errors: {metrics.timeout_errors}")
    print("=" * 50)

# ============================================
# HELPER FUNCTIONS
# ============================================

def get_valid_payload():
    """Returns a valid API payload"""
    return {
        "data": {
            "level3": "data"
        }
    }

def get_headers(user=PROXY_USER, content_type="application/json"):
    """Returns request headers"""
    headers = {
        "Content-Type": content_type,
        "Accept": "application/json",
    }
    if user:
        headers["Proxy-Remote-User"] = user
    return headers

def random_string(length=10):
    """Generate random string"""
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

# ============================================
# USER BEHAVIORS
# ============================================

class PreferencesAPIUser(HttpUser):
    """Main user class for API testing"""

    wait_time = between(1, 3)  # Wait 1-3 seconds between tasks

    # ============================================
    # SUCCESS SCENARIOS (Weight: 60%)
    # ============================================

    @task(60)
    def success_request(self):
        """Normal successful request"""
        payload = get_valid_payload()
        headers = get_headers()

        with self.client.post(
            API_ENDPOINT,
            json=payload,
            headers=headers,
            name="Success - Normal Request",
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Expected 200, got {response.status_code}")

    @task(10)
    def success_with_extra_data(self):
        """Request with additional valid data"""
        payload = {
            "data": {
                "level3": "data",
                "extra_field": random_string()
            }
        }
        headers = get_headers()

        with self.client.post(
            API_ENDPOINT,
            json=payload,
            headers=headers,
            name="Success - Extra Data",
            catch_response=True
        ) as response:
            # This might return 200 or 400 depending on API behavior
            if response.status_code in [200, 400]:
                response.success()
            else:
                response.failure(f"Unexpected status: {response.status_code}")

    # ============================================
    # VALIDATION FAILURE SCENARIOS (Weight: 15%)
    # ============================================

    @task(3)
    def invalid_payload_missing_field(self):
        """Missing required field"""
        payload = {"data": {}}
        headers = get_headers()

        with self.client.post(
            API_ENDPOINT,
            json=payload,
            headers=headers,
            name="Failure - Missing Field",
            catch_response=True
        ) as response:
            if response.status_code in [400, 422]:
                response.success()
            else:
                response.failure(f"Expected 400/422, got {response.status_code}")

    @task(3)
    def invalid_payload_wrong_type(self):
        """Wrong data type"""
        payload = {"data": {"level3": 12345}}
        headers = get_headers()

        with self.client.post(
            API_ENDPOINT,
            json=payload,
            headers=headers,
            name="Failure - Wrong Type",
            catch_response=True
        ) as response:
            if response.status_code in [400, 422]:
                response.success()
            else:
                response.failure(f"Expected 400/422, got {response.status_code}")

    @task(3)
    def invalid_payload_null(self):
        """Null value"""
        payload = {"data": {"level3": None}}
        headers = get_headers()

        with self.client.post(
            API_ENDPOINT,
            json=payload,
            headers=headers,
            name="Failure - Null Value",
            catch_response=True
        ) as response:
            if response.status_code in [400, 422]:
                response.success()
            else:
                response.failure(f"Expected 400/422, got {response.status_code}")

    @task(3)
    def empty_payload(self):
        """Empty request body"""
        headers = get_headers()

        with self.client.post(
            API_ENDPOINT,
            data="",
            headers=headers,
            name="Failure - Empty Payload",
            catch_response=True
        ) as response:
            if response.status_code == 400:
                response.success()
            else:
                response.failure(f"Expected 400, got {response.status_code}")

    @task(3)
    def malformed_json(self):
        """Malformed JSON"""
        headers = get_headers()
        malformed = '{"data": {level3: "data"}}'  # Missing quotes

        with self.client.post(
            API_ENDPOINT,
            data=malformed,
            headers=headers,
            name="Failure - Malformed JSON",
            catch_response=True
        ) as response:
            if response.status_code == 400:
                response.success()
            else:
                response.failure(f"Expected 400, got {response.status_code}")

    # ============================================
    # AUTH FAILURE SCENARIOS (Weight: 10%)
    # ============================================

    @task(3)
    def missing_auth_header(self):
        """Missing Proxy-Remote-User header"""
        payload = get_valid_payload()
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

        with self.client.post(
            API_ENDPOINT,
            json=payload,
            headers=headers,
            name="Auth Failure - Missing Header",
            catch_response=True
        ) as response:
            if response.status_code in [401, 403]:
                response.success()
            elif response.status_code == 200:
                response.failure("Security issue: Request succeeded without auth header")
            else:
                response.failure(f"Expected 401/403, got {response.status_code}")

    @task(3)
    def invalid_user(self):
        """Invalid user"""
        payload = get_valid_payload()
        headers = get_headers(user="nonexistent_user_" + random_string())

        with self.client.post(
            API_ENDPOINT,
            json=payload,
            headers=headers,
            name="Auth Failure - Invalid User",
            catch_response=True
        ) as response:
            if response.status_code in [401, 403]:
                response.success()
            else:
                response.failure(f"Expected 401/403, got {response.status_code}")

    @task(2)
    def empty_user(self):
        """Empty user header"""
        payload = get_valid_payload()
        headers = get_headers(user="")

        with self.client.post(
            API_ENDPOINT,
            json=payload,
            headers=headers,
            name="Auth Failure - Empty User",
            catch_response=True
        ) as response:
            if response.status_code in [401, 403]:
                response.success()
            else:
                response.failure(f"Expected 401/403, got {response.status_code}")

    # ============================================
    # SECURITY TEST SCENARIOS (Weight: 5%)
    # ============================================

    @task(1)
    def sql_injection_attempt(self):
        """SQL injection in header"""
        payload = get_valid_payload()
        headers = get_headers(user="admin'; DROP TABLE users;--")

        with self.client.post(
            API_ENDPOINT,
            json=payload,
            headers=headers,
            name="Security - SQL Injection",
            catch_response=True
        ) as response:
            if response.status_code in [400, 401, 403]:
                response.success()
            elif response.status_code >= 500:
                response.failure("Server error on SQL injection - potential vulnerability")
            else:
                response.failure(f"Unexpected response: {response.status_code}")

    @task(1)
    def xss_attempt(self):
        """XSS in payload"""
        payload = {"data": {"level3": "<script>alert('xss')</script>"}}
        headers = get_headers()

        with self.client.post(
            API_ENDPOINT,
            json=payload,
            headers=headers,
            name="Security - XSS Attempt",
            catch_response=True
        ) as response:
            if response.status_code in [200, 400]:
                # Check if response is sanitized
                if "<script>" in response.text:
                    response.failure("XSS not sanitized in response")
                else:
                    response.success()
            else:
                response.failure(f"Unexpected status: {response.status_code}")

    @task(1)
    def path_traversal(self):
        """Path traversal in header"""
        payload = get_valid_payload()
        headers = get_headers(user="../../../etc/passwd")

        with self.client.post(
            API_ENDPOINT,
            json=payload,
            headers=headers,
            name="Security - Path Traversal",
            catch_response=True
        ) as response:
            if response.status_code in [400, 401, 403]:
                response.success()
            elif response.status_code >= 500:
                response.failure("Server error on path traversal")
            else:
                response.failure(f"Unexpected: {response.status_code}")

    # ============================================
    # EDGE CASE SCENARIOS (Weight: 10%)
    # ============================================

    @task(2)
    def large_payload(self):
        """Large payload test"""
        large_data = "x" * 100000  # 100KB
        payload = {"data": {"level3": large_data}}
        headers = get_headers()

        with self.client.post(
            API_ENDPOINT,
            json=payload,
            headers=headers,
            name="Edge Case - Large Payload",
            catch_response=True,
            timeout=60
        ) as response:
            if response.status_code in [200, 413, 400]:
                response.success()
            else:
                response.failure(f"Unexpected: {response.status_code}")

    @task(2)
    def unicode_payload(self):
        """Unicode characters in payload"""
        payload = {"data": {"level3": "测试 🎉 données тест"}}
        headers = get_headers()

        with self.client.post(
            API_ENDPOINT,
            json=payload,
            headers=headers,
            name="Edge Case - Unicode",
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Unicode not handled: {response.status_code}")

    @task(2)
    def special_characters(self):
        """Special characters in payload"""
        payload = {"data": {"level3": "test\n\t\r\"'\\"}}
        headers = get_headers()

        with self.client.post(
            API_ENDPOINT,
            json=payload,
            headers=headers,
            name="Edge Case - Special Chars",
            catch_response=True
        ) as response:
            if response.status_code in [200, 400]:
                response.success()
            else:
                response.failure(f"Unexpected: {response.status_code}")

    @task(2)
    def concurrent_rapid_requests(self):
        """Rapid consecutive requests"""
        payload = get_valid_payload()
        headers = get_headers()

        for i in range(5):
            with self.client.post(
                API_ENDPOINT,
                json=payload,
                headers=headers,
                name=f"Edge Case - Rapid Request {i+1}",
                catch_response=True
            ) as response:
                if response.status_code in [200, 429]:  # 429 = rate limited
                    response.success()
                else:
                    response.failure(f"Unexpected: {response.status_code}")


# ============================================
# STRESS TEST USER
# ============================================

class StressTestUser(HttpUser):
    """High-frequency user for stress testing"""

    wait_time = between(0.1, 0.5)  # Very short wait

    @task
    def stress_request(self):
        """Rapid fire requests"""
        payload = get_valid_payload()
        headers = get_headers()

        self.client.post(
            API_ENDPOINT,
            json=payload,
            headers=headers,
            name="Stress Test"
        )


# ============================================
# SPIKE TEST USER
# ============================================

class SpikeTestUser(HttpUser):
    """User for spike testing - immediate requests"""

    wait_time = between(0, 0.1)

    @task
    def spike_request(self):
        """Spike request"""
        payload = get_valid_payload()
        headers = get_headers()

        self.client.post(
            API_ENDPOINT,
            json=payload,
            headers=headers,
            name="Spike Test"
        )
