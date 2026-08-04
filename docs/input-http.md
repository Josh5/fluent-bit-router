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
flowchart LR
    %% TOP BLOCK: INPUT STAGE
    subgraph InputStage [Input Stage]
        A["HTTP Client / Webhook"] -->|POST / (JSON Payload)| B["<b>HTTP Input Engine</b><br><small>Listen: 0.0.0.0:8080</small>"]
    end

    %% Drop down connection to filter pipeline
    B -->|Ingested JSON Stream| C

    %% MIDDLE BLOCK: LUA FILTER PIPELINE
    subgraph FilterPipeline [Global Lua Filter Pipeline]
        subgraph GlobalFormatting [Global Formatter]
            C["<b>1. Global Filter</b><br>apply-standard-record-formatting.lua<br><small>• Decodes string JSON<br>• Flattens objects & normalizes level/time</small>"]
        end

        C --> D

        subgraph GlobalEnrichment [Global Metadata]
            D["<b>2. Global Filter</b><br>append_records.lua<br><small>• Injects source_env, source_hostname<br>• Injects source_project & source_tag</small>"]
        end
    end

    %% Drop down connection to output stage
    D -->|Enriched Records| E

    %% BOTTOM BLOCK: OUTPUT STAGE
    subgraph OutputStage [Output Stage]
        E["<b>Router Output Pipeline</b><br><small>Destination Outputs & Upstream Forwarders</small>"]
    end

    %% Structural layout constraints
    InputStage ~~~ FilterPipeline
    FilterPipeline ~~~ OutputStage
```

---

## Applied Filters

### 1. Global Core Filters

Logs received via HTTP pass through all global core filters:

- **[`apply-standard-record-formatting.lua`](input-global-filters.md#1-core-record-formatting-filter-apply-standard-record-formattinglua)**: Decodes string JSON, normalizes `message`, flattens nested objects, converts `source.` keys to `source_`, and normalizes level/timestamp.
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
