FROM ubuntu:latest

ARG FLUENT_BIT_RELEASE_VERSION=3.2.9
RUN \
    echo "**** update apt repositories ****" \
        && apt-get update \
    && \
    echo "**** install container runtime packages ****" \
        && apt-get install -y --no-install-recommends \
            bash \
            ca-certificates \
            certbot \
            curl \
            gnupg \
            tini \
    && \
    echo "**** install wait-for-it script ****" \
        && curl https://raw.githubusercontent.com/vishnubob/wait-for-it/81b1373f17855a4dc21156cfe1694c31d7d1792e/wait-for-it.sh \
            -o /usr/bin/wait-for-it \
        && chmod +x /usr/bin/wait-for-it \
    && \
    echo "**** install Fluent-bit (${FLUENT_BIT_RELEASE_VERSION:-latest}) ****" \
        && curl https://raw.githubusercontent.com/fluent/fluent-bit/master/install.sh \
            -o /tmp/install.sh \
        && chmod +x /tmp/install.sh \
        && /tmp/install.sh \
        && rm -f /tmp/install.sh \
        && /opt/fluent-bit/bin/fluent-bit --version \
    && \
    echo "**** install lua dependencies ****" \
        && apt-get install -y --no-install-recommends \
            lua-cjson \
    && \
    echo "**** cleanup apt cache ****" \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/* \
    && \
    echo

COPY overlay/ /

ENV \
    FLUENT_BIT_LOG_LEVEL=info \
    FLUENT_BIT_TAG_PREFIX=flb. \
    HOST_HOSTNAME=fluent-bit-router \
    FLUENT_STORAGE_PATH=/var/fluent-bit/storage \
    ENABLE_HTTP_INPUT=false \
    HTTP_INPUT_PORT=24280 \
    ENABLE_TLS_FORWARD_INPUT=false \
    TLS_FORWARD_INPUT_PORT=24224 \
    TLS_FORWARD_INPUT_SHARED_KEY=1234567890 \
    TLS_FORWARD_INPUT_VERIFY=off \
    CERTIFICATES_DIRECTORY=/etc/fluent-bit/certs \
    USE_EXISTING_CERT=false \
    EXISTING_KEY_PATH=/etc/fluent-bit/certs/1.key \
    EXISTING_CERT_PATH=/etc/fluent-bit/certs/1.pem \
    USE_CERTBOT_TO_GENERATE_KEY=false \
    CERT_FQDN=fluent-bit-router \
    CERT_EMAIL=admin@example.com \
    ENABLE_PT_FORWARD_INPUT=false \
    PT_FORWARD_INPUT_PORT=24228 \
    ENABLE_STDOUT_OUTPUT=false \
    ENABLE_S3_BUCKET_COLD_STORAGE_OUTPUT=false \
    ENABLE_GRAYLOG_GELF_OUTPUT=false \
    ENABLE_GRAFANA_LOKI_OUTPUT=false \
    GRAFANA_LOKI_HOST=loki \
    GRAFANA_LOKI_PORT=3100 \
    GRAFANA_LOKI_URI=/logs/loki/api/v1/push \
    ENABLE_OPENOBSERVE_HTTP_OUTPUT=false \
    OPENOBSERVE_HTTP_HOST=openobserve \
    OPENOBSERVE_HTTP_PORT=5080 \
    OPENOBSERVE_HTTP_URI=/api/default/default/_json \
    OPENOBSERVE_HTTP_TLS=off \
    OPENOBSERVE_HTTP_USER= \
    OPENOBSERVE_HTTP_PASSWD= \
    ENABLE_TLS_FORWARD_OUTPUT=false \
    TLS_FORWARD_OUTPUT_HOST=tls-fluent-bit-upstream \
    TLS_FORWARD_OUTPUT_PORT=24224 \
    TLS_FORWARD_OUTPUT_SHARED_KEY=1234567890 \
    TLS_FORWARD_OUTPUT_VERIFY=off \
    ENABLE_PT_FORWARD_OUTPUT=false \
    PT_FORWARD_OUTPUT_HOST=pt-fluent-bit-upstream \
    PT_FORWARD_OUTPUT_PORT=24224

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD []
