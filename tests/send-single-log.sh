#!/usr/bin/env bash
###
# File: send-single-log.sh
# Project: tests
###

set -euo pipefail

# --- Locate and load .env from the parent directory of this script (if present) ---
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PARENT_DIR="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
ENV_FILE="${PARENT_DIR}/.env"

# Load .env without overriding any pre-set environment variables
if [[ -f "${ENV_FILE}" ]]; then
    echo "Loading environment from: ${ENV_FILE} (without overriding existing env)"
    # Strip CRLF, comments, and blank lines, then only export keys not already set.
    while IFS= read -r line; do
        # Require KEY=VAL format (POSIX-ish var name)
        [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
        key="${line%%=*}"
        val="${line#*=}"
        # If $key is unset, export from .env; otherwise keep existing env value
        if [[ -z "${!key+x}" ]]; then
            # Use eval so quoted values in .env are respected (e.g., FOO="a b")
            eval "export $key=$val"
        fi
    done < <(sed -e 's/\r$//' -e '/^\s*#/d' -e '/^\s*$/d' "${ENV_FILE}")
fi

# --- Helpers ---
is_true() {
    # case-insensitive: true/t/yes/y/1
    shopt -s nocasematch
    [[ "${1:-}" =~ ^(true|t|yes|y|1)$ ]]
}

detect_ip() {
    local ip
    ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
    if [[ -z "$ip" ]]; then
        ip="$(ip -4 addr show scope global up 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)"
    fi
    echo "${ip:-127.0.0.1}"
}

# --- Base defaults (may be overridden below) ---
FORWARD_OUTPUT_HOST="${FORWARD_OUTPUT_HOST:-$(detect_ip)}"
FORWARD_OUTPUT_PORT="${FORWARD_OUTPUT_PORT:-}"
FORWARD_OUTPUT_SHARED_KEY="${FORWARD_OUTPUT_SHARED_KEY:-}"
FORWARD_OUTPUT_TLS="${FORWARD_OUTPUT_TLS:-}"
FORWARD_OUTPUT_TLS_VERIFY="${FORWARD_OUTPUT_TLS_VERIFY:-}"

TAG_PREFIX="${FLUENT_BIT_TAG_PREFIX:-flb.}stdout_debug."

# --- Selection logic based on env/.env (env already has priority) ---
# Priority: TLS input (if enabled) > PT input (if enabled) > keep defaults
if is_true "${ENABLE_FLUENTBIT_TLS_FORWARD_INPUT:-false}"; then
    [[ -z "${FORWARD_OUTPUT_TLS:-}" ]] && FORWARD_OUTPUT_TLS="on"
    [[ -z "${FORWARD_OUTPUT_TLS_VERIFY:-}" ]] && FORWARD_OUTPUT_TLS_VERIFY="${FLUENTBIT_TLS_FORWARD_INPUT_VERIFY:-off}"
    [[ -z "${FORWARD_OUTPUT_PORT:-}" ]] && FORWARD_OUTPUT_PORT="${FLUENTBIT_TLS_FORWARD_INPUT_PORT:-24224}"
    if [[ -z "${FORWARD_OUTPUT_SHARED_KEY:-}" ]]; then
        [[ -n "${FLUENTBIT_TLS_FORWARD_INPUT_SHARED_KEY:-}" ]] &&
            FORWARD_OUTPUT_SHARED_KEY="${FLUENTBIT_TLS_FORWARD_INPUT_SHARED_KEY}"
    fi

elif is_true "${ENABLE_FLUENTBIT_PT_FORWARD_INPUT:-false}"; then
    [[ -z "${FORWARD_OUTPUT_TLS:-}" ]] && FORWARD_OUTPUT_TLS="off"
    [[ -z "${FORWARD_OUTPUT_TLS_VERIFY:-}" ]] && FORWARD_OUTPUT_TLS_VERIFY="${FLUENTBIT_TLS_FORWARD_INPUT_VERIFY:-off}"
    [[ -z "${FORWARD_OUTPUT_PORT:-}" ]] && FORWARD_OUTPUT_PORT="${FLUENTBIT_TLS_FORWARD_INPUT_PORT:-24228}"
fi

# --- Payload timestamps ---
EPOCH_SECONDS="$(date +%s)"
RFC3339_TIME="$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ)"

# --- Show effective config ---
echo "FORWARD_OUTPUT_HOST:              ${FORWARD_OUTPUT_HOST:?}"
echo "FORWARD_OUTPUT_PORT:              ${FORWARD_OUTPUT_PORT:?}"
echo "FORWARD_OUTPUT_SHARED_KEY:        ${FORWARD_OUTPUT_SHARED_KEY:-}"
echo "FORWARD_OUTPUT_TLS:               ${FORWARD_OUTPUT_TLS:?}"
echo "FORWARD_OUTPUT_TLS_VERIFY:        ${FORWARD_OUTPUT_TLS_VERIFY:?}"
echo "FLUENT_BIT_TAG_PREFIX:            ${TAG_PREFIX:?}"

# --- Build nested JSON with jq ---
MESSAGE_OBJ="$(jq -cn '
{
  taskName: null,
  filename: "glogging.py",
  funcName: "access",
  levelname: "INFO",
  lineno: 123,
  module: "glogging",
  name: "gunicorn.access",
  pathname: "/var/venv-docker/lib/python3.12/site-packages/gunicorn/glogging.py",
  process: 321,
  processName: "MainProcess",
  stack_info: null,
  thread: 131494281823936,
  threadName: "ThreadPoolExecutor-0_0",
  message: {
    remote_ip: "69.12.252.27",
    x_forwarded_for: "69.12.252.27",
    method: "GET",
    path: "/v2/path/thing",
    status: "200",
    time: "2025-08-15T03:57:39+00:00",
    response_length: "70",
    user_agent: "python-requests/2.32.4",
    referer: "-",
    duration_in_ms: 15,
    pid: "<321>"
  },
  "source.env": "not-sandbox",
  "source.service": "some-fake-service",
  "source.version": "678869c6"
}
')"

DUMMY_JSON="$(
    jq -cn \
        --arg epoch "$EPOCH_SECONDS" \
        --arg rfc3339 "$RFC3339_TIME" \
        --argjson msg "$MESSAGE_OBJ" \
        '{
     level: 6,
     container_name: "/test-logging-container",
     levelname: "info",
     source_project: "manually-deployed",
     source_version: "1234",
     timestamp: ($epoch|tonumber),
     service_name: "testing-service",
     source_service: "testing-service",
     source_account: "544038296934",
     container_id: "1b5be6c727325117c4278c9f81a92bbc726e288805fd3f0f56a6d1f35466888a",
     message: $msg,
     time: $rfc3339,
     source: "stdout",
     source_env: "sandbox"
   }'
)"

# --- Build fluent-bit args (conditionally include shared_key and tls.verify) ---
FB_ARGS=(
    /fluent-bit/bin/fluent-bit
    -i dummy
    -p "dummy=${DUMMY_JSON}"
    -o forward
    -p "host=${FORWARD_OUTPUT_HOST}"
    -p "port=${FORWARD_OUTPUT_PORT}"
    -p "tls=${FORWARD_OUTPUT_TLS}"
    -p "self_hostname=test-fluentbit"
    -p "tag=${TAG_PREFIX}test-service"
    -f 1
)

# Add tls.verify only if TLS is on
if [[ "${FORWARD_OUTPUT_TLS}" == "on" ]]; then
    FB_ARGS+=(-p "tls.verify=${FORWARD_OUTPUT_TLS_VERIFY}")
fi

# Add shared_key only if TLS is on AND a key is set
if [[ "${FORWARD_OUTPUT_TLS}" == "on" && -n "${FORWARD_OUTPUT_SHARED_KEY}" ]]; then
    FB_ARGS+=(-p "shared_key=${FORWARD_OUTPUT_SHARED_KEY}")
fi

# --- Run Fluent Bit once with the nested JSON payload ---
sudo docker stop fluent-bit-router-single-log-test &> /dev/null || true
sudo docker rm fluent-bit-router-single-log-test &> /dev/null || true
sudo docker run --rm --name fluent-bit-router-single-log-test fluent/fluent-bit:latest "${FB_ARGS[@]}"

echo "DONE"
