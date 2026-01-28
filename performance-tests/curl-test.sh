#!/bin/bash

# ============================================
# Performance Test Script using cURL
# API: https://mywsqa.barcapint.com/BLA/api-v1/preferences
# ============================================

set -e

# Configuration
BASE_URL="${BASE_URL:-https://mywsqa.barcapint.com}"
ENDPOINT="/BLA/api-v1/preferences"
PROXY_USER="${PROXY_USER:-kamanyas}"
CONCURRENT_USERS="${CONCURRENT_USERS:-10}"
REQUESTS_PER_USER="${REQUESTS_PER_USER:-100}"
RESULTS_DIR="./results"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL_REQUESTS=0
SUCCESS_COUNT=0
FAIL_COUNT=0
TIMEOUT_COUNT=0
AUTH_ERROR_COUNT=0
VALIDATION_ERROR_COUNT=0
SERVER_ERROR_COUNT=0

# Arrays for response times
declare -a RESPONSE_TIMES

# Create results directory
mkdir -p "$RESULTS_DIR"

# ============================================
# Helper Functions
# ============================================

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_test() { echo -e "${BLUE}[TEST]${NC} $1"; }

timestamp() { date +"%Y-%m-%d %H:%M:%S"; }

# ============================================
# API Request Function
# ============================================

make_request() {
    local payload="$1"
    local headers="$2"
    local expected_status="$3"
    local test_name="$4"
    local timeout="${5:-30}"

    local start_time=$(date +%s%N)

    local response=$(curl -s -w "\n%{http_code}\n%{time_total}" \
        -X POST "${BASE_URL}${ENDPOINT}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        $headers \
        -d "$payload" \
        --max-time "$timeout" \
        2>&1) || true

    local end_time=$(date +%s%N)
    local duration=$(( (end_time - start_time) / 1000000 ))

    # Parse response
    local body=$(echo "$response" | head -n -2)
    local status=$(echo "$response" | tail -n 2 | head -n 1)
    local curl_time=$(echo "$response" | tail -n 1)

    RESPONSE_TIMES+=("$duration")
    ((TOTAL_REQUESTS++))

    # Check result
    if [[ "$status" == "$expected_status" ]]; then
        ((SUCCESS_COUNT++))
        return 0
    else
        ((FAIL_COUNT++))

        case "$status" in
            401|403) ((AUTH_ERROR_COUNT++)) ;;
            400|422) ((VALIDATION_ERROR_COUNT++)) ;;
            5*) ((SERVER_ERROR_COUNT++)) ;;
            000) ((TIMEOUT_COUNT++)) ;;
        esac

        echo "$test_name,$status,$expected_status,$duration,$body" >> "$RESULTS_DIR/failures.csv"
        return 1
    fi
}

# ============================================
# Test Cases
# ============================================

test_success() {
    log_test "Running: Success Scenario"
    local payload='{"data": {"level3": "data"}}'
    local headers="-H \"Proxy-Remote-User: $PROXY_USER\""

    make_request "$payload" "$headers" "200" "success"
}

test_invalid_payload_missing_field() {
    log_test "Running: Invalid Payload - Missing Field"
    local payload='{"data": {}}'
    local headers="-H \"Proxy-Remote-User: $PROXY_USER\""

    make_request "$payload" "$headers" "400" "invalid_payload_missing"
}

test_invalid_payload_wrong_type() {
    log_test "Running: Invalid Payload - Wrong Type"
    local payload='{"data": {"level3": 123}}'
    local headers="-H \"Proxy-Remote-User: $PROXY_USER\""

    make_request "$payload" "$headers" "400" "invalid_payload_type"
}

test_invalid_payload_null() {
    log_test "Running: Invalid Payload - Null Value"
    local payload='{"data": {"level3": null}}'
    local headers="-H \"Proxy-Remote-User: $PROXY_USER\""

    make_request "$payload" "$headers" "400" "invalid_payload_null"
}

test_missing_auth_header() {
    log_test "Running: Missing Auth Header"
    local payload='{"data": {"level3": "data"}}'
    local headers=""

    make_request "$payload" "$headers" "401" "missing_auth"
}

test_invalid_user() {
    log_test "Running: Invalid User"
    local payload='{"data": {"level3": "data"}}'
    local headers="-H \"Proxy-Remote-User: nonexistent_user_12345\""

    make_request "$payload" "$headers" "403" "invalid_user"
}

test_empty_user() {
    log_test "Running: Empty User"
    local payload='{"data": {"level3": "data"}}'
    local headers="-H \"Proxy-Remote-User: \""

    make_request "$payload" "$headers" "401" "empty_user"
}

