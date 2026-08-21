# Configuration Reference

This document details all environment variables supported by the `fluent-bit-router` container. Environment variables control input pipelines, output destinations, certificate management, buffering, and log enrichment.

---

## Environment Variables Summary

### Core & Service Storage

| Variable                                        | Description                                                                                                        | Default                   |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | ------------------------- |
| `FLUENT_BIT_LOG_LEVEL`                          | Logging verbosity for Fluent-Bit (`error`, `warning`, `info`, `debug`, `trace`).                                   | `info`                    |
| `HTTP_SERVER_PORT`                              | Port for Fluent Bit's built-in HTTP server (metrics and health check endpoint).                                    | `2020`                    |
| `FLUENT_BIT_TAG_PREFIX`                         | Base prefix added to tags processed by output routing rules.                                                       | `flb`                     |
| `INFRASTRUCTURE_PROVIDER`                       | Hosting provider (`aws`, `azure`, `self`, `linode`) used in record tags and supported instance-metadata discovery. | `privatecloud`            |
| `FLUENT_STORAGE_PATH`                           | Path inside container where filesystem buffer chunks are stored.                                                   | `/var/fluent-bit/storage` |
| `FLUENT_STORAGE_MAX_CHUNKS_UP`                  | Maximum number of filesystem storage chunks kept loaded in memory simultaneously (`[SERVICE]` section).            | `128`                     |
| `FLUENT_STORAGE_BACKLOG_MEM_LIMIT`              | Memory limit for storage engine when reloading disk backlog at startup (`[SERVICE]` section).                      | `20M`                     |
| `FLUENT_STORAGE_SYNC`                           | Storage synchronization mode (`normal` / `full`).                                                                  | `normal`                  |
| `FLUENT_STORAGE_CHECKSUM`                       | Storage chunk checksum validation (`on` / `off`).                                                                  | `off`                     |
| `FLUENT_INPUT_STORAGE_TYPE`                     | Default storage mechanism for inputs (`filesystem` / `memory`).                                                    | `filesystem`              |
| `FLUENT_INPUT_MEM_BUF_LIMIT`                    | Memory buffer limit for input plugins before filesystem writes occur.                                              | `64M`                     |
| `FLUENT_REWRITE_TAG_EMITTER_MEM_BUF_LIMIT`      | Memory buffer limit for `rewrite_tag` emitter engines.                                                             | `64M`                     |
| `FLUENT_OUTPUT_BUFFER_STORAGE_TOTAL_LIMIT_SIZE` | Global fallback filesystem buffer limit for output queues (empty to use per-output defaults).                      | _(empty)_                 |
| `CONTAINER_MAX_LIFETIME_HOURS`                  | Optional maximum lifetime in hours before health check reports unhealthy to trigger container recycling.           | _(empty)_                 |
| `CERTIFICATES_DIRECTORY`                        | Directory where generated or supplied SSL/TLS certificates reside.                                                 | `/etc/fluent-bit/certs`   |

---

### Ingestion Inputs

Click any `ENABLE_*` link below to view complete setup and pipeline documentation for that input.

