#!/usr/bin/env bash
###
# File: entrypoint.sh
# Project: overlay
# File Created: Friday, 18th October 2024 5:05:51 pm
# Author: Josh5 (jsunnex@gmail.com)
# -----
# Last Modified: Tuesday, 4th August 2026 5:36:45 pm
# Modified By: Josh.5 (jsunnex@gmail.com)
###
set -eu

################################################
# --- Create Logging Function
#
print_log() {
    timestamp=$(date +'%Y/%m/%d %H:%M:%S')
    level="$1"
    shift
    message="$*"
    echo "[${timestamp}] [ ${level}] ${message}"
}

################################################
# --- Create Missing Directories
#
print_log "info" "Creating any missing directories."
mkdir -p \
    "${FLUENT_STORAGE_PATH:?}" \
    "${CERTIFICATES_DIRECTORY:?}"

################################################
# --- Configure buffering defaults
#
FLUENT_STORAGE_MAX_CHUNKS_UP="${FLUENT_STORAGE_MAX_CHUNKS_UP:-128}"
FLUENT_STORAGE_BACKLOG_MEM_LIMIT="${FLUENT_STORAGE_BACKLOG_MEM_LIMIT:-20M}"
FLUENT_INPUT_MEM_BUF_LIMIT="${FLUENT_INPUT_MEM_BUF_LIMIT:-64M}"
FLUENT_REWRITE_TAG_EMITTER_MEM_BUF_LIMIT="${FLUENT_REWRITE_TAG_EMITTER_MEM_BUF_LIMIT:-64M}"
HOST_HOSTNAME="${HOST_HOSTNAME:-$(hostname)}"

################################################
# --- Create certificates
#
print_log "info" "Generating certificates in '${CERTIFICATES_DIRECTORY:?}'"
export CERTIFICATE_FILE_PATH="${CERTIFICATES_DIRECTORY:?}/fluent-bit.pem"
if [[ -n "${ENABLE_TLS_FORWARD_INPUT:-}" && "${ENABLE_TLS_FORWARD_INPUT,,}" =~ ^(true|t)$ ]]; then
    if [ -f "${CERTIFICATE_FILE_PATH:?}" ]; then
        print_log "info" "Checking expiration date on existing ${CERTIFICATE_FILE_PATH:?}"
        # Days before expiration to check
        DAYS_BEFORE_EXPIRATION=14
        # Get the expiration date of the certificate in seconds since epoch
        EXPIRATION_DATE=$(openssl x509 -enddate -noout -in "${CERTIFICATE_FILE_PATH:?}" | cut -d= -f2 || echo "Unable to load certificate")
        if [ "X${EXPIRATION_DATE:-}" = "X" ]; then
            # Invalid file
            print_log "info" "Certificate ${CERTIFICATE_FILE_PATH:?} appears to be invalid. Deleting..."
            rm -f "${CERTIFICATE_FILE_PATH:?}"
        else
            date -d "$(echo $EXPIRATION_DATE | sed "s/ GMT//")" +%s
            EXPIRATION_DATE_EPOCH=$(date -d "$(echo $EXPIRATION_DATE | sed "s/ GMT//")" +%s 2>/dev/null)
            # Get the current date in seconds since epoch
            CURRENT_DATE_EPOCH=$(date +%s)
            # Calculate the number of seconds in 14 days (14 * 86400)
            THRESHOLD=$((DAYS_BEFORE_EXPIRATION * 86400))
            # Check if the certificate will expire within the next 14 days
            if [ "$((EXPIRATION_DATE_EPOCH - CURRENT_DATE_EPOCH))" -lt "$THRESHOLD" ]; then
                # Not After date is earlier or equal to the current date (expired or expiring today)
                print_log "info" "Certificate ${CERTIFICATE_FILE_PATH:?} has expired or is expiring in the next 14 days. Deleting..."
                rm -f "${CERTIFICATE_FILE_PATH:?}"
            else
                print_log "info" "Certificate ${CERTIFICATE_FILE_PATH:?} is still valid until ${EXPIRATION_DATE:?}."
            fi
        fi
    fi

    if [[ -z "${USE_EXISTING_CERT:-}" || "${USE_EXISTING_CERT,,}" =~ ^(false|f)$ ]]; then
        print_log "info" "Configured to not use an existing cert."
    else
        if [ -f "${EXISTING_KEY_PATH:-}" ] && [ -f "${EXISTING_CERT_PATH:-}" ]; then
            print_log "info" "Using supplied ${EXISTING_KEY_PATH:?} and ${EXISTING_CERT_PATH:?} files to create ${CERTIFICATE_FILE_PATH:?}."
            cat ${EXISTING_KEY_PATH:?} ${EXISTING_CERT_PATH:?} >"${CERTIFICATE_FILE_PATH:?}"
        else
            print_log "info" "Configured to use an existing cert, but no EXISTING_KEY_PATH variable configured or the path in the variable EXISTING_KEY_PATH does not exsist."
        fi
    fi

    if [ ! -f "${CERTIFICATE_FILE_PATH:?}" ]; then
        print_log "info" "Certificate ${CERTIFICATE_FILE_PATH:?} does not exist. Creating a new one."
        if [ "X${CERT_FQDN:-}" != "X" ]; then
            HOST_HOSTNAME="${CERT_FQDN:?}"
        fi
        if [[ -n "${USE_CERTBOT_TO_GENERATE_KEY:-}" && "${USE_CERTBOT_TO_GENERATE_KEY,,}" =~ ^(true|t)$ ]]; then
            print_log "info" "Waiting for Nginx proxy container..."
            sleep 5
            i=1
            while [ $i -le 60 ]; do
                if [ -f "/var/www/certbot/.proxy-running" ]; then
                    print_log "info" "  - The Nginx proxy container is running"
                    rm -f "/var/www/certbot/.proxy-running"
                    break
                fi
                print_log "info" "  - Nginx proxy container check #$i - Not yet running. Recheck in 5 seconds..."
                sleep 5
                i=$((i + 1))
            done
            # Sleep here to wait long enough to ensure nginx is running
            print_log "info" "Pausing startup for 10 seconds to ensure Nginx service has completed startup for certbot certifiacte creation..."
            sleep 10
            echo

            print_log "info" "Running certbot command..."
            rm -rf "${CERTIFICATES_DIRECTORY:?}"/letsencrypt
            if certbot certonly \
                --webroot \
                --webroot-path /var/www/certbot \
                -d "${HOST_HOSTNAME:?}" \
                --email "${CERT_EMAIL:?}" \
                --agree-tos \
                --no-eff-email \
                --non-interactive \
                --config-dir "${CERTIFICATES_DIRECTORY:?}/letsencrypt/etc" \
                --logs-dir "${CERTIFICATES_DIRECTORY:?}/letsencrypt/logs" \
                --work-dir "${CERTIFICATES_DIRECTORY:?}/letsencrypt/work"; then

                cat \
                    "${CERTIFICATES_DIRECTORY:?}/letsencrypt/etc/live/${CERT_FQDN:?}/fullchain.pem" \
                    "${CERTIFICATES_DIRECTORY:?}/letsencrypt/etc/live/${CERT_FQDN:?}/privkey.pem" \
                    >"${CERTIFICATE_FILE_PATH:?}"
            else
                print_log "error" "Certbot failed to obtain certificate. Sleeping for 10 minutes before exiting."
                sleep 600
                exit 1
            fi
        else
            print_log "info" "Creating self-signed certificate ${CERTIFICATE_FILE_PATH:?}..."
            openssl req -new -x509 \
                -days 1095 \
                -newkey rsa:4096 \
                -sha256 \
                -nodes \
                -keyout "${CERTIFICATE_FILE_PATH:?}" \
                -out "${CERTIFICATE_FILE_PATH:?}" \
                -subj "/CN=${HOST_HOSTNAME:?}"
        fi
    fi
fi

################################################
# --- Configure Fluent-bit
#
CUSTOM_CONFIG_PATH="/tmp/fluent-bit-custom"
mkdir -p "${CUSTOM_CONFIG_PATH:?}"
cp -rf /etc/fluent-bit/* "${CUSTOM_CONFIG_PATH:?}/"
touch "${CUSTOM_CONFIG_PATH:?}/plugins.conf"

# Specify a ** match in single quotes if no prefix was provided
output_tag_match_key="match"
output_tag_match="${FLUENT_BIT_TAG_PREFIX:-}**"
if [ -z "${FLUENT_BIT_TAG_PREFIX:-}" ]; then
    # If no prefix, use regex to match everything EXCEPT our internal formatted tags
    output_tag_match_key="match_regex"
    output_tag_match="^(?!.*_fmt\.).*"

    # Patch fluent-bit.yaml to use regex for the main lua filters to avoid double-formatting
    print_log "info" "Configuring main Lua filters to exclude internal rewritten tags (using Match_Regex)"
    sed -i 's/match: ${FLUENT_BIT_TAG_PREFIX}\*/match_regex: ^(?!.*_fmt\\.).*/g' "${CUSTOM_CONFIG_PATH:?}/fluent-bit.yaml"
fi

input_storage_lines() {
    cat <<EOF
      mem_buf_limit: ${FLUENT_INPUT_MEM_BUF_LIMIT}
      storage.type: filesystem
      storage.pause_on_chunks_overlimit: on
EOF
}

# Fluent HTTP Input
if [[ "${ENABLE_HTTP_INPUT,,}" =~ ^(t|true)$ ]]; then
    print_log "info" "Adding HTTP input"
    yaml_file="fluent-bit.http.input.yaml"
    cat <<EOF >"${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
pipeline:
  inputs:
    # HTTP input to sit behind an LB
    - name: http
      listen: 0.0.0.0
      port: ${HTTP_INPUT_PORT:?}
$(input_storage_lines)
      buffer_chunk_size: 5M
      buffer_max_size: 1000M
      threaded: ${ENABLE_THREADED_INPUTS:-false,,}
EOF
    sed -i "s/^\(\s*\)#-\( ${yaml_file:?}\)/\1- ${yaml_file:?}/" "${CUSTOM_CONFIG_PATH:?}/fluent-bit.yaml"
    echo
    echo "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
    cat "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
else
    print_log "info" "Leaving HTTP input disabled"
fi

# Fluent Forward TLS Input
if [[ "${ENABLE_TLS_FORWARD_INPUT,,}" =~ ^(t|true)$ ]]; then
    print_log "info" "Adding TLS Forward input"
    yaml_file="fluent-bit.tls-forward.input.yaml"
    cat <<EOF >"${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
pipeline:
  inputs:
    # TLS Forward input
    - name: forward
      listen: 0.0.0.0
      port: ${TLS_FORWARD_INPUT_PORT:?}
      shared_key: ${TLS_FORWARD_INPUT_SHARED_KEY:-}
      self_hostname: ${HOST_HOSTNAME:?}
$(input_storage_lines)
      buffer_chunk_size: 5M
      buffer_max_size: 1000M
      tls: on
      tls.verify: ${TLS_FORWARD_INPUT_VERIFY:-off}
      tls.key_file: ${CERTIFICATES_DIRECTORY:?}/fluent-bit.pem
      tls.crt_file: ${CERTIFICATES_DIRECTORY:?}/fluent-bit.pem
      threaded: ${ENABLE_THREADED_INPUTS:-false,,}
EOF
    sed -i "s/^\(\s*\)#-\( ${yaml_file:?}\)/\1- ${yaml_file:?}/" "${CUSTOM_CONFIG_PATH:?}/fluent-bit.yaml"
    echo
    echo "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
    cat "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
else
    print_log "info" "Leaving TLS Forward input disabled"
fi

# Fluent Forward PT Input
if [[ "${ENABLE_PT_FORWARD_INPUT,,}" =~ ^(t|true)$ ]]; then
    print_log "info" "Adding PT Forward input"
    yaml_file="fluent-bit.pt-forward.input.yaml"
    cat <<EOF >"${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
pipeline:
  inputs:
    # PT Forward input
    - name: forward
      listen: 0.0.0.0
      port: ${PT_FORWARD_INPUT_PORT:?}
      self_hostname: ${HOST_HOSTNAME:?}
$(input_storage_lines)
      buffer_chunk_size: 5M
      buffer_max_size: 1000M
      tls: off
      tls.verify: off
      threaded: ${ENABLE_THREADED_INPUTS:-false,,}
EOF
    sed -i "s/^\(\s*\)#-\( ${yaml_file:?}\)/\1- ${yaml_file:?}/" "${CUSTOM_CONFIG_PATH:?}/fluent-bit.yaml"
    echo
    echo "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
    cat "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
else
    print_log "info" "Leaving PT Forward input disabled"
fi

# Docker Container Forward Input
if [[ "${ENABLE_DOCKER_FORWARD_INPUT:-}" =~ ^(t|true)$ ]]; then
    print_log "info" "Adding Docker Forward input"
    yaml_file="fluent-bit.docker-forward.input.yaml"
    cat <<EOF >"${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
pipeline:
  inputs:
    # Docker Container Forward input
    - name: forward
      listen: 0.0.0.0
      port: ${DOCKER_FORWARD_INPUT_PORT:-24226}
      tag_prefix: ${DOCKER_TAG_PREFIX:-docker.}
$(input_storage_lines)
      buffer_chunk_size: 5M
      buffer_max_size: 1000M
      threaded: ${ENABLE_THREADED_INPUTS:-false,,}

  filters:
    # Parse Docker log records
    - name: lua
      match: '${DOCKER_TAG_PREFIX:-docker.}**'
      script: docker_modify_records.lua
      call: docker_modify_records
EOF
    sed -i "s/^\(\s*\)#-\( ${yaml_file:?}\)/\1- ${yaml_file:?}/" "${CUSTOM_CONFIG_PATH:?}/fluent-bit.yaml"
    echo
    echo "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
    cat "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
else
    print_log "info" "Leaving Docker Forward input disabled"
fi

# Systemd Journal / System log input
HAS_SYSTEMD_JOURNAL="false"
HAS_SYSTEM_LOG_FALLBACK="false"
JOURNAL_PATH=""
SYSTEM_LOG_PATH=""

if [[ "${ENABLE_SYSTEMD_INPUT:-}" =~ ^(t|true)$ ]]; then
    HAS_SYSTEMD_JOURNAL="true"
    if [ -d "/host/var/log/journal" ]; then
        JOURNAL_PATH="/host/var/log/journal"
    elif [ -d "/host/run/log/journal" ]; then
        JOURNAL_PATH="/host/run/log/journal"
    else
        JOURNAL_PATH="/var/log/journal"
    fi
elif [ -d "/host/var/log/journal" ]; then
    HAS_SYSTEMD_JOURNAL="true"
    JOURNAL_PATH="/host/var/log/journal"
elif [ -d "/host/run/log/journal" ]; then
    HAS_SYSTEMD_JOURNAL="true"
    JOURNAL_PATH="/host/run/log/journal"
elif [ -f "/host/var/log/syslog" ]; then
    HAS_SYSTEM_LOG_FALLBACK="true"
    SYSTEM_LOG_PATH="/host/var/log/syslog"
elif [ -f "/host/var/log/messages" ]; then
    HAS_SYSTEM_LOG_FALLBACK="true"
    SYSTEM_LOG_PATH="/host/var/log/messages"
fi

if [[ "${HAS_SYSTEMD_JOURNAL}" == "true" ]]; then
    print_log "info" "Adding Systemd Journal input from ${JOURNAL_PATH}"
    yaml_file="fluent-bit.systemd.input.yaml"
    cat <<EOF >"${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
pipeline:
  inputs:
    - name: systemd
      tag: ${NODE_LOG_TAG_PREFIX:-node.log.}systemd.${HOST_HOSTNAME:?}
      path: ${JOURNAL_PATH}
      db: ${FLUENT_STORAGE_PATH:?}/systemd-journal.db
      db.sync: normal
      read_from_tail: On
      strip_underscores: On
      systemd_filter_type: Or

  filters:
    - name: lua
      match: '${NODE_LOG_TAG_PREFIX:-node.log.}systemd.**'
      script: systemd_modify_records.lua
      call: systemd_modify_records
EOF
    sed -i "s/^\(\s*\)#-\( ${yaml_file:?}\)/\1- ${yaml_file:?}/" "${CUSTOM_CONFIG_PATH:?}/fluent-bit.yaml"
    echo
    echo "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
    cat "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
elif [[ "${HAS_SYSTEM_LOG_FALLBACK}" == "true" ]]; then
    print_log "info" "Adding System log fallback input from ${SYSTEM_LOG_PATH}"
    yaml_file="fluent-bit.systemd.input.yaml"
    cat <<EOF >"${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
pipeline:
  parsers:
    - name: system_log
      format: regex
      regex: '^(?<time>[A-Z][a-z]{2}\s+[ 0-9]{1,2}\s\d{2}:\d{2}:\d{2})\s(?<host>[^ ]+)\s(?<process>[^:]+):\s(?<message>.*)$'
      time_key: time
      time_format: '%b %d %H:%M:%S'

  inputs:
    - name: tail
      tag: ${NODE_LOG_TAG_PREFIX:-node.log.}system.${HOST_HOSTNAME:?}
      path: ${SYSTEM_LOG_PATH}
      parser: system_log
      db: ${FLUENT_STORAGE_PATH:?}/system-log.db
      db.sync: normal
      refresh_interval: 10
      rotate_wait: 30
      read_from_head: On
      skip_long_lines: On
      mem_buf_limit: 20MB
      storage.type: filesystem

  filters:
    - name: modify
      match: '${NODE_LOG_TAG_PREFIX:-node.log.}system.**'
      add:
        source_service: systemd
        source_category: system
EOF
    sed -i "s/^\(\s*\)#-\( ${yaml_file:?}\)/\1- ${yaml_file:?}/" "${CUSTOM_CONFIG_PATH:?}/fluent-bit.yaml"
    echo
    echo "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
    cat "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
else
    print_log "info" "Leaving Systemd / System log input disabled"
fi

# Host Auth Log Input (/host/var/log/auth.log or /host/var/log/secure)
AUTH_LOG_PATH=""
if [ -f "/host/var/log/auth.log" ]; then
    AUTH_LOG_PATH="/host/var/log/auth.log"
elif [ -f "/host/var/log/secure" ]; then
    AUTH_LOG_PATH="/host/var/log/secure"
fi

if [ -n "${AUTH_LOG_PATH}" ]; then
    print_log "info" "Adding Auth log input from ${AUTH_LOG_PATH}"
    yaml_file="fluent-bit.auth-log.input.yaml"
    cat <<EOF >"${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
pipeline:
  parsers:
    - name: gitops_auth_log
      format: regex
      regex: '^(?<time>[A-Z][a-z]{2}\s+[ 0-9]{1,2}\s\d{2}:\d{2}:\d{2})\s(?<host>[^ ]+)\s(?<process>[^:]+):\s(?<message>.*)$'
      time_key: time
      time_format: '%b %d %H:%M:%S'

  inputs:
    - name: tail
      tag: ${NODE_LOG_TAG_PREFIX:-node.log.}auth.${HOST_HOSTNAME:?}
      path: ${AUTH_LOG_PATH}
      parser: gitops_auth_log
      db: ${FLUENT_STORAGE_PATH:?}/auth-log.db
      db.sync: normal
      refresh_interval: 10
      rotate_wait: 30
      read_from_head: On
      skip_long_lines: On
      mem_buf_limit: 20MB
      storage.type: filesystem

  filters:
    - name: modify
      match: '${NODE_LOG_TAG_PREFIX:-node.log.}auth.**'
      add:
        source_service: authlog
        source_category: auth
EOF
    sed -i "s/^\(\s*\)#-\( ${yaml_file:?}\)/\1- ${yaml_file:?}/" "${CUSTOM_CONFIG_PATH:?}/fluent-bit.yaml"
    echo
    echo "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
    cat "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
else
    print_log "info" "Leaving Auth log input disabled"
fi

# Host Auditd Log Input (/host/var/log/audit/audit.log)
if [ -f "/host/var/log/audit/audit.log" ]; then
    print_log "info" "Adding Auditd log input from /host/var/log/audit/audit.log"
    yaml_file="fluent-bit.audit-log.input.yaml"
    cat <<EOF >"${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
pipeline:
  parsers:
    - name: gitops_audit_log
      format: regex
      regex: '^type=(?<audit_type>[^ ]+)\s+msg=audit\((?<time>\d+\.\d+):(?<audit_id>\d+)\):\s(?<message>.*)$'
      time_key: time
      time_format: '%s.%L'

  inputs:
    - name: tail
      tag: ${NODE_LOG_TAG_PREFIX:-node.log.}audit.${HOST_HOSTNAME:?}
      path: /host/var/log/audit/audit.log
      parser: gitops_audit_log
      db: ${FLUENT_STORAGE_PATH:?}/audit-log.db
      db.sync: normal
      refresh_interval: 10
      rotate_wait: 30
      read_from_head: On
      skip_long_lines: On
      mem_buf_limit: 20MB
      storage.type: filesystem

  filters:
    - name: modify
      match: '${NODE_LOG_TAG_PREFIX:-node.log.}audit.**'
      add:
        source_service: auditd
        source_category: audit
EOF
    sed -i "s/^\(\s*\)#-\( ${yaml_file:?}\)/\1- ${yaml_file:?}/" "${CUSTOM_CONFIG_PATH:?}/fluent-bit.yaml"
    echo
    echo "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
    cat "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
else
    print_log "info" "Leaving Auditd log input disabled"
fi

# STDOUT output for debugging all log traffic
if [[ "${ENABLE_STDOUT_OUTPUT,,}" =~ ^(t|true)$ ]]; then
    print_log "info" "Adding STDOUT output for all logs"
    yaml_file="fluent-bit.debug.output.yaml"
    cat <<EOF >"${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
pipeline:
  outputs:
    # Debugging output
    - name: stdout
      ${output_tag_match_key:?}: ${output_tag_match:?}
EOF
    echo
    echo "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
    cat "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
else
    print_log "info" "Leaving STDOUT output for all logs disabled"
fi

# S3 Bucket cold storage
if [[ "${ENABLE_S3_BUCKET_COLD_STORAGE_OUTPUT,,}" =~ ^(t|true)$ ]]; then
    print_log "info" "Adding S3 Bucket cold storage output"
    yaml_file="fluent-bit.s3-cold-storage.output.yaml"
    cat <<EOF >"${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
pipeline:
  outputs:
    # S3 Bucket cold storage output
    - name: s3
      match_regex: ^${FLUENT_BIT_TAG_PREFIX:-}(?!.*cld_st).*
      bucket: ${AWS_COLD_STORAGE_BUCKET_NAME:?}
      region: ${AWS_COLD_STORAGE_BUCKET_REGION:?}
      total_file_size: 10M
      s3_key_format: /\$TAG/%Y/%m/%d/%H_%M_%S-\$UUID.txt.gz
      use_put_object: On
      compression: gzip
      store_dir: ${FLUENT_STORAGE_PATH:?}/s3_buffer
      upload_timeout: 10m
      retry_limit: 5
EOF
    sed -i "s/^\(\s*\)#-\( ${yaml_file:?}\)/\1- ${yaml_file:?}/" "${CUSTOM_CONFIG_PATH:?}/fluent-bit.yaml"
    echo
    echo "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
    cat "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
else
    print_log "info" "Leaving S3 Bucket cold storage output disabled"
fi

# Graylog GELF output
if [[ "${ENABLE_GRAYLOG_GELF_OUTPUT,,}" =~ ^(t|true)$ ]]; then
    print_log "info" "Adding Graylog GELF output"
    yaml_file="fluent-bit.graylog-gelf.output.yaml"
    cat <<EOF >"${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
pipeline:
  filters:
    # Create a copy of the logs to be formatted before shipping to Graylog
    - name: rewrite_tag
      ${output_tag_match_key:?}: ${output_tag_match:?}
      rule: \$message .* graylog_fmt.\$TAG true
      emitter_name: emitter_graylog
      emitter_storage.type: filesystem
      emitter_mem_buf_limit: ${FLUENT_REWRITE_TAG_EMITTER_MEM_BUF_LIMIT}
    # Ensure required fields are extracted and formatted for Graylog
    - name: lua
      match: 'graylog_fmt.*'
      script: apply-graylog-formatting.lua
      call: graylog_formatting

  outputs:
    # Graylog GELF output
    - name: gelf
      match: 'graylog_fmt.*'
      host: graylog
      port: 12201
      mode: tcp
      compress: false
      gelf_timestamp_key: timestamp
      gelf_short_message_key: message
      gelf_full_message_key: message
      gelf_host_key: source
      retry_limit: 6
EOF
    sed -i "s/^\(\s*\)#-\( ${yaml_file:?}\)/\1- ${yaml_file:?}/" "${CUSTOM_CONFIG_PATH:?}/fluent-bit.yaml"
    echo
    echo "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
    cat "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
else
    print_log "info" "Leaving Graylog GELF output disabled"
fi

# Grafana Loki output
if [[ "${ENABLE_GRAFANA_LOKI_OUTPUT,,}" =~ ^(t|true)$ ]]; then
    print_log "info" "Adding Grafana Loki output"
    yaml_file="fluent-bit.grafana-loki.output.yaml"
    cat <<EOF >>"${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
pipeline:
  filters:
    # Create a copy of the logs to be formatted before shipping to Loki
    - name: rewrite_tag
      ${output_tag_match_key:?}: ${output_tag_match:?}
      rule: \$message .* loki_fmt.\$TAG true
      emitter_name: emitter_loki
      emitter_storage.type: filesystem
      emitter_mem_buf_limit: ${FLUENT_REWRITE_TAG_EMITTER_MEM_BUF_LIMIT}
    # Ensure required fields are extracted and formatted for Grafana Loki
    - name: lua
      match: 'loki_fmt.*'
      script: apply-loki-formatting.lua
      call: grafana_loki_formatting

  outputs:
    # Grafana Loki output
    - name: loki
      match: 'loki_fmt.*'
      host: ${GRAFANA_LOKI_HOST:-}
      port: ${GRAFANA_LOKI_PORT:-}
      uri: ${GRAFANA_LOKI_URI:-/loki/api/v1/push}
      tls: off
      labels: input=flb
      label_map_path: ${CUSTOM_CONFIG_PATH:?}/fluent-bit.grafana-loki.output.logmap.json
      line_format: json
EOF
    sed -i "s/^\(\s*\)#-\( ${yaml_file:?}\)/\1- ${yaml_file:?}/" "${CUSTOM_CONFIG_PATH:?}/fluent-bit.yaml"
    echo
    echo "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
    cat "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
else
    print_log "info" "Leaving Grafana Loki output disabled"
fi

# OpenObserve HTTP output
if [[ "${ENABLE_OPENOBSERVE_HTTP_OUTPUT,,}" =~ ^(t|true)$ ]]; then
    print_log "info" "Adding OpenObserve HTTP output"
    yaml_file="fluent-bit.openobserve-http.output.yaml"
    cat <<EOF >"${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
pipeline:
  filters:
    # Create a copy of the logs to be shipped to OpenObserve
    - name: rewrite_tag
      ${output_tag_match_key:?}: ${output_tag_match:?}
      rule: \$message .* openobserve_fmt.\$TAG true
      emitter_name: emitter_openobserve
      emitter_storage.type: filesystem
      emitter_mem_buf_limit: ${FLUENT_REWRITE_TAG_EMITTER_MEM_BUF_LIMIT}

  outputs:
    # OpenObserve HTTP output
    - name: http
      match: 'openobserve_fmt.*'
      host: ${OPENOBSERVE_HTTP_HOST:-}
      port: ${OPENOBSERVE_HTTP_PORT:-}
      uri: ${OPENOBSERVE_HTTP_URI:-/api/default/default/_json}
      tls: ${OPENOBSERVE_HTTP_TLS:-off}
      format: json
      json_date_key: _timestamp
      json_date_format: iso8601
      http_user: ${OPENOBSERVE_HTTP_USER:-}
      http_passwd: ${OPENOBSERVE_HTTP_PASSWD:-}
      compress: gzip
EOF
    sed -i "s/^\(\s*\)#-\( ${yaml_file:?}\)/\1- ${yaml_file:?}/" "${CUSTOM_CONFIG_PATH:?}/fluent-bit.yaml"
    echo
    echo "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
    cat "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
else
    print_log "info" "Leaving OpenObserve HTTP output disabled"
fi

# Upstream Fluentd or Fluent-bit TLS encrypted Forward output
if [[ "${ENABLE_TLS_FORWARD_OUTPUT,,}" =~ ^(t|true)$ ]]; then
    print_log "info" "Adding TLS Forward output"
    yaml_file="fluent-bit.tls-forward.output.yaml"
    cat <<EOF >"${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
pipeline:
  outputs:
    # TLS Forward output
    - name: forward
      ${output_tag_match_key:?}: ${output_tag_match:?}
      host: ${TLS_FORWARD_OUTPUT_HOST:?}
      port: ${TLS_FORWARD_OUTPUT_PORT:?}
      shared_key: ${TLS_FORWARD_OUTPUT_SHARED_KEY:?}
      tls: on
      tls.verify: ${TLS_FORWARD_OUTPUT_VERIFY:-off}
EOF
    sed -i "s/^\(\s*\)#-\( ${yaml_file:?}\)/\1- ${yaml_file:?}/" "${CUSTOM_CONFIG_PATH:?}/fluent-bit.yaml"
    echo
    echo "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
    cat "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
else
    print_log "info" "Leaving TLS Forward output disabled"
fi

# Upstream Fluentd or Fluent-bit unencrypted Forward output
if [[ "${ENABLE_PT_FORWARD_OUTPUT,,}" =~ ^(t|true)$ ]]; then
    print_log "info" "Adding PT Forward output"
    yaml_file="fluent-bit.pt-forward.output.yaml"
    cat <<EOF >"${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
pipeline:
  outputs:
    # PT Forward output
    - name: forward
      ${output_tag_match_key:?}: ${output_tag_match:?}
      host: ${PT_FORWARD_OUTPUT_HOST:?}
      port: ${PT_FORWARD_OUTPUT_PORT:?}
      tls: off
EOF
    sed -i "s/^\(\s*\)#-\( ${yaml_file:?}\)/\1- ${yaml_file:?}/" "${CUSTOM_CONFIG_PATH:?}/fluent-bit.yaml"
    echo
    echo "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
    cat "${CUSTOM_CONFIG_PATH:?}/${yaml_file:?}"
else
    print_log "info" "Leaving PT Forward output disabled"
fi
echo
echo "${CUSTOM_CONFIG_PATH:?}/fluent-bit.yaml"
cat "${CUSTOM_CONFIG_PATH:?}/fluent-bit.yaml"

# Modify the Lua lib paths or Fluent-bit will not be able to import it
export LUA_PATH="/usr/share/lua/5.1/?.lua;;"
export LUA_CPATH="/usr/lib/$(uname -m)-linux-gnu/lua/5.1/?.so;;"

################################################
# --- Run Fluent-bit
#
print_log "info" "Starting Fluent-Bit"
exec /opt/fluent-bit/bin/fluent-bit -c "${CUSTOM_CONFIG_PATH:?}/fluent-bit.yaml"
