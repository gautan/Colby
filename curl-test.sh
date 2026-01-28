#!/bin/bash

# ============================================
# Performance Test Script using cURL
# API: https://mywsqa.barcapint.com/BLA/api-v1/preferences
# ============================================

set -e

# ============================================
# CONFIGURATION
# ============================================

BASE_URL="${BASE_URL:-https://mywsqa.barcapint.com}"
ENDPOINT="/BLA/api-v1/preferences"
PROXY_USER="${PROXY_USER:-kamanyas}"
AUTH_TOKEN="${AUTH_TOKEN:-}"  # Bearer token
CONCURRENT_USERS="${CONCURRENT_USERS:-10}"
REQUESTS_PER_USER="${REQUESTS_PER_USER:-100}"
RESULTS_DIR="./results"
VERBOSE="${VERBOSE:-true}"
LOG_FILE="$RESULTS_DIR/test_$(date +%Y%m%d_%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# Counters
TOTAL_REQUESTS=0
SUCCESS_COUNT=0
FAIL_COUNT=0
TIMEOUT_COUNT=0
AUTH_ERROR_COUNT=0
VALIDATION_ERROR_COUNT=0
SERVER_ERROR_COUNT=0
TEST_NUMBER=0

# Arrays for response times
declare -a RESPONSE_TIMES

# Create results directory
mkdir -p "$RESULTS_DIR"

# ============================================
# LOGGING FUNCTIONS
# ============================================

log_info() { echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }
log_test() { echo -e "${BLUE}[TEST]${NC} $1" | tee -a "$LOG_FILE"; }
log_debug() { [[ "$VERBOSE" == "true" ]] && echo -e "${CYAN}[DEBUG]${NC} $1" | tee -a "$LOG_FILE"; }

timestamp() { date +"%Y-%m-%d %H:%M:%S.%3N"; }

print_separator() {
    echo -e "${WHITE}════════════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
}

print_section() {
    echo "" | tee -a "$LOG_FILE"
    print_separator
    echo -e "${WHITE}  $1${NC}" | tee -a "$LOG_FILE"
    print_separator
}

# ============================================
# REQUEST/RESPONSE LOGGING
# ============================================

log_request() {
    local method="$1"
    local url="$2"
    local headers="$3"
    local body="$4"

    echo "" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}┌──────────────────────────────────────────────────────────────┐${NC}" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}│ REQUEST                                                      │${NC}" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}├──────────────────────────────────────────────────────────────┤${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}│ Timestamp:${NC} $(timestamp)" | tee -a "$LOG_FILE"
    echo -e "${CYAN}│ Method:${NC}    $method" | tee -a "$LOG_FILE"
    echo -e "${CYAN}│ URL:${NC}       $url" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}├──────────────────────────────────────────────────────────────┤${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}│ Headers:${NC}" | tee -a "$LOG_FILE"
    echo "$headers" | while IFS= read -r line; do
        echo -e "│   $line" | tee -a "$LOG_FILE"
    done
    echo -e "${MAGENTA}├──────────────────────────────────────────────────────────────┤${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}│ Body:${NC}" | tee -a "$LOG_FILE"
    if [[ -n "$body" ]]; then
        echo "$body" | jq '.' 2>/dev/null | while IFS= read -r line; do
            echo -e "│   $line" | tee -a "$LOG_FILE"
        done || echo -e "│   $body" | tee -a "$LOG_FILE"
    else
        echo -e "│   (empty)" | tee -a "$LOG_FILE"
    fi
    echo -e "${MAGENTA}└──────────────────────────────────────────────────────────────┘${NC}" | tee -a "$LOG_FILE"
}

