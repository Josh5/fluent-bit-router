# OpenObserve Output Integration

This document details how `fluent-bit-router` streams log data to OpenObserve using its native HTTP JSON ingestion API.

---

## Overview & Architecture

OpenObserve is a cloud-native observability platform that ingests structured JSON log records over HTTP. OpenObserve uses a unified schema where timestamp records are expected under the `_timestamp` ISO8601 field.

`fluent-bit-router` handles OpenObserve ingestion via a two-stage pipeline:

1. **Stream Duplication (`rewrite_tag`)**: Creates a dedicated parallel copy of incoming log records tagged `openobserve_fmt.<TAG>`.
2. **HTTP Gzip JSON Push**: Compresses and streams JSON payloads to the configured OpenObserve HTTP endpoint with HTTP Basic Authentication.

---

## Pipeline Execution Flow

```mermaid
block-beta
    columns 5

    block:InputStage
        columns 1
        InputTitle["<b>Input Stage</b>"]
        A["<b>Enriched Incoming Log</b><br/><small>Clean tag and structured record<br/>Example: flb.docker.api</small>"]
    end

    space

    block:FilterStage
        columns 1
        FilterTitle["<b>Filter Stage</b>"]
        B["<b>1. Output Filter</b><br/>rewrite_tag<br/><small>Matches clean records<br/>Emits openobserve_fmt.$TAG copy; retains original</small>"]
    end

    space

    block:OutputStage
        columns 1
        OutputTitle["<b>Output Stage</b>"]
        C["<b>2. HTTP Output Plugin</b><br/><small>JSON with ISO8601 _timestamp<br/>Basic authentication and gzip compression</small>"]
        space
        D["<b>OpenObserve Cluster</b><br/><small>Port 5080 (default)<br/>URI: /api/default/default/_json</small>"]
    end

    A -- "Match: ^(?!.*_fmt\.).*" --> B
    B -- "Tag: openobserve_fmt.$TAG" --> C
    C -- "Gzip HTTP POST" --> D

    style InputTitle fill:none,stroke:none
    style FilterTitle fill:none,stroke:none
    style OutputTitle fill:none,stroke:none
```

---

## Configuration Reference

### Environment Variables

| Variable                                           | Description                                                  | Default                      |
| -------------------------------------------------- | ------------------------------------------------------------ | ---------------------------- |
| `ENABLE_OPENOBSERVE_HTTP_OUTPUT`                   | Enable OpenObserve HTTP output (`true` / `false`).           | `false`                      |
| `OPENOBSERVE_HTTP_HOST`                            | Hostname or IP address of OpenObserve instance.              | _(empty)_                    |
| `OPENOBSERVE_HTTP_PORT`                            | Port of OpenObserve instance.                                | `5080`                       |
| `OPENOBSERVE_HTTP_URI`                             | HTTP ingestion URI endpoint.                                 | `/api/default/default/_json` |
| `OPENOBSERVE_HTTP_TLS`                             | Enable TLS/HTTPS for connection (`on` / `off`).              | `off`                        |
| `OPENOBSERVE_HTTP_USER`                            | Basic authentication username (e.g. OpenObserve user email). | _(empty)_                    |
| `OPENOBSERVE_HTTP_PASSWD`                          | Basic authentication password or stream authorization token. | _(empty)_                    |
| `OPENOBSERVE_HTTP_BUFFER_STORAGE_TOTAL_LIMIT_SIZE` | Filesystem queue limit for OpenObserve output buffer.        | `5G`                         |
| `OPENOBSERVE_HTTP_RETRY_LIMIT`                     | Retry limit for OpenObserve output (`integer` or `false`).   | `false`                      |

### Generated Configuration Template

When `ENABLE_OPENOBSERVE_HTTP_OUTPUT=true`, `entrypoint.sh` appends the following YAML block to `fluent-bit.yaml`:

