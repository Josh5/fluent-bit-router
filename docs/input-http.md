# HTTP Ingestion Input

This document details the HTTP log ingestion input supported by `fluent-bit-router`.

---

## Overview

The HTTP input plugin allows `fluent-bit-router` to receive log batches sent as HTTP `POST` JSON requests. It is useful for receiving logs from webhooks, serverless functions, application endpoints, or load balancers.

---

## Configuration Reference

### Environment Variables

| Variable                 | Description                                                     | Default |
| ------------------------ | --------------------------------------------------------------- | ------- |
| `ENABLE_HTTP_INPUT`      | Enable HTTP input plugin (`true` / `false`).                    | `false` |
| `HTTP_INPUT_PORT`        | Listen port for HTTP requests.                                  | `8080`  |
| `ENABLE_THREADED_INPUTS` | Enable multi-threading for input processing (`true` / `false`). | `false` |

### Configuration Template

When `ENABLE_HTTP_INPUT=true`, `entrypoint.sh` generates the following YAML block in `fluent-bit.http.input.yaml`:

```yaml
pipeline:
  inputs:
    - name: http
      listen: 0.0.0.0
      port: ${HTTP_INPUT_PORT}
      mem_buf_limit: 64M
      storage.type: filesystem
      storage.pause_on_chunks_overlimit: on
      buffer_chunk_size: 5M
      buffer_max_size: 1000M
      threaded: ${ENABLE_THREADED_INPUTS}
```

---

## Ingestion & Filtering Flow Diagram

```mermaid
block-beta
    columns 5

    block:InputStage
        columns 1
        InputTitle["<b>Input Stage</b>"]
        A["<b>HTTP Client</b><br/><small>Webhook, serverless function,<br/>application, or load balancer</small>"]
        space
        B["<b>HTTP Input Engine</b><br/>http plugin<br/><small>Listen: 0.0.0.0:8080 (default)<br/>Filesystem buffering</small>"]
    end

    space

    block:FilterStage
        columns 1
        FilterTitle["<b>Filter Stage</b>"]
        C["<b>1. Global Filter</b><br/>apply_standard_record_formatting.lua<br/><small>Decodes string JSON and flattens objects<br/>Normalizes message, level, and timestamp</small>"]
        space
        D["<b>2. Global Filter</b><br/>append_records.lua<br/><small>Adds environment and host metadata<br/>Adds project, tag, and aggregator metadata</small>"]
    end

    space

    block:OutputStage
        columns 1
        OutputTitle["<b>Output Stage</b>"]
        space
        E["<b>Router Output Pipeline</b><br/><small>Destination outputs<br/>Upstream forwarders</small>"]
    end

    A -- "POST / (JSON)" --> B
    B -- "Ingested JSON records" --> C
    C --> D
    D -- "Enriched records" --> E

    style InputTitle fill:none,stroke:none
    style FilterTitle fill:none,stroke:none
    style OutputTitle fill:none,stroke:none
```

---

## Applied Filters

### 1. Global Core Filters

Logs received via HTTP pass through all global core filters:

- **[`apply_standard_record_formatting.lua`](input-global-filters.md#1-core-record-formatting-filter-apply_standard_record_formattinglua)**: Decodes string JSON, normalizes `message`, flattens nested objects, converts `source.` keys to `source_`, and normalizes level/timestamp.
- **[`append_records.lua`](input-global-filters.md#2-environmental-metadata-enrichment-filter-append_recordslua)**: Appends `source_env`, `source_hostname`, `source_project`, `source_tag`, and `source_aggregator`.

---

## Verification & Testing

Send a test JSON payload to the HTTP endpoint using `curl`:

```bash
curl -X POST http://127.0.0.1:8080/ \
  -H "Content-Type: application/json" \
  -d '[{"log": "Test HTTP log message", "service": "my-app", "level": "info"}]'
```

Verify in `fluent-bit-router` container logs (`docker logs -f fluent-bit-router`) that the log is received, formatted, and enriched.