log_response() {
    local status="$1"
    local duration="$2"
    local headers="$3"
    local body="$4"
    local test_name="$5"

    local status_color="${RED}"
    local status_icon="✗"

    if [[ "$status" == "200" ]] || [[ "$status" == "201" ]]; then
        status_color="${GREEN}"
        status_icon="✓"
    elif [[ "$status" == "400" ]] || [[ "$status" == "401" ]] || [[ "$status" == "403" ]] || [[ "$status" == "404" ]] || [[ "$status" == "422" ]]; then
        status_color="${YELLOW}"
        status_icon="⚠"
    fi

    echo "" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}┌──────────────────────────────────────────────────────────────┐${NC}" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}│ RESPONSE                                                     │${NC}" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}├──────────────────────────────────────────────────────────────┤${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}│ Timestamp:${NC}    $(timestamp)" | tee -a "$LOG_FILE"
    echo -e "${CYAN}│ Test:${NC}         $test_name" | tee -a "$LOG_FILE"
    echo -e "${CYAN}│ Status:${NC}       ${status_color}${status_icon} $status${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}│ Duration:${NC}     ${duration}ms" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}├──────────────────────────────────────────────────────────────┤${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}│ Response Headers:${NC}" | tee -a "$LOG_FILE"
    echo "$headers" | while IFS= read -r line; do
        [[ -n "$line" ]] && echo -e "│   $line" | tee -a "$LOG_FILE"
    done
    echo -e "${MAGENTA}├──────────────────────────────────────────────────────────────┤${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}│ Response Body:${NC}" | tee -a "$LOG_FILE"
    if [[ -n "$body" ]]; then
        echo "$body" | jq '.' 2>/dev/null | while IFS= read -r line; do
            echo -e "│   $line" | tee -a "$LOG_FILE"
        done || echo -e "│   $body" | tee -a "$LOG_FILE"
    else
        echo -e "│   (empty)" | tee -a "$LOG_FILE"
    fi
    echo -e "${MAGENTA}└──────────────────────────────────────────────────────────────┘${NC}" | tee -a "$LOG_FILE"
}

# ============================================
# BUILD HEADERS
# ============================================

build_headers() {
    local include_auth="${1:-true}"
    local include_proxy="${2:-true}"
    local custom_proxy_user="${3:-$PROXY_USER}"
    local custom_content_type="${4:-application/json}"
    local custom_auth_token="${5:-$AUTH_TOKEN}"

    local headers=""
    headers+="Content-Type: $custom_content_type\n"
    headers+="Accept: application/json\n"
    headers+="X-Request-ID: $(uuidgen 2>/dev/null || echo "req-$(date +%s)-$RANDOM")\n"
    headers+="X-Correlation-ID: test-$(date +%Y%m%d%H%M%S)-$TEST_NUMBER\n"

    if [[ "$include_proxy" == "true" ]] && [[ -n "$custom_proxy_user" ]]; then
        headers+="Proxy-Remote-User: $custom_proxy_user\n"
    fi

    if [[ "$include_auth" == "true" ]] && [[ -n "$custom_auth_token" ]]; then
        headers+="Authorization: Bearer $custom_auth_token\n"
    fi

    echo -e "$headers"
}

build_curl_headers() {
    local include_auth="${1:-true}"
    local include_proxy="${2:-true}"
    local custom_proxy_user="${3:-$PROXY_USER}"
    local custom_content_type="${4:-application/json}"
    local custom_auth_token="${5:-$AUTH_TOKEN}"

    local curl_headers=""
    curl_headers+="-H 'Content-Type: $custom_content_type' "
    curl_headers+="-H 'Accept: application/json' "
    curl_headers+="-H 'X-Request-ID: $(uuidgen 2>/dev/null || echo "req-$(date +%s)-$RANDOM")' "
    curl_headers+="-H 'X-Correlation-ID: test-$(date +%Y%m%d%H%M%S)-$TEST_NUMBER' "

    if [[ "$include_proxy" == "true" ]] && [[ -n "$custom_proxy_user" ]]; then
        curl_headers+="-H 'Proxy-Remote-User: $custom_proxy_user' "
    fi

    if [[ "$include_auth" == "true" ]] && [[ -n "$custom_auth_token" ]]; then
        curl_headers+="-H 'Authorization: Bearer $custom_auth_token' "
    fi

    echo "$curl_headers"
}

# ============================================
# API REQUEST FUNCTION
# ============================================

