#!/bin/bash
set -euo pipefail

# Test runner for fluent-bit-router configuration generation and dry-run validation

FAILED_TESTS=0
TOTAL_TESTS=0

run_test() {
    local test_name="$1"
    shift
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo "======================================================================"
    echo "TEST #${TOTAL_TESTS}: ${test_name}"
    echo "======================================================================"

    local test_dir
    test_dir=$(mktemp -d /tmp/flb-test-XXXXXX)
    mkdir -p "${test_dir}/storage" "${test_dir}/certs" "${test_dir}/custom"

    # Create mock certs for testing TLS
    touch "${test_dir}/certs/fluent-bit.pem"

    if (
        export CUSTOM_CONFIG_PATH="${test_dir}/custom"
        export FLUENT_STORAGE_PATH="${test_dir}/storage"
        export CERTIFICATES_DIRECTORY="${test_dir}/certs"
        export USE_EXISTING_CERT="true"
        export EXISTING_CERT_PATH="${test_dir}/certs/fluent-bit.pem"
        export EXISTING_KEY_PATH="${test_dir}/certs/fluent-bit.pem"
        export DRY_RUN_CONFIG_ONLY="true"
        export "$@"

        # Test configuration generation
        ENTRYPOINT_BIN="${ENTRYPOINT_SCRIPT:-/entrypoint.sh}"
        if [ ! -f "${ENTRYPOINT_BIN}" ] && [ -f "./docker/overlay/entrypoint.sh" ]; then
            ENTRYPOINT_BIN="./docker/overlay/entrypoint.sh"
        fi
        bash -c "
            set -e
            ${ENTRYPOINT_BIN} config_test 2>&1 || true
        "
    ); then
        # Check if fluent-bit.yaml was created
        if [ -f "${test_dir}/custom/fluent-bit.yaml" ]; then
            echo "Config generated. Validating with /opt/fluent-bit/bin/fluent-bit --dry-run..."
            if /opt/fluent-bit/bin/fluent-bit --dry-run -c "${test_dir}/custom/fluent-bit.yaml"; then
                echo ">>> PASS: ${test_name}"
            else
                echo ">>> FAIL (Fluent Bit dry-run rejected generated config): ${test_name}"
                FAILED_TESTS=$((FAILED_TESTS + 1))
            fi
        else
            echo ">>> FAIL (fluent-bit.yaml was not generated): ${test_name}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        echo ">>> FAIL (Entrypoint execution error): ${test_name}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    rm -rf "${test_dir}"
    echo
}

echo "Starting Fluent Bit Router Configuration Validation Test Suite..."
echo

# 1. Default Router Configuration
run_test "Default router configuration (defaults, no optional I/O)" \
    HOST_HOSTNAME="router-test"

# 2. All Inputs Enabled
run_test "All inputs enabled with input-tailored pause policies" \
    HOST_HOSTNAME="router-test" \
    ENABLE_HTTP_INPUT="true" \
    ENABLE_TLS_FORWARD_INPUT="true" \
    TLS_FORWARD_INPUT_SHARED_KEY="testkey123" \
    ENABLE_PT_FORWARD_INPUT="true" \
    ENABLE_DOCKER_FORWARD_INPUT="true" \
    ENABLE_SYSTEMD_INPUT="true" \
    ENABLE_AUTH_LOG_INPUT="true" \
    ENABLE_AUDIT_LOG_INPUT="true" \
    ENABLE_AWS_SSM_INPUT="true"

# 3. Threaded network inputs enabled
run_test "Threaded network inputs enabled" \
    HOST_HOSTNAME="router-test" \
    ENABLE_HTTP_INPUT="true" \
    ENABLE_TLS_FORWARD_INPUT="true" \
    TLS_FORWARD_INPUT_SHARED_KEY="testkey123" \
    ENABLE_THREADED_NETWORK_INPUTS="true"

