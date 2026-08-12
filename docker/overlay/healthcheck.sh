#!/usr/bin/env bash
set -euo pipefail

# 1. Check Fluent Bit HTTP monitoring API health endpoint
HTTP_SERVER_PORT="${HTTP_SERVER_PORT:-2020}"
if ! curl -fs "http://127.0.0.1:${HTTP_SERVER_PORT}/" >/dev/null 2>&1 && \
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