make_request() {
    local payload="$1"
    local expected_status="$2"
    local test_name="$3"
    local timeout="${4:-30}"
    local include_auth="${5:-true}"
    local include_proxy="${6:-true}"
    local custom_proxy_user="${7:-$PROXY_USER}"
    local custom_content_type="${8:-application/json}"
    local custom_auth_token="${9:-$AUTH_TOKEN}"

    ((TEST_NUMBER++))
    local full_url="${BASE_URL}${ENDPOINT}"

    # Build headers for logging
    local log_headers=$(build_headers "$include_auth" "$include_proxy" "$custom_proxy_user" "$custom_content_type" "$custom_auth_token")

    # Log request
    log_request "POST" "$full_url" "$log_headers" "$payload"

    # Build curl command
    local curl_cmd="curl -s -w '\n%{http_code}\n%{time_total}\n%{size_download}' "
    curl_cmd+="-X POST '$full_url' "
    curl_cmd+="-H 'Content-Type: $custom_content_type' "
    curl_cmd+="-H 'Accept: application/json' "
    curl_cmd+="-H 'X-Request-ID: $(uuidgen 2>/dev/null || echo "req-$(date +%s)-$RANDOM")' "
    curl_cmd+="-H 'X-Correlation-ID: test-$(date +%Y%m%d%H%M%S)-$TEST_NUMBER' "

    if [[ "$include_proxy" == "true" ]] && [[ -n "$custom_proxy_user" ]]; then
        curl_cmd+="-H 'Proxy-Remote-User: $custom_proxy_user' "
    fi

    if [[ "$include_auth" == "true" ]] && [[ -n "$custom_auth_token" ]]; then
        curl_cmd+="-H 'Authorization: Bearer $custom_auth_token' "
    fi

    curl_cmd+="-d '$payload' "
    curl_cmd+="--max-time $timeout "
    curl_cmd+="-D - "  # Include response headers

    # Execute request
    local start_time=$(date +%s%N)

    local full_response=$(eval "$curl_cmd" 2>&1) || true

    local end_time=$(date +%s%N)
    local duration=$(( (end_time - start_time) / 1000000 ))

    # Parse response
    local response_headers=$(echo "$full_response" | sed -n '1,/^\r*$/p' | head -n -1)
    local response_body=$(echo "$full_response" | sed '1,/^\r*$/d' | head -n -3)
    local status=$(echo "$full_response" | tail -n 3 | head -n 1)
    local curl_time=$(echo "$full_response" | tail -n 2 | head -n 1)
    local response_size=$(echo "$full_response" | tail -n 1)

    # Handle empty/timeout status
    [[ -z "$status" ]] && status="000"
    [[ "$status" == "000" ]] && response_body="Connection timeout or refused"

    # Log response
    log_response "$status" "$duration" "$response_headers" "$response_body" "$test_name"

    # Track metrics
    RESPONSE_TIMES+=("$duration")
    ((TOTAL_REQUESTS++))

    # Determine result
    local result="FAIL"
    if [[ "$status" == "$expected_status" ]]; then
        ((SUCCESS_COUNT++))
        result="PASS"
        echo -e "${GREEN}[RESULT] ✓ PASS - $test_name (Expected: $expected_status, Got: $status, Duration: ${duration}ms)${NC}" | tee -a "$LOG_FILE"
    else
        ((FAIL_COUNT++))

        case "$status" in
            401|403) ((AUTH_ERROR_COUNT++)) ;;
            400|422) ((VALIDATION_ERROR_COUNT++)) ;;
            5*) ((SERVER_ERROR_COUNT++)) ;;
            000) ((TIMEOUT_COUNT++)) ;;
        esac

        echo -e "${RED}[RESULT] ✗ FAIL - $test_name (Expected: $expected_status, Got: $status, Duration: ${duration}ms)${NC}" | tee -a "$LOG_FILE"
        echo "$test_name,$status,$expected_status,$duration,\"$response_body\"" >> "$RESULTS_DIR/failures.csv"
    fi

    echo "" | tee -a "$LOG_FILE"
    return $([[ "$result" == "PASS" ]] && echo 0 || echo 1)
}

# ============================================
# TEST CASES - SUCCESS SCENARIOS
# ============================================

test_success_basic() {
    print_section "TEST: Success - Basic Valid Request"
    local payload='{"data": {"level3": "data"}}'
    make_request "$payload" "200" "Success - Basic Valid Request"
}

test_success_with_auth_token() {
    print_section "TEST: Success - With Bearer Token"
    local payload='{"data": {"level3": "data"}}'

    if [[ -z "$AUTH_TOKEN" ]]; then
        log_warn "AUTH_TOKEN not set, using dummy token for test"
        make_request "$payload" "200" "Success - With Bearer Token" "30" "true" "true" "$PROXY_USER" "application/json" "test-token-12345"
    else
        make_request "$payload" "200" "Success - With Bearer Token"
    fi
}

test_success_extra_fields() {
    print_section "TEST: Success - Extra Fields in Payload"
    local payload='{"data": {"level3": "data", "extra": "field", "another": 123}}'
    make_request "$payload" "200" "Success - Extra Fields"
}

test_success_unicode() {
    print_section "TEST: Success - Unicode Characters"
    local payload='{"data": {"level3": "测试数据 🎉 données тест"}}'
    make_request "$payload" "200" "Success - Unicode Characters"
}

test_success_special_chars() {
    print_section "TEST: Success - Special Characters"
    local payload='{"data": {"level3": "test\\n\\t\\r\\\"data\\\""}}'
    make_request "$payload" "200" "Success - Special Characters"
}

# ============================================
# TEST CASES - VALIDATION FAILURES
# ============================================

test_invalid_missing_field() {
    print_section "TEST: Validation - Missing Required Field"
    local payload='{"data": {}}'
    make_request "$payload" "400" "Validation - Missing Field"
}

test_invalid_wrong_type() {
    print_section "TEST: Validation - Wrong Data Type"
    local payload='{"data": {"level3": 12345}}'
    make_request "$payload" "400" "Validation - Wrong Type"
}

test_invalid_null_value() {
    print_section "TEST: Validation - Null Value"
    local payload='{"data": {"level3": null}}'
    make_request "$payload" "400" "Validation - Null Value"
}

test_invalid_empty_payload() {
    print_section "TEST: Validation - Empty Payload"
    local payload=''
    make_request "$payload" "400" "Validation - Empty Payload"
}

test_invalid_empty_object() {
    print_section "TEST: Validation - Empty Object"
    local payload='{}'
    make_request "$payload" "400" "Validation - Empty Object"
}

test_invalid_malformed_json() {
    print_section "TEST: Validation - Malformed JSON"
    local payload='{"data": {level3: "data"}}'  # Missing quotes
    make_request "$payload" "400" "Validation - Malformed JSON"
}

test_invalid_array_instead_object() {
    print_section "TEST: Validation - Array Instead of Object"
    local payload='{"data": ["level3", "data"]}'
    make_request "$payload" "400" "Validation - Array Instead of Object"
}

test_invalid_large_payload() {
    print_section "TEST: Validation - Large Payload (1MB)"
    local large_data=$(head -c 1048576 < /dev/zero | tr '\0' 'x')
    local payload="{\"data\": {\"level3\": \"$large_data\"}}"
    make_request "$payload" "413" "Validation - Large Payload" "60"
}

# ============================================
# TEST CASES - AUTHENTICATION FAILURES
# ============================================

test_auth_missing_proxy_header() {
    print_section "TEST: Auth - Missing Proxy-Remote-User Header"
    local payload='{"data": {"level3": "data"}}'
    make_request "$payload" "401" "Auth - Missing Proxy Header" "30" "true" "false"
}

test_auth_empty_proxy_user() {
    print_section "TEST: Auth - Empty Proxy-Remote-User"
    local payload='{"data": {"level3": "data"}}'
    make_request "$payload" "401" "Auth - Empty Proxy User" "30" "true" "true" ""
}

test_auth_invalid_user() {
    print_section "TEST: Auth - Invalid User"
    local payload='{"data": {"level3": "data"}}'
    make_request "$payload" "403" "Auth - Invalid User" "30" "true" "true" "nonexistent_user_12345"
}