```yaml
pipeline:
  filters:
    - name: rewrite_tag
      match_regex: ^(?!.*_fmt\.).*
      rule: $message .* openobserve_fmt.$TAG true
      emitter_name: emitter_openobserve
      emitter_storage.type: filesystem
      emitter_mem_buf_limit: 64M

  outputs:
    - name: http
      match: "openobserve_fmt.*"
      host: ${OPENOBSERVE_HTTP_HOST}
      port: ${OPENOBSERVE_HTTP_PORT}
      uri: ${OPENOBSERVE_HTTP_URI}
      tls: ${OPENOBSERVE_HTTP_TLS}
      format: json
      json_date_key: _timestamp
      json_date_format: iso8601
      http_user: ${OPENOBSERVE_HTTP_USER}
      http_passwd: ${OPENOBSERVE_HTTP_PASSWD}
      compress: gzip
      storage.total_limit_size: ${OPENOBSERVE_HTTP_BUFFER_STORAGE_TOTAL_LIMIT_SIZE}
      retry_limit: ${OPENOBSERVE_HTTP_RETRY_LIMIT}
```

---

## Retry Policy & Ingestion Resilience

### Retry Behavior (`OPENOBSERVE_HTTP_RETRY_LIMIT=false`)

By default, the OpenObserve HTTP output plugin is configured with `retry_limit: false` (infinite retries) and `storage.total_limit_size: 5G`.

#### Why `false` (Infinite Retries) is Default for OpenObserve:

1. **Dynamic Schema Adaptation**: OpenObserve is a columnar storage engine (based on Apache Arrow / DataFusion / Parquet). Unlike Loki, which requires rigid label validation and stream indexing rules, OpenObserve dynamically creates and merges columns from incoming JSON payloads without rejecting batches due to label cardinality or schema mismatches.
2. **Flexible Timestamp Window**: OpenObserve natively partitions data into time-bucketed Parquet files on disk/object storage, allowing it to ingest delayed or replayed logs spanning hours or days without `400 Bad Request` rejections.
3. **Seamless Maintenance Recovery**: When OpenObserve is down for container upgrades or database compaction, Fluent Bit holds chunks in `/var/fluent-bit/storage` and continues retrying every 5 minutes (`scheduler.cap: 300`). Once OpenObserve resumes, the router drains its 5GB queue at full network speed using gzip compression with zero log loss.

---

## Field Schema in OpenObserve

OpenObserve automatically parses and indexes all top-level JSON fields present in the log record:

| Record Field                 | Description                                                  | Ingested JSON Key            |
| ---------------------------- | ------------------------------------------------------------ | ---------------------------- |
| `timestamp`                  | Epoch timestamp automatically converted to ISO8601 string.   | `_timestamp`                 |
| `message`                    | Log message body text.                                       | `message`                    |
| `service_name`               | Service name or systemd unit.                                | `service_name`               |
| `service_project`            | Logical software project or codebase producing the workload. | `service_project`            |
| `service_version`            | Version of the deployed workload.                            | `service_version`            |
| `source_category`            | High-level category (`docker`, `system`, `auth`, `audit`).   | `source_category`            |
| `source_container_name`      | Docker container name (when category is `docker`).           | `source_container_name`      |
| `source_container_id`        | Short container ID.                                          | `source_container_id`        |
| `source_stream`              | Container log stream (`stdout` / `stderr`).                  | `source_stream`              |
| `source_env`                 | Deployment environment name.                                 | `source_env`                 |
| `source_env_type`            | Lifecycle or deployment class.                               | `source_env_type`            |
| `source_hostname`            | Host node hostname.                                          | `source_hostname`            |
| `source_env_isolation_scope` | Security and credential-sharing boundary.                    | `source_env_isolation_scope` |
| `level` / `levelname`        | Normalized log severity level.                               | `level` / `levelname`        |

---

## Related Swarm Deployments

For deploying OpenObserve on Docker Swarm, refer to the [OpenObserve Docker Swarm Repository](https://github.com/Josh5/openobserve-docker-swarm).