test_sql_injection() {
    log_test "Running: SQL Injection Attempt"
    local payload='{"data": {"level3": "data"}}'
    local headers="-H \"Proxy-Remote-User: admin'; DROP TABLE users;--\""

    # Should return 400 or 403, not 500
    make_request "$payload" "$headers" "400" "sql_injection"
}

test_xss_attempt() {
    log_test "Running: XSS Attempt"
    local payload='{"data": {"level3": "<script>alert(1)</script>"}}'
    local headers="-H \"Proxy-Remote-User: $PROXY_USER\""

    make_request "$payload" "$headers" "400" "xss_attempt"
}

test_empty_payload() {
    log_test "Running: Empty Payload"
    local payload=''
    local headers="-H \"Proxy-Remote-User: $PROXY_USER\""

    make_request "$payload" "$headers" "400" "empty_payload"
}

test_empty_object() {
    log_test "Running: Empty Object"
    local payload='{}'
    local headers="-H \"Proxy-Remote-User: $PROXY_USER\""

    make_request "$payload" "$headers" "400" "empty_object"
}

test_malformed_json() {
    log_test "Running: Malformed JSON"
    local payload='{"data": {level3: "data"}}'
    local headers="-H \"Proxy-Remote-User: $PROXY_USER\""

    make_request "$payload" "$headers" "400" "malformed_json"
}

test_large_payload() {
    log_test "Running: Large Payload (1MB)"
    local large_data=$(head -c 1048576 < /dev/zero | tr '\0' 'x')
    local payload="{\"data\": {\"level3\": \"$large_data\"}}"
    local headers="-H \"Proxy-Remote-User: $PROXY_USER\""

    make_request "$payload" "$headers" "413" "large_payload" "60"
}

test_timeout() {
    log_test "Running: Timeout Test"
    local payload='{"data": {"level3": "data"}}'
    local headers="-H \"Proxy-Remote-User: $PROXY_USER\""

    # Very short timeout
    make_request "$payload" "$headers" "000" "timeout" "0.001"
}

test_concurrent_requests() {
    log_test "Running: Concurrent Requests"
    local payload='{"data": {"level3": "data"}}'

    for i in $(seq 1 10); do
        curl -s -o /dev/null -w "%{http_code}" \
            -X POST "${BASE_URL}${ENDPOINT}" \
            -H "Content-Type: application/json" \
            -H "Proxy-Remote-User: $PROXY_USER" \
            -d "$payload" &
    done
    wait
}

test_wrong_method() {
    log_test "Running: Wrong HTTP Method (GET)"

    local response=$(curl -s -w "\n%{http_code}" \
        -X GET "${BASE_URL}${ENDPOINT}" \
        -H "Content-Type: application/json" \
        -H "Proxy-Remote-User: $PROXY_USER" \
        2>&1)

    local status=$(echo "$response" | tail -n 1)

    if [[ "$status" == "405" ]] || [[ "$status" == "404" ]]; then
        ((SUCCESS_COUNT++))
    else
        ((FAIL_COUNT++))
        log_warn "Wrong method test: expected 405, got $status"
    fi
    ((TOTAL_REQUESTS++))
}

test_wrong_content_type() {
    log_test "Running: Wrong Content-Type"
    local payload='{"data": {"level3": "data"}}'

    local response=$(curl -s -w "\n%{http_code}" \
        -X POST "${BASE_URL}${ENDPOINT}" \
        -H "Content-Type: text/plain" \
        -H "Proxy-Remote-User: $PROXY_USER" \
        -d "$payload" \
        2>&1)

    local status=$(echo "$response" | tail -n 1)

    if [[ "$status" == "415" ]] || [[ "$status" == "400" ]]; then
        ((SUCCESS_COUNT++))
    else
        ((FAIL_COUNT++))
    fi
    ((TOTAL_REQUESTS++))
}

test_special_characters() {
    log_test "Running: Special Characters in Payload"
    local payload='{"data": {"level3": "test\n\t\r\"\\"}}'
    local headers="-H \"Proxy-Remote-User: $PROXY_USER\""

    make_request "$payload" "$headers" "200" "special_chars"
}

test_unicode() {
    log_test "Running: Unicode Characters"
    local payload='{"data": {"level3": "测试数据 🎉 données"}}'
    local headers="-H \"Proxy-Remote-User: $PROXY_USER\""

    make_request "$payload" "$headers" "200" "unicode"
}

# ============================================
# Load Test Function
# ============================================

run_load_test() {
    local users=$1
    local requests=$2

    log_info "Starting load test: $users concurrent users, $requests requests each"

    local start_time=$(date +%s)

    for user in $(seq 1 $users); do
        (
            for req in $(seq 1 $requests); do
                test_success > /dev/null 2>&1
                sleep 0.1
            done
        ) &
    done

    wait

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_info "Load test completed in ${duration}s"
}

# ============================================
# Calculate Statistics
# ============================================

calculate_stats() {
    if [ ${#RESPONSE_TIMES[@]} -eq 0 ]; then
        echo "No response times recorded"
        return
    fi

    # Sort response times
    IFS=$'\n' sorted=($(sort -n <<<"${RESPONSE_TIMES[*]}")); unset IFS

    local count=${#sorted[@]}
    local sum=0
    local min=${sorted[0]}
    local max=${sorted[$((count-1))]}

    for t in "${sorted[@]}"; do
        ((sum+=t))
    done

    local avg=$((sum / count))
    local p50_idx=$((count * 50 / 100))
    local p95_idx=$((count * 95 / 100))
    local p99_idx=$((count * 99 / 100))

    echo ""
    echo "============================================"
    echo "RESPONSE TIME STATISTICS"
    echo "============================================"
    echo "Min:     ${min}ms"
    echo "Max:     ${max}ms"
    echo "Avg:     ${avg}ms"
    echo "P50:     ${sorted[$p50_idx]}ms"
    echo "P95:     ${sorted[$p95_idx]}ms"
    echo "P99:     ${sorted[$p99_idx]}ms"
}

# ============================================
# Generate Report
# ============================================

generate_report() {
    local report_file="$RESULTS_DIR/report_$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "============================================"
        echo "PERFORMANCE TEST REPORT"
        echo "============================================"
        echo "Timestamp: $(timestamp)"
        echo "Base URL: $BASE_URL"
        echo "Endpoint: $ENDPOINT"
        echo ""
        echo "============================================"
        echo "REQUEST SUMMARY"
        echo "============================================"
        echo "Total Requests:     $TOTAL_REQUESTS"
        echo "Successful:         $SUCCESS_COUNT"
        echo "Failed:             $FAIL_COUNT"
        echo "Success Rate:       $(echo "scale=2; $SUCCESS_COUNT * 100 / $TOTAL_REQUESTS" | bc)%"
        echo ""
        echo "============================================"
        echo "ERROR BREAKDOWN"
        echo "============================================"
        echo "Timeout Errors:     $TIMEOUT_COUNT"
        echo "Auth Errors:        $AUTH_ERROR_COUNT"
        echo "Validation Errors:  $VALIDATION_ERROR_COUNT"
        echo "Server Errors:      $SERVER_ERROR_COUNT"

        calculate_stats

        echo ""
        echo "============================================"
        echo "TEST RESULTS"
        echo "============================================"

        if [ $FAIL_COUNT -eq 0 ]; then
            echo -e "${GREEN}ALL TESTS PASSED${NC}"
        else
            echo -e "${RED}$FAIL_COUNT TESTS FAILED${NC}"
            echo "See $RESULTS_DIR/failures.csv for details"
        fi

    } | tee "$report_file"

    log_info "Report saved to $report_file"
}

# ============================================
# Main
# ============================================

main() {
    echo ""
    echo "============================================"
    echo "PERFORMANCE TEST SUITE"
    echo "============================================"
    echo "Base URL: $BASE_URL"
    echo "Endpoint: $ENDPOINT"
    echo "User: $PROXY_USER"
    echo "============================================"
    echo ""

    # Initialize failures CSV
    echo "test_name,actual_status,expected_status,duration_ms,response_body" > "$RESULTS_DIR/failures.csv"

    case "${1:-all}" in
        functional)
            log_info "Running functional tests..."
            test_success
            test_invalid_payload_missing_field
            test_invalid_payload_wrong_type
            test_invalid_payload_null
            test_missing_auth_header
            test_invalid_user
            test_empty_user
            test_empty_payload
            test_empty_object
            test_malformed_json
            test_wrong_method
            test_wrong_content_type
            test_special_characters
            test_unicode
            ;;
        security)
            log_info "Running security tests..."
            test_sql_injection
            test_xss_attempt
            test_missing_auth_header
            test_invalid_user
            ;;
        load)
            log_info "Running load test..."
            run_load_test "$CONCURRENT_USERS" "$REQUESTS_PER_USER"
            ;;
        stress)
            log_info "Running stress test..."
            run_load_test 50 200
            run_load_test 100 200
            run_load_test 200 100
            ;;
        all)
            log_info "Running all tests..."
            # Functional tests
            test_success
            test_invalid_payload_missing_field
            test_invalid_payload_wrong_type
            test_invalid_payload_null
            test_missing_auth_header
            test_invalid_user
            test_empty_user
            test_sql_injection
            test_xss_attempt
            test_empty_payload
            test_empty_object
            test_malformed_json
            test_large_payload
            test_wrong_method
            test_wrong_content_type
            test_special_characters
            test_unicode
            test_concurrent_requests
            ;;
        *)
            echo "Usage: $0 {functional|security|load|stress|all}"
            exit 1
            ;;
    esac

    generate_report
}

main "$@"