test_auth_missing_bearer_token() {
    print_section "TEST: Auth - Missing Bearer Token"
    local payload='{"data": {"level3": "data"}}'
    make_request "$payload" "401" "Auth - Missing Bearer Token" "30" "false" "true"
}

test_auth_invalid_bearer_token() {
    print_section "TEST: Auth - Invalid Bearer Token"
    local payload='{"data": {"level3": "data"}}'
    make_request "$payload" "401" "Auth - Invalid Bearer Token" "30" "true" "true" "$PROXY_USER" "application/json" "invalid-token-xyz"
}

test_auth_expired_token() {
    print_section "TEST: Auth - Expired Token"
    local payload='{"data": {"level3": "data"}}'
    # Simulate expired JWT (this is a mock expired token)
    local expired_token="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiZXhwIjoxMDAwMDAwMDAwfQ.invalid"
    make_request "$payload" "401" "Auth - Expired Token" "30" "true" "true" "$PROXY_USER" "application/json" "$expired_token"
}

test_auth_malformed_bearer() {
    print_section "TEST: Auth - Malformed Bearer Header"
    local payload='{"data": {"level3": "data"}}'
    make_request "$payload" "401" "Auth - Malformed Bearer" "30" "true" "true" "$PROXY_USER" "application/json" "not-a-valid-format"
}

# ============================================
# TEST CASES - SECURITY
# ============================================

test_security_sql_injection_header() {
    print_section "TEST: Security - SQL Injection in Header"
    local payload='{"data": {"level3": "data"}}'
    make_request "$payload" "400" "Security - SQL Injection Header" "30" "true" "true" "admin'; DROP TABLE users;--"
}

test_security_sql_injection_payload() {
    print_section "TEST: Security - SQL Injection in Payload"
    local payload='{"data": {"level3": "data; DROP TABLE users;--"}}'
    make_request "$payload" "200" "Security - SQL Injection Payload"  # Should sanitize, not crash
}

test_security_xss_payload() {
    print_section "TEST: Security - XSS in Payload"
    local payload='{"data": {"level3": "<script>alert(\"xss\")</script>"}}'
    make_request "$payload" "200" "Security - XSS Payload"  # Should sanitize
}

test_security_path_traversal() {
    print_section "TEST: Security - Path Traversal"
    local payload='{"data": {"level3": "data"}}'
    make_request "$payload" "400" "Security - Path Traversal" "30" "true" "true" "../../../etc/passwd"
}

test_security_command_injection() {
    print_section "TEST: Security - Command Injection"
    local payload='{"data": {"level3": "data; cat /etc/passwd"}}'
    make_request "$payload" "200" "Security - Command Injection"  # Should not execute
}

test_security_xxe() {
    print_section "TEST: Security - XXE Attempt"
    local payload='{"data": {"level3": "<!DOCTYPE foo [<!ENTITY xxe SYSTEM \"file:///etc/passwd\">]><foo>&xxe;</foo>"}}'
    make_request "$payload" "200" "Security - XXE"  # Should not process
}

test_security_long_string() {
    print_section "TEST: Security - Very Long String (DoS)"
    local long_string=$(head -c 100000 < /dev/zero | tr '\0' 'A')
    local payload="{\"data\": {\"level3\": \"$long_string\"}}"
    make_request "$payload" "400" "Security - Long String" "60"
}

# ============================================
# TEST CASES - EDGE CASES
# ============================================

test_edge_timeout() {
    print_section "TEST: Edge Case - Request Timeout"
    local payload='{"data": {"level3": "data"}}'
    make_request "$payload" "000" "Edge Case - Timeout" "0.001"
}

test_edge_wrong_method() {
    print_section "TEST: Edge Case - Wrong HTTP Method (GET)"
    local full_url="${BASE_URL}${ENDPOINT}"

    log_request "GET" "$full_url" "$(build_headers)" ""

    local response=$(curl -s -w '\n%{http_code}\n%{time_total}' \
        -X GET "$full_url" \
        -H "Content-Type: application/json" \
        -H "Proxy-Remote-User: $PROXY_USER" \
        ${AUTH_TOKEN:+-H "Authorization: Bearer $AUTH_TOKEN"} \
        --max-time 30 \
        -D - \
        2>&1)

    local response_headers=$(echo "$response" | sed -n '1,/^\r*$/p')
    local response_body=$(echo "$response" | sed '1,/^\r*$/d' | head -n -2)
    local status=$(echo "$response" | tail -n 2 | head -n 1)

    log_response "$status" "N/A" "$response_headers" "$response_body" "Edge Case - Wrong Method"

    ((TOTAL_REQUESTS++))
    if [[ "$status" == "405" ]] || [[ "$status" == "404" ]]; then
        ((SUCCESS_COUNT++))
        echo -e "${GREEN}[RESULT] ✓ PASS - Wrong method correctly rejected${NC}" | tee -a "$LOG_FILE"
    else
        ((FAIL_COUNT++))
        echo -e "${RED}[RESULT] ✗ FAIL - Expected 405, got $status${NC}" | tee -a "$LOG_FILE"
    fi
}

test_edge_wrong_content_type() {
    print_section "TEST: Edge Case - Wrong Content-Type"
    local payload='{"data": {"level3": "data"}}'
    make_request "$payload" "415" "Edge Case - Wrong Content-Type" "30" "true" "true" "$PROXY_USER" "text/plain"
}

test_edge_duplicate_headers() {
    print_section "TEST: Edge Case - Duplicate Headers"
    local payload='{"data": {"level3": "data"}}'
    local full_url="${BASE_URL}${ENDPOINT}"

    local response=$(curl -s -w '\n%{http_code}' \
        -X POST "$full_url" \
        -H "Content-Type: application/json" \
        -H "Proxy-Remote-User: $PROXY_USER" \
        -H "Proxy-Remote-User: another_user" \
        ${AUTH_TOKEN:+-H "Authorization: Bearer $AUTH_TOKEN"} \
        -d "$payload" \
        --max-time 30 \
        2>&1)

    local status=$(echo "$response" | tail -n 1)
    ((TOTAL_REQUESTS++))

    log_info "Duplicate headers test - Status: $status"

    if [[ "$status" == "200" ]] || [[ "$status" == "400" ]]; then
        ((SUCCESS_COUNT++))
    else
        ((FAIL_COUNT++))
    fi
}

# ============================================
# LOAD TEST FUNCTION
# ============================================

run_load_test() {
    local users=$1
    local requests=$2

    print_section "LOAD TEST: $users concurrent users, $requests requests each"

    local start_time=$(date +%s)
    local pids=()

    for user in $(seq 1 $users); do
        (
            for req in $(seq 1 $requests); do
                curl -s -o /dev/null -w "%{http_code},%{time_total}\n" \
                    -X POST "${BASE_URL}${ENDPOINT}" \
                    -H "Content-Type: application/json" \
                    -H "Proxy-Remote-User: $PROXY_USER" \
                    ${AUTH_TOKEN:+-H "Authorization: Bearer $AUTH_TOKEN"} \
                    -d '{"data": {"level3": "data"}}' \
                    --max-time 30 >> "$RESULTS_DIR/load_test_user_${user}.csv" 2>&1
                sleep 0.1
            done
        ) &
        pids+=($!)
    done

    # Wait for all background processes
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_info "Load test completed in ${duration}s"

    # Aggregate results
    local total=0
    local success=0
    local failed=0

    for file in "$RESULTS_DIR"/load_test_user_*.csv; do
        while IFS=',' read -r status time; do
            ((total++))
            if [[ "$status" == "200" ]]; then
                ((success++))
            else
                ((failed++))
            fi
        done < "$file"
    done

    log_info "Load Test Results: Total=$total, Success=$success, Failed=$failed"
}

# ============================================
# CALCULATE STATISTICS
# ============================================

calculate_stats() {
    if [ ${#RESPONSE_TIMES[@]} -eq 0 ]; then
        echo "No response times recorded"
        return
    fi

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

    print_section "RESPONSE TIME STATISTICS"
    echo -e "│ Total Requests: $count" | tee -a "$LOG_FILE"
    echo -e "│ Min:            ${min}ms" | tee -a "$LOG_FILE"
    echo -e "│ Max:            ${max}ms" | tee -a "$LOG_FILE"
    echo -e "│ Average:        ${avg}ms" | tee -a "$LOG_FILE"
    echo -e "│ P50 (Median):   ${sorted[$p50_idx]}ms" | tee -a "$LOG_FILE"
    echo -e "│ P95:            ${sorted[$p95_idx]}ms" | tee -a "$LOG_FILE"
    echo -e "│ P99:            ${sorted[$p99_idx]}ms" | tee -a "$LOG_FILE"
}

# ============================================
# GENERATE REPORT
# ============================================

generate_report() {
    print_section "TEST EXECUTION SUMMARY"

    local success_rate=0
    if [ $TOTAL_REQUESTS -gt 0 ]; then
        success_rate=$(echo "scale=2; $SUCCESS_COUNT * 100 / $TOTAL_REQUESTS" | bc)
    fi

    echo -e "│ Timestamp:          $(timestamp)" | tee -a "$LOG_FILE"
    echo -e "│ Base URL:           $BASE_URL" | tee -a "$LOG_FILE"
    echo -e "│ Endpoint:           $ENDPOINT" | tee -a "$LOG_FILE"
    echo -e "│ Proxy User:         $PROXY_USER" | tee -a "$LOG_FILE"
    echo -e "│ Auth Token:         ${AUTH_TOKEN:+[SET]}${AUTH_TOKEN:-[NOT SET]}" | tee -a "$LOG_FILE"
    echo -e "│" | tee -a "$LOG_FILE"
    echo -e "│ Total Requests:     $TOTAL_REQUESTS" | tee -a "$LOG_FILE"
    echo -e "│ ${GREEN}Successful:${NC}         $SUCCESS_COUNT" | tee -a "$LOG_FILE"
    echo -e "│ ${RED}Failed:${NC}             $FAIL_COUNT" | tee -a "$LOG_FILE"
    echo -e "│ Success Rate:       ${success_rate}%" | tee -a "$LOG_FILE"
    echo -e "│" | tee -a "$LOG_FILE"
    echo -e "│ ${YELLOW}Error Breakdown:${NC}" | tee -a "$LOG_FILE"
    echo -e "│   Timeout Errors:     $TIMEOUT_COUNT" | tee -a "$LOG_FILE"
    echo -e "│   Auth Errors:        $AUTH_ERROR_COUNT" | tee -a "$LOG_FILE"
    echo -e "│   Validation Errors:  $VALIDATION_ERROR_COUNT" | tee -a "$LOG_FILE"
    echo -e "│   Server Errors:      $SERVER_ERROR_COUNT" | tee -a "$LOG_FILE"

    calculate_stats

    print_section "FINAL RESULT"

    if [ $FAIL_COUNT -eq 0 ]; then
        echo -e "│ ${GREEN}✓ ALL TESTS PASSED${NC}" | tee -a "$LOG_FILE"
    else
        echo -e "│ ${RED}✗ $FAIL_COUNT TEST(S) FAILED${NC}" | tee -a "$LOG_FILE"
        echo -e "│ See $RESULTS_DIR/failures.csv for details" | tee -a "$LOG_FILE"
    fi

    print_separator
    log_info "Full log saved to: $LOG_FILE"
}

# ============================================
# MAIN
# ============================================

main() {
    print_section "PERFORMANCE TEST SUITE"
    echo -e "│ Base URL:    $BASE_URL" | tee -a "$LOG_FILE"
    echo -e "│ Endpoint:    $ENDPOINT" | tee -a "$LOG_FILE"
    echo -e "│ Proxy User:  $PROXY_USER" | tee -a "$LOG_FILE"
    echo -e "│ Auth Token:  ${AUTH_TOKEN:+[CONFIGURED]}${AUTH_TOKEN:-[NOT SET]}" | tee -a "$LOG_FILE"
    echo -e "│ Verbose:     $VERBOSE" | tee -a "$LOG_FILE"
    echo -e "│ Log File:    $LOG_FILE" | tee -a "$LOG_FILE"
    print_separator

    # Initialize failures CSV
    echo "test_name,actual_status,expected_status,duration_ms,response_body" > "$RESULTS_DIR/failures.csv"

    case "${1:-all}" in
        success)
            log_info "Running success tests..."
            test_success_basic
            test_success_with_auth_token
            test_success_extra_fields
            test_success_unicode
            test_success_special_chars
            ;;
        validation)
            log_info "Running validation tests..."
            test_invalid_missing_field
            test_invalid_wrong_type
            test_invalid_null_value
            test_invalid_empty_payload
            test_invalid_empty_object
            test_invalid_malformed_json
            test_invalid_array_instead_object
            ;;
        auth)
            log_info "Running authentication tests..."
            test_auth_missing_proxy_header
            test_auth_empty_proxy_user
            test_auth_invalid_user
            test_auth_missing_bearer_token
            test_auth_invalid_bearer_token
            test_auth_expired_token
            test_auth_malformed_bearer
            ;;
        security)
            log_info "Running security tests..."
            test_security_sql_injection_header
            test_security_sql_injection_payload
            test_security_xss_payload
            test_security_path_traversal
            test_security_command_injection
            test_security_xxe
            test_security_long_string
            ;;
        edge)
            log_info "Running edge case tests..."
            test_edge_wrong_method
            test_edge_wrong_content_type
            test_edge_duplicate_headers
            ;;
        load)
            log_info "Running load test..."
            run_load_test "$CONCURRENT_USERS" "$REQUESTS_PER_USER"
            ;;
        stress)
            log_info "Running stress test..."
            run_load_test 50 100
            run_load_test 100 100
            run_load_test 200 50
            ;;
        functional)
            log_info "Running all functional tests..."
            test_success_basic
            test_success_with_auth_token
            test_invalid_missing_field
            test_invalid_wrong_type
            test_auth_missing_proxy_header
            test_auth_invalid_bearer_token
            test_edge_wrong_method
            ;;
        all)
            log_info "Running ALL tests..."
            # Success
            test_success_basic
            test_success_with_auth_token
            test_success_extra_fields
            test_success_unicode
            test_success_special_chars
            # Validation
            test_invalid_missing_field
            test_invalid_wrong_type
            test_invalid_null_value
            test_invalid_empty_payload
            test_invalid_empty_object
            test_invalid_malformed_json
            test_invalid_array_instead_object
            # Auth
            test_auth_missing_proxy_header
            test_auth_empty_proxy_user
            test_auth_invalid_user
            test_auth_missing_bearer_token
            test_auth_invalid_bearer_token
            test_auth_expired_token
            # Security
            test_security_sql_injection_header
            test_security_sql_injection_payload
            test_security_xss_payload
            test_security_path_traversal
            # Edge Cases
            test_edge_wrong_method
            test_edge_wrong_content_type
            test_edge_duplicate_headers
            ;;
        *)
            echo "Usage: $0 {success|validation|auth|security|edge|load|stress|functional|all}"
            echo ""
            echo "Test Categories:"
            echo "  success     - Valid request tests"
            echo "  validation  - Invalid payload tests"
            echo "  auth        - Authentication/Authorization tests"
            echo "  security    - Security vulnerability tests"
            echo "  edge        - Edge case tests"
            echo "  load        - Load testing"
            echo "  stress      - Stress testing"
            echo "  functional  - Quick functional test suite"
            echo "  all         - Run all tests"
            echo ""
            echo "Environment Variables:"
            echo "  BASE_URL       - API base URL (default: https://mywsqa.barcapint.com)"
            echo "  PROXY_USER     - Proxy-Remote-User header value (default: kamanyas)"
            echo "  AUTH_TOKEN     - Bearer token for Authorization header"
            echo "  VERBOSE        - Enable verbose logging (default: true)"
            echo ""
            echo "Example:"
            echo "  AUTH_TOKEN=your-token ./curl-test.sh all"
            exit 1
            ;;
    esac

    generate_report
}

main "$@"
