# Configuration Reference

This document details all environment variables supported by the `fluent-bit-router` container. Environment variables control input pipelines, output destinations, certificate management, buffering, and log enrichment.

---

## Environment Variables Summary

### Core & Storage

| Variable                                   | Description                                                                                  | Default                           |
| ------------------------------------------ | -------------------------------------------------------------------------------------------- | --------------------------------- |
| `FLUENT_BIT_LOG_LEVEL`                     | Logging verbosity for Fluent-Bit (`error`, `warning`, `info`, `debug`, `trace`).             | `info`                            |
| `FLUENT_BIT_LOG_LEVEL`                     | Logging verbosity for Fluent-Bit (`error`, `warning`, `info`, `debug`, `trace`).             | `info`                            |
| `HTTP_SERVER_PORT`                         | Port for Fluent Bit's built-in HTTP server (metrics and health check endpoint).              | `2020`                            |
| `FLUENT_BIT_TAG_PREFIX`                    | Base prefix added to tags processed by output routing rules.                                 | `flb`                             |
| `INFRASTRUCTURE_PROVIDER`                  | Infrastructure provider tag (`aws`, `azure`, `privatecloud`). Controls IMDS instance lookup. | `privatecloud`                    |
| `FLUENT_STORAGE_PATH`                      | Path inside container where filesystem buffer chunks are stored.                             | `/var/fluent-bit/log/flb-storage` |
| `FLUENT_STORAGE_MAX_CHUNKS_UP`             | Maximum number of storage chunks up in memory.                                               | `128`                             |
| `FLUENT_STORAGE_BACKLOG_MEM_LIMIT`         | Memory limit for storage backlog.                                                            | `20M`                             |
| `FLUENT_INPUT_MEM_BUF_LIMIT`               | Memory buffer limit for input plugins.                                                       | `64M`                             |
| `FLUENT_REWRITE_TAG_EMITTER_MEM_BUF_LIMIT` | Memory buffer limit for `rewrite_tag` emitter engines.                                       | `64M`                             |
| `CERTIFICATES_DIRECTORY`                   | Directory where generated or supplied SSL/TLS certificates reside.                           | `/etc/fluent-bit/certs`           |

---

### Ingestion Inputs

Click any `ENABLE_*` link below to view complete setup and pipeline documentation for that input.

| Variable                       | Description                                                                                     | Default   | Detailed Guide                                  |
| ------------------------------ | ----------------------------------------------------------------------------------------------- | --------- | ----------------------------------------------- |
| `ENABLE_HTTP_INPUT`            | Enable HTTP log ingestion server.                                                               | `false`   | [HTTP Input Guide](input-http.md)               |
| `HTTP_INPUT_PORT`              | Listen port for HTTP input.                                                                     | `24280`   | [HTTP Input Guide](input-http.md)               |
| `ENABLE_TLS_FORWARD_INPUT`     | Enable TLS-encrypted Forward input.                                                             | `false`   | [TLS Forward Input Guide](input-tls-forward.md) |
| `TLS_FORWARD_INPUT_PORT`       | Listen port for TLS Forward input.                                                              | `24224`   | [TLS Forward Input Guide](input-tls-forward.md) |
| `TLS_FORWARD_INPUT_SHARED_KEY` | Shared key for TLS Forward authentication.                                                      | _(empty)_ | [TLS Forward Input Guide](input-tls-forward.md) |
| `TLS_FORWARD_INPUT_VERIFY`     | Verify client certificates (`on` or `off`).                                                     | `off`     | [TLS Forward Input Guide](input-tls-forward.md) |
| `ENABLE_PT_FORWARD_INPUT`      | Enable Plaintext Forward input.                                                                 | `false`   | [PT Forward Input Guide](input-pt-forward.md)   |
| `PT_FORWARD_INPUT_PORT`        | Listen port for Plaintext Forward input.                                                        | `24228`   | [PT Forward Input Guide](input-pt-forward.md)   |
| `ENABLE_DOCKER_FORWARD_INPUT`  | Enable dedicated Docker container Forward input.                                                | `false`   | [Docker Forward Input Guide](input-docker.md)   |
| `DOCKER_FORWARD_INPUT_PORT`    | Listen port for Docker Forward input.                                                           | `24226`   | [Docker Forward Input Guide](input-docker.md)   |
| `ENABLE_SYSTEMD_INPUT`         | Enable systemd journal input (also auto-detected if `/host/var/log/journal` exists).            | `false`   | [Systemd Journal Guide](input-systemd.md)       |
| `SYSTEMD_FILTER_UNITS`         | Optional comma/space separated list of systemd units to filter (e.g. `gitops-.*,sshd.service`). | _(empty)_ | [Systemd Journal Guide](input-systemd.md)       |
| `ENABLE_THREADED_INPUTS`       | Enable multi-threading for supported input plugins.                                             | `false`   | [Inputs Overview](inputs.md)                    |

> [!NOTE]
> Input tag prefixes are automatically derived from `FLUENT_BIT_TAG_PREFIX` and `INFRASTRUCTURE_PROVIDER`:
>
> - **Docker Tag Prefix**: `${FLUENT_BIT_TAG_PREFIX}.${INFRASTRUCTURE_PROVIDER}.docker.` (e.g., `flb.privatecloud.docker.`)
> - **Node Log Tag Prefix**: `${FLUENT_BIT_TAG_PREFIX}.${INFRASTRUCTURE_PROVIDER}.node.log.` (e.g., `flb.privatecloud.node.log.`)

---

### Environmental & Metadata Tagging

| Variable              | Description                                                                                               | Default       | Detailed Guide                                                                                               |
| --------------------- | --------------------------------------------------------------------------------------------------------- | ------------- | ------------------------------------------------------------------------------------------------------------ |
| `ENVIRONMENT_NAME`    | Deployment environment name appended as `source_env` (e.g. `production`, `homelab`).                      | _(empty)_     | [Global Filters Guide](input-global-filters.md#2-environmental-metadata-enrichment-filter-append_recordslua) |
| `ENVIRONMENT_PROJECT` | Project name appended as `source_project`.                                                                | _(empty)_     | [Global Filters Guide](input-global-filters.md#2-environmental-metadata-enrichment-filter-append_recordslua) |
| `ENVIRONMENT_REGION`  | Region identifier appended as `source_region`.                                                            | _(empty)_     | [Global Filters Guide](input-global-filters.md#2-environmental-metadata-enrichment-filter-append_recordslua) |
| `INSTANCE_ID`         | Host instance ID appended as `source_instance_id`. Auto-fetched via IMDS for `aws`/`azure` if unassigned. | _(empty)_     | [Global Filters Guide](input-global-filters.md#2-environmental-metadata-enrichment-filter-append_recordslua) |
| `HOST_HOSTNAME`       | Host node hostname appended as `source_hostname`.                                                         | `$(hostname)` | [Global Filters Guide](input-global-filters.md#2-environmental-metadata-enrichment-filter-append_recordslua) |

---

### Output Destinations

Click any `ENABLE_*` link below to view detailed pipeline, schema, and routing documentation for that output.

| Variable                               | Description                                              | Default                      | Detailed Guide                                                    |
| -------------------------------------- | -------------------------------------------------------- | ---------------------------- | ----------------------------------------------------------------- |
| `ENABLE_STDOUT_OUTPUT`                 | Enable stdout debug output plugin for all incoming logs. | `true`                       | [Routing Guide](routing-and-forwarding.md#stdout-debug-output)    |
| `ENABLE_GRAFANA_LOKI_OUTPUT`           | Enable Grafana Loki HTTP push output plugin.             | `false`                      | [Grafana Loki Output Guide](output-loki.md)                       |
| `GRAFANA_LOKI_HOST`                    | Hostname or IP of Grafana Loki instance.                 | _(empty)_                    | [Grafana Loki Output Guide](output-loki.md)                       |
| `GRAFANA_LOKI_PORT`                    | Port of Grafana Loki instance.                           | `3100`                       | [Grafana Loki Output Guide](output-loki.md)                       |
| `GRAFANA_LOKI_URI`                     | Ingestion endpoint URI for Grafana Loki.                 | `/loki/api/v1/push`          | [Grafana Loki Output Guide](output-loki.md)                       |
| `ENABLE_OPENOBSERVE_HTTP_OUTPUT`       | Enable OpenObserve HTTP ingestion output plugin.         | `false`                      | [OpenObserve Output Guide](output-openobserve.md)                 |
| `OPENOBSERVE_HTTP_HOST`                | Hostname or IP of OpenObserve instance.                  | _(empty)_                    | [OpenObserve Output Guide](output-openobserve.md)                 |
| `OPENOBSERVE_HTTP_PORT`                | Port of OpenObserve instance.                            | `5080`                       | [OpenObserve Output Guide](output-openobserve.md)                 |
| `OPENOBSERVE_HTTP_URI`                 | Ingestion endpoint URI for OpenObserve.                  | `/api/default/default/_json` | [OpenObserve Output Guide](output-openobserve.md)                 |
| `OPENOBSERVE_HTTP_TLS`                 | Enable TLS for OpenObserve HTTP connection (`on`/`off`). | `off`                        | [OpenObserve Output Guide](output-openobserve.md)                 |
| `OPENOBSERVE_HTTP_USER`                | Basic auth username for OpenObserve.                     | _(empty)_                    | [OpenObserve Output Guide](output-openobserve.md)                 |
| `OPENOBSERVE_HTTP_PASSWD`              | Basic auth password or stream token for OpenObserve.     | _(empty)_                    | [OpenObserve Output Guide](output-openobserve.md)                 |
| `ENABLE_GRAYLOG_GELF_OUTPUT`           | Enable Graylog GELF TCP output plugin.                   | `false`                      | [Routing Guide](routing-and-forwarding.md)                        |
| `ENABLE_S3_BUCKET_COLD_STORAGE_OUTPUT` | Enable Amazon S3 cold storage output plugin.             | `false`                      | [Routing Guide](routing-and-forwarding.md)                        |
| `AWS_COLD_STORAGE_BUCKET_NAME`         | Amazon S3 bucket name for cold storage.                  | _(empty)_                    | [Routing Guide](routing-and-forwarding.md)                        |
| `AWS_COLD_STORAGE_BUCKET_REGION`       | AWS region for S3 cold storage bucket.                   | _(empty)_                    | [Routing Guide](routing-and-forwarding.md)                        |
| `ENABLE_TLS_FORWARD_OUTPUT`            | Enable TLS-encrypted upstream Forward output plugin.     | `false`                      | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |
| `TLS_FORWARD_OUTPUT_HOST`              | Remote host address for TLS Forward output.              | _(empty)_                    | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |
| `TLS_FORWARD_OUTPUT_PORT`              | Remote port for TLS Forward output.                      | `24225`                      | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |
| `TLS_FORWARD_OUTPUT_SHARED_KEY`        | Shared key for remote TLS Forward authentication.        | _(empty)_                    | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |
| `TLS_FORWARD_OUTPUT_VERIFY`            | Verify remote TLS certificate (`on`/`off`).              | `off`                        | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |
| `ENABLE_PT_FORWARD_OUTPUT`             | Enable Plaintext upstream Forward output plugin.         | `false`                      | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |
| `PT_FORWARD_OUTPUT_HOST`               | Remote host address for Plaintext Forward output.        | _(empty)_                    | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |
| `PT_FORWARD_OUTPUT_PORT`               | Remote port for Plaintext Forward output.                | `24224`                      | [Forwarding Guide](routing-and-forwarding.md#upstream-forwarding) |

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