# 4. All Outputs Enabled with custom storage limits
run_test "All outputs enabled with custom limits and retries" \
    HOST_HOSTNAME="router-test" \
    ENABLE_STDOUT_OUTPUT="true" \
    ENABLE_GRAFANA_LOKI_OUTPUT="true" \
    GRAFANA_LOKI_HOST="loki.internal" \
    GRAFANA_LOKI_BUFFER_STORAGE_TOTAL_LIMIT_SIZE="4G" \
    GRAFANA_LOKI_RETRY_LIMIT="15" \
    ENABLE_OPENOBSERVE_HTTP_OUTPUT="true" \
    OPENOBSERVE_HTTP_HOST="openobserve.internal" \
    OPENOBSERVE_HTTP_BUFFER_STORAGE_TOTAL_LIMIT_SIZE="8G" \
    OPENOBSERVE_HTTP_RETRY_LIMIT="false" \
    ENABLE_GRAYLOG_GELF_OUTPUT="true" \
    GRAYLOG_GELF_HOST="graylog.internal" \
    GRAYLOG_GELF_BUFFER_STORAGE_TOTAL_LIMIT_SIZE="1G" \
    GRAYLOG_GELF_RETRY_LIMIT="3" \
    ENABLE_S3_BUCKET_COLD_STORAGE_OUTPUT="true" \
    AWS_COLD_STORAGE_BUCKET_NAME="log-archive" \
    AWS_COLD_STORAGE_BUCKET_REGION="us-east-1" \
    AWS_COLD_STORAGE_BUFFER_STORE_DIR_LIMIT_SIZE="20G" \
    AWS_COLD_STORAGE_RETRY_LIMIT="10" \
    ENABLE_TLS_FORWARD_OUTPUT="true" \
    TLS_FORWARD_OUTPUT_HOST="upstream.internal" \
    TLS_FORWARD_OUTPUT_PORT="24224" \
    TLS_FORWARD_OUTPUT_SHARED_KEY="secret" \
    TLS_FORWARD_OUTPUT_BUFFER_STORAGE_TOTAL_LIMIT_SIZE="5G" \
    TLS_FORWARD_OUTPUT_RETRY_LIMIT="false" \
    ENABLE_PT_FORWARD_OUTPUT="true" \
    PT_FORWARD_OUTPUT_HOST="pt-upstream.internal" \
    PT_FORWARD_OUTPUT_PORT="24228" \
    PT_FORWARD_OUTPUT_BUFFER_STORAGE_TOTAL_LIMIT_SIZE="2G" \
    PT_FORWARD_OUTPUT_RETRY_LIMIT="5"

# 5. Service storage options: max_chunks_up, backlog limit, sync full, checksum on
run_test "Custom service storage parameters (sync=full, checksum=on, max_chunks_up=256)" \
    HOST_HOSTNAME="router-test" \
    FLUENT_STORAGE_MAX_CHUNKS_UP="256" \
    FLUENT_STORAGE_BACKLOG_MEM_LIMIT="50M" \
    FLUENT_STORAGE_SYNC="full" \
    FLUENT_STORAGE_CHECKSUM="on" \
    ENABLE_HTTP_INPUT="true" \
    ENABLE_GRAFANA_LOKI_OUTPUT="true" \
    GRAFANA_LOKI_HOST="loki.internal"

# 6. Global fallback limit FLUENT_OUTPUT_BUFFER_STORAGE_TOTAL_LIMIT_SIZE
run_test "Global fallback limit FLUENT_OUTPUT_BUFFER_STORAGE_TOTAL_LIMIT_SIZE=7G" \
    HOST_HOSTNAME="router-test" \
    FLUENT_OUTPUT_BUFFER_STORAGE_TOTAL_LIMIT_SIZE="7G" \
    ENABLE_GRAFANA_LOKI_OUTPUT="true" \
    GRAFANA_LOKI_HOST="loki.internal" \
    ENABLE_OPENOBSERVE_HTTP_OUTPUT="true" \
    OPENOBSERVE_HTTP_HOST="openobserve.internal"

# 7. Healthcheck container max lifetime timeout test
TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo "======================================================================"
echo "TEST #${TOTAL_TESTS}: Healthcheck max lifetime timeout expiration"
echo "======================================================================"
HEALTHCHECK_BIN="./docker/overlay/healthcheck.sh"
if [ ! -f "${HEALTHCHECK_BIN}" ]; then
    HEALTHCHECK_BIN="/healthcheck.sh"
fi

FOUR_HOURS_AGO=$(($(date +%s) - 14400))
echo "${FOUR_HOURS_AGO}" >/tmp/.fluent-bit-start-time

if CONTAINER_MAX_LIFETIME_HOURS=3 bash "${HEALTHCHECK_BIN}" >/dev/null 2>&1; then
    echo ">>> FAIL (Healthcheck should have failed for expired lifetime)"
    FAILED_TESTS=$((FAILED_TESTS + 1))
else
    echo ">>> PASS: Healthcheck reported unhealthy as expected when lifetime exceeded"
fi
rm -f /tmp/.fluent-bit-start-time

echo "======================================================================"
echo "TEST RESULTS: ${TOTAL_TESTS} run, $((TOTAL_TESTS - FAILED_TESTS)) passed, ${FAILED_TESTS} failed"
echo "======================================================================"

if [ "${FAILED_TESTS}" -gt 0 ]; then
    exit 1
fi