| Variable                         | Description                                                                                                           | Default   | Detailed Guide                                  |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------- | --------- | ----------------------------------------------- |
| `ENABLE_HTTP_INPUT`              | Enable HTTP log ingestion server.                                                                                     | `false`   | [HTTP Input Guide](input-http.md)               |
| `HTTP_INPUT_PORT`                | Listen port for HTTP input.                                                                                           | `24280`   | [HTTP Input Guide](input-http.md)               |
| `ENABLE_TLS_FORWARD_INPUT`       | Enable TLS-encrypted Forward input.                                                                                   | `false`   | [TLS Forward Input Guide](input-tls-forward.md) |
| `TLS_FORWARD_INPUT_PORT`         | Listen port for TLS Forward input.                                                                                    | `24224`   | [TLS Forward Input Guide](input-tls-forward.md) |
| `TLS_FORWARD_INPUT_SHARED_KEY`   | Shared key for TLS Forward authentication.                                                                            | _(empty)_ | [TLS Forward Input Guide](input-tls-forward.md) |
| `TLS_FORWARD_INPUT_VERIFY`       | Verify client certificates (`on` or `off`).                                                                           | `off`     | [TLS Forward Input Guide](input-tls-forward.md) |
| `ENABLE_PT_FORWARD_INPUT`        | Enable Plaintext Forward input.                                                                                       | `false`   | [PT Forward Input Guide](input-pt-forward.md)   |
| `PT_FORWARD_INPUT_PORT`          | Listen port for Plaintext Forward input.                                                                              | `24228`   | [PT Forward Input Guide](input-pt-forward.md)   |
| `ENABLE_DOCKER_FORWARD_INPUT`    | Enable dedicated Docker container Forward input.                                                                      | `false`   | [Docker Forward Input Guide](input-docker.md)   |
| `DOCKER_FORWARD_INPUT_PORT`      | Listen port for Docker Forward input.                                                                                 | `24226`   | [Docker Forward Input Guide](input-docker.md)   |
| `ENABLE_SYSTEMD_INPUT`           | Enable systemd journal & system log fallback input (requires host `/var/log` mounted).                                | `false`   | [Systemd Journal Guide](input-systemd.md)       |
| `SYSTEMD_FILTER_UNITS`           | Optional comma-separated unit regexes. Syslog processes are normalized to service-shaped units. If empty, all ingest. | _(empty)_ | [Systemd Journal Guide](input-systemd.md)       |
| `ENABLE_AUTH_LOG_INPUT`          | Enable host SSH/auth log input (`/host/var/log/auth.log` or `/host/var/log/secure`).                                  | `false`   | [Auth & Audit Guide](input-auth-audit.md)       |
| `ENABLE_AUDIT_LOG_INPUT`         | Enable host auditd log input (`/host/var/log/audit/audit.log`).                                                       | `false`   | [Auth & Audit Guide](input-auth-audit.md)       |
| `ENABLE_AWS_SSM_INPUT`           | Enable AWS SSM Agent log input (`/host/var/log/amazon/ssm`).                                                          | `false`   | [AWS Cloud Guide](input-aws-cloud.md)           |
| `ENABLE_AWS_ECS_INPUT`           | Enable AWS ECS host log input (`/host/var/log/ecs`).                                                                  | `false`   | [AWS Cloud Guide](input-aws-cloud.md)           |
| `ENABLE_THREADED_NETWORK_INPUTS` | Enable multi-threading for network listener input plugins (Forward, HTTP).                                            | `false`   | [Inputs Overview](inputs.md)                    |

> [!NOTE]
> Input tag prefixes are automatically derived from `FLUENT_BIT_TAG_PREFIX` and `INFRASTRUCTURE_PROVIDER`:
>
> - **Docker Tag Prefix**: `${FLUENT_BIT_TAG_PREFIX}.${INFRASTRUCTURE_PROVIDER}.docker.` (e.g., `flb.privatecloud.docker.`)
> - **Node Log Tag Prefix**: `${FLUENT_BIT_TAG_PREFIX}.${INFRASTRUCTURE_PROVIDER}.node.log.` (e.g., `flb.privatecloud.node.log.`)

---

### Environmental & Metadata Tagging

| Variable                      | Description                                                                                                | Default       | Detailed Guide                                                                                               |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------- | ------------- | ------------------------------------------------------------------------------------------------------------ |
| `ENVIRONMENT_NAME`            | Logical deployment environment name, appended as `source_env`.                                             | _(empty)_     | [Global Filters Guide](input-global-filters.md#2-environmental-metadata-enrichment-filter-append_recordslua) |
| `ENVIRONMENT_TYPE`            | Lifecycle or deployment class appended as `source_env_type` (`homelab`, `test`, `staging`, `production`).  | _(empty)_     | [Global Filters Guide](input-global-filters.md#2-environmental-metadata-enrichment-filter-append_recordslua) |
| `ENVIRONMENT_REGION`          | Cloud-provider or physical region appended as `source_env_region` (`ap-south-1`, `us-east-1`, `nz`, `uk`). | _(empty)_     | [Global Filters Guide](input-global-filters.md#2-environmental-metadata-enrichment-filter-append_recordslua) |
| `ENVIRONMENT_ISOLATION_SCOPE` | Security and credential-sharing boundary appended as `source_env_isolation_scope`.                         | _(empty)_     | [Global Filters Guide](input-global-filters.md#2-environmental-metadata-enrichment-filter-append_recordslua) |
| `INSTANCE_ID`                 | Host instance ID appended as `source_instance_id`. Auto-fetched via IMDS for `aws`/`azure` if unassigned.  | _(empty)_     | [Global Filters Guide](input-global-filters.md#2-environmental-metadata-enrichment-filter-append_recordslua) |
| `HOST_HOSTNAME`               | Host node hostname appended as `source_hostname`.                                                          | `$(hostname)` | [Global Filters Guide](input-global-filters.md#2-environmental-metadata-enrichment-filter-append_recordslua) |

---

### Output Destinations

Click any `ENABLE_*` link below to view detailed pipeline, schema, and routing documentation for that output.

| Variable                                             | Description                                                      | Default                      | Detailed Guide                                                    |
| ---------------------------------------------------- | ---------------------------------------------------------------- | ---------------------------- | ----------------------------------------------------------------- |
| `ENABLE_STDOUT_OUTPUT`                               | Enable stdout debug output plugin for all incoming logs.         | `false`                      | [Routing Guide](routing-and-forwarding.md#stdout-debug-output)    |
| `ENABLE_GRAFANA_LOKI_OUTPUT`                         | Enable Grafana Loki HTTP push output plugin.                     | `false`                      | [Grafana Loki Output Guide](output-loki.md)                       |
| `GRAFANA_LOKI_HOST`                                  | Hostname or IP of Grafana Loki instance.                         | _(empty)_                    | [Grafana Loki Output Guide](output-loki.md)                       |
| `GRAFANA_LOKI_PORT`                                  | Port of Grafana Loki instance.                                   | `3100`                       | [Grafana Loki Output Guide](output-loki.md)                       |
| `GRAFANA_LOKI_URI`                                   | Ingestion endpoint URI for Grafana Loki.                         | `/loki/api/v1/push`          | [Grafana Loki Output Guide](output-loki.md)                       |
| `GRAFANA_LOKI_BUFFER_STORAGE_TOTAL_LIMIT_SIZE`       | Filesystem queue limit for Loki output buffer.                   | `3G`                         | [Grafana Loki Output Guide](output-loki.md)                       |
| `GRAFANA_LOKI_RETRY_LIMIT`                           | Retry limit for Loki push requests before dropping chunk.        | `10`                         | [Grafana Loki Output Guide](output-loki.md)                       |
| `ENABLE_OPENOBSERVE_HTTP_OUTPUT`                     | Enable OpenObserve HTTP ingestion output plugin.                 | `false`                      | [OpenObserve Output Guide](output-openobserve.md)                 |
| `OPENOBSERVE_HTTP_HOST`                              | Hostname or IP of OpenObserve instance.                          | _(empty)_                    | [OpenObserve Output Guide](output-openobserve.md)                 |
| `OPENOBSERVE_HTTP_PORT`                              | Port of OpenObserve instance.                                    | `5080`                       | [OpenObserve Output Guide](output-openobserve.md)                 |
| `OPENOBSERVE_HTTP_URI`                               | Ingestion endpoint URI for OpenObserve.                          | `/api/default/default/_json` | [OpenObserve Output Guide](output-openobserve.md)                 |
| `OPENOBSERVE_HTTP_TLS`                               | Enable TLS for OpenObserve HTTP connection (`on`/`off`).         | `off`                        | [OpenObserve Output Guide](output-openobserve.md)                 |
| `OPENOBSERVE_HTTP_USER`                              | Basic auth username for OpenObserve.                             | _(empty)_                    | [OpenObserve Output Guide](output-openobserve.md)                 |
| `OPENOBSERVE_HTTP_PASSWD`                            | Basic auth password or stream token for OpenObserve.             | _(empty)_                    | [OpenObserve Output Guide](output-openobserve.md)                 |
| `OPENOBSERVE_HTTP_BUFFER_STORAGE_TOTAL_LIMIT_SIZE`   | Filesystem queue limit for OpenObserve output buffer.            | `5G`                         | [OpenObserve Output Guide](output-openobserve.md)                 |
| `OPENOBSERVE_HTTP_RETRY_LIMIT`                       | Retry limit for OpenObserve output (`integer` or `false`).       | `false`                      | [OpenObserve Output Guide](output-openobserve.md)                 |
| `ENABLE_GRAYLOG_GELF_OUTPUT`                         | Enable Graylog GELF TCP output plugin.                           | `false`                      | [Routing Guide](routing-and-forwarding.md)                        |
| `GRAYLOG_GELF_HOST`                                  | Hostname or service name of Graylog instance.                    | `graylog`                    | [Routing Guide](routing-and-forwarding.md)                        |
| `GRAYLOG_GELF_PORT`                                  | Port of Graylog GELF input.                                      | `12201`                      | [Routing Guide](routing-and-forwarding.md)                        |
| `GRAYLOG_GELF_MODE`                                  | Transport protocol for Graylog GELF (`tcp` / `udp`).             | `tcp`                        | [Routing Guide](routing-and-forwarding.md)                        |
| `GRAYLOG_GELF_BUFFER_STORAGE_TOTAL_LIMIT_SIZE`       | Filesystem queue limit for Graylog GELF output buffer.           | `2G`                         | [Routing Guide](routing-and-forwarding.md)                        |
| `GRAYLOG_GELF_RETRY_LIMIT`                           | Retry limit for Graylog GELF output before dropping chunk.       | `6`                          | [Routing Guide](routing-and-forwarding.md)                        |
| `ENABLE_S3_BUCKET_COLD_STORAGE_OUTPUT`               | Enable Amazon S3 cold storage output plugin.                     | `false`                      | [Routing Guide](routing-and-forwarding.md)                        |
| `AWS_COLD_STORAGE_BUCKET_NAME`                       | Amazon S3 bucket name for cold storage.                          | _(empty)_                    | [Routing Guide](routing-and-forwarding.md)                        |
| `AWS_COLD_STORAGE_BUCKET_REGION`                     | AWS region for S3 cold storage bucket.                           | _(empty)_                    | [Routing Guide](routing-and-forwarding.md)                        |
| `AWS_COLD_STORAGE_BUFFER_STORE_DIR_LIMIT_SIZE`       | Max disk size for S3 multipart buffer directory.                 | `10G`                        | [Routing Guide](routing-and-forwarding.md)                        |
| `AWS_COLD_STORAGE_RETRY_LIMIT`                       | Retry limit for S3 uploads before failing chunk.                 | `5`                          | [Routing Guide](routing-and-forwarding.md)                        |
| `ENABLE_TLS_FORWARD_OUTPUT`                          | Enable TLS-encrypted upstream Forward output plugin.             | `false`                      | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |
| `TLS_FORWARD_OUTPUT_HOST`                            | Remote host address for TLS Forward output.                      | _(empty)_                    | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |
| `TLS_FORWARD_OUTPUT_PORT`                            | Remote port for TLS Forward output.                              | `24224`                      | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |
| `TLS_FORWARD_OUTPUT_SHARED_KEY`                      | Shared key for remote TLS Forward authentication.                | _(empty)_                    | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |
| `TLS_FORWARD_OUTPUT_VERIFY`                          | Verify remote TLS certificate (`on`/`off`).                      | `off`                        | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |
| `TLS_FORWARD_OUTPUT_BUFFER_STORAGE_TOTAL_LIMIT_SIZE` | Filesystem queue limit for TLS Forward output buffer.            | `3G`                         | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |
| `TLS_FORWARD_OUTPUT_RETRY_LIMIT`                     | Retry limit for TLS Forward output (`integer` or `false`).       | `false`                      | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |
| `ENABLE_PT_FORWARD_OUTPUT`                           | Enable Plaintext upstream Forward output plugin.                 | `false`                      | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |
| `PT_FORWARD_OUTPUT_HOST`                             | Remote host address for Plaintext Forward output.                | _(empty)_                    | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |
| `PT_FORWARD_OUTPUT_PORT`                             | Remote port for Plaintext Forward output.                        | `24224`                      | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |
| `PT_FORWARD_OUTPUT_BUFFER_STORAGE_TOTAL_LIMIT_SIZE`  | Filesystem queue limit for Plaintext Forward output buffer.      | `3G`                         | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |
| `PT_FORWARD_OUTPUT_RETRY_LIMIT`                      | Retry limit for Plaintext Forward output (`integer` or `false`). | `false`                      | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |

---

### Storage Architecture & Input-Specific Backpressure Policies

The router enforces differentiated backpressure policies based on the producer contract of each input plugin:

- **Inter-Node Forward & HTTP Streams (`storage.pause_on_chunks_overlimit: on`)**: When downstream outputs stall and `storage.max_chunks_up` is filled, the router pauses its Forward/HTTP network listeners. Upstream FB sources (which maintain their own local filesystem queues) safely hold logs on edge host disks without data loss.
- **Systemd Journal Input (`storage.pause_on_chunks_overlimit: on`)**: Systemd journal maintains its own compressed binary journal files on host disk. Pausing journal tailing during downstream pressure conserves router buffer space while journald retains historical logs across multiple days/weeks.
- **Docker Log Driver Input (`storage.pause_on_chunks_overlimit: off`)**: Docker daemon's `fluentd` log driver lacks disk spooling. The router actively hoovers all Docker logs directly to its own disk chunks in unmapped state to prevent container lockups or Docker ring buffer drops.
- **Host File Tailing Inputs (`storage.pause_on_chunks_overlimit: off`)**: Host logs (`auth.log`, `audit.log`, SSM, ECS) are tailed aggressively and spooled to router disk chunks so data is secured before host `logrotate` (or `copytruncate`) can rotate, compress, or truncate active log files.
- **Active Memory Cap**: `FLUENT_STORAGE_MAX_CHUNKS_UP=128` limits active memory-mapped chunks to ~256MB in RAM, keeping the memory footprint minimal and predictable under heavy throughput.

---

## Certificate Generation Variables

| Variable                      | Description                                                             | Default       |
| ----------------------------- | ----------------------------------------------------------------------- | ------------- |
| `USE_EXISTING_CERT`           | Use supplied certificate files (`true`/`false`).                        | `false`       |
| `EXISTING_KEY_PATH`           | Path to existing private key file.                                      | _(empty)_     |
| `EXISTING_CERT_PATH`          | Path to existing certificate file.                                      | _(empty)_     |
| `CERT_FQDN`                   | Hostname / FQDN used for self-signed or Certbot certificate generation. | `$(hostname)` |
| `USE_CERTBOT_TO_GENERATE_KEY` | Use Certbot Let's Encrypt webroot challenge (`true`/`false`).           | `false`       |
| `CERT_EMAIL`                  | Contact email address for Certbot registration.                         | _(empty)_     |
