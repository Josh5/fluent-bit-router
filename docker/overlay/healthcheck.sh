#!/usr/bin/env bash
set -euo pipefail

# 1. Check Container Maximum Lifetime / Auto-Recycle Timeout
CONTAINER_MAX_LIFETIME_HOURS="${CONTAINER_MAX_LIFETIME_HOURS:-}"
if [[ -n "${CONTAINER_MAX_LIFETIME_HOURS}" && "${CONTAINER_MAX_LIFETIME_HOURS}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    START_TIME_FILE="/tmp/.fluent-bit-start-time"
    if [ -f "${START_TIME_FILE}" ]; then
        START_TIME_EPOCH=$(cat "${START_TIME_FILE}" 2>/dev/null || echo 0)
        CURRENT_TIME_EPOCH=$(date +%s)
        # Calculate max lifetime in seconds (supports integer or decimal hours)
        MAX_LIFETIME_SECONDS=$(awk -v hours="${CONTAINER_MAX_LIFETIME_HOURS}" 'BEGIN { printf "%.0f", hours * 3600 }')
        ELAPSED_SECONDS=$((CURRENT_TIME_EPOCH - START_TIME_EPOCH))

        if [ "${ELAPSED_SECONDS}" -ge "${MAX_LIFETIME_SECONDS}" ]; then
            echo "HEALTHCHECK ERROR: Container has exceeded configured maximum lifetime of ${CONTAINER_MAX_LIFETIME_HOURS} hour(s) (${ELAPSED_SECONDS}s elapsed >= ${MAX_LIFETIME_SECONDS}s limit). Reporting unhealthy to trigger restart." >&2
            exit 1
        fi
    fi
fi

# 2. Check Fluent Bit HTTP monitoring API health endpoint
HTTP_SERVER_PORT="${HTTP_SERVER_PORT:-2020}"
if ! curl -fs "http://127.0.0.1:${HTTP_SERVER_PORT}/" >/dev/null 2>&1 &&
    ! curl -fs "http://127.0.0.1:${HTTP_SERVER_PORT}/api/v1/health" >/dev/null 2>&1; then
    echo "HEALTHCHECK ERROR: Fluent Bit HTTP monitoring endpoint on port ${HTTP_SERVER_PORT} is not responding." >&2
    exit 1
fi

# 2. Check Certificate Expiration if TLS Forward Input is enabled
if [[ -n "${ENABLE_TLS_FORWARD_INPUT:-}" && "${ENABLE_TLS_FORWARD_INPUT,,}" =~ ^(true|t)$ ]]; then
    CERTIFICATES_DIRECTORY="${CERTIFICATES_DIRECTORY:-/etc/fluent-bit/certs}"
    CERTIFICATE_FILE_PATH="${CERTIFICATES_DIRECTORY}/fluent-bit.pem"
    # Allow a 2-day buffer relative to entrypoint.sh (which uses 14 days)
    DAYS_BEFORE_EXPIRATION=12

    if [ ! -f "${CERTIFICATE_FILE_PATH}" ]; then
        echo "HEALTHCHECK ERROR: TLS Forward Input is enabled, but certificate '${CERTIFICATE_FILE_PATH}' does not exist." >&2
        exit 1
    fi

    EXPIRATION_DATE=$(openssl x509 -enddate -noout -in "${CERTIFICATE_FILE_PATH}" | cut -d= -f2 || true)
    if [ -z "${EXPIRATION_DATE}" ]; then
        echo "HEALTHCHECK ERROR: Unable to read expiration date from certificate '${CERTIFICATE_FILE_PATH}'." >&2
        exit 1
    fi

    EXPIRATION_DATE_EPOCH=$(date -d "$(echo "${EXPIRATION_DATE}" | sed "s/ GMT//")" +%s 2>/dev/null || echo 0)
    CURRENT_DATE_EPOCH=$(date +%s)
    THRESHOLD=$((DAYS_BEFORE_EXPIRATION * 86400))

    if [ "$((EXPIRATION_DATE_EPOCH - CURRENT_DATE_EPOCH))" -lt "$THRESHOLD" ]; then
        echo "HEALTHCHECK ERROR: Certificate '${CERTIFICATE_FILE_PATH}' is expired or expiring within ${DAYS_BEFORE_EXPIRATION} days." >&2
        exit 1
    fi
fi

exit 0
