# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv

FROM ubuntu:latest AS lua-cjson-builder

ARG LUA_CJSON_COMMIT=5ce46a80b10ef9d380a45c9e6cff9ecffbe71ebb
ARG LUA_CJSON_SHA256=ba78a371233335e1822cede7d2541e88bec77c572ee892e96e87e661153a79f1
RUN \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        liblua5.1-0-dev \
    && mkdir -p /tmp/lua-cjson /out/usr/local/lib/lua/5.1 \
    && curl -fsSL \
        "https://github.com/openresty/lua-cjson/archive/${LUA_CJSON_COMMIT}.tar.gz" \
        -o /tmp/lua-cjson.tar.gz \
    && echo "${LUA_CJSON_SHA256}  /tmp/lua-cjson.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/lua-cjson.tar.gz --strip-components=1 -C /tmp/lua-cjson \
    && make -C /tmp/lua-cjson \
        LUA_INCLUDE_DIR=/usr/include/lua5.1 \
        CJSON_CFLAGS="-fpic -pthread -DMULTIPLE_THREADS" \
        CJSON_LDFLAGS="-shared -pthread" \
    && cp /tmp/lua-cjson/cjson.so /out/usr/local/lib/lua/5.1/cjson.so

FROM ubuntu:latest

ARG FLUENT_BIT_RELEASE_VERSION=5.0.9
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
            jq \
            openssl \
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
    echo "**** cleanup apt cache ****" \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/* \
    && \
    echo

COPY --from=lua-cjson-builder /out/ /
COPY overlay/ /

ENV \
    # Core Defaults
    FLUENT_BIT_LOG_LEVEL=info \
    FLUENT_BIT_TAG_PREFIX=flb \
    FLUENT_STORAGE_PATH=/var/fluent-bit/storage \
    CERTIFICATES_DIRECTORY=/etc/fluent-bit/certs \
    # Input Feature Flags
    ENABLE_THREADED_NETWORK_INPUTS=false \
    ENABLE_HTTP_INPUT=false \
    ENABLE_TLS_FORWARD_INPUT=false \
    ENABLE_PT_FORWARD_INPUT=false \
    ENABLE_DOCKER_FORWARD_INPUT=false \
    ENABLE_SYSTEMD_INPUT=false \
    ENABLE_AUTH_LOG_INPUT=false \
    ENABLE_AUDIT_LOG_INPUT=false \
    ENABLE_AWS_SSM_INPUT=false \
    ENABLE_AWS_ECS_INPUT=false \
    # Output Feature Flags
    ENABLE_STDOUT_OUTPUT=false \
    ENABLE_S3_BUCKET_COLD_STORAGE_OUTPUT=false \
    ENABLE_GRAYLOG_GELF_OUTPUT=false \
    ENABLE_GRAFANA_LOKI_OUTPUT=false \
    ENABLE_OPENOBSERVE_HTTP_OUTPUT=false \
    ENABLE_TLS_FORWARD_OUTPUT=false \
    ENABLE_PT_FORWARD_OUTPUT=false \
    # Certificate Options
    USE_EXISTING_CERT=false \
    USE_CERTBOT_TO_GENERATE_KEY=false


HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=5 \
    CMD ["/healthcheck.sh"]

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD []
