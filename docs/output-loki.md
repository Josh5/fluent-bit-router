# Grafana Loki Output Integration

This document details how `fluent-bit-router` formats, mutates, and pushes log streams to Grafana Loki using the Loki HTTP push API.

---

## Overview & Architecture

Grafana Loki ingests log lines as JSON or raw text paired with key-value labels. To prevent excessive memory consumption and index degradation in Loki, label cardinality must be strictly controlled.

`fluent-bit-router` handles Loki output through a three-stage pipeline:

1. **Stream Duplication (`rewrite_tag`)**: Creates a dedicated parallel copy of incoming records tagged `loki_fmt.<TAG>`.
2. **Record Reshaping (`apply_loki_formatting.lua`)**: Converts fields to JSON, extracts level strings, and ensures required label fields exist.
3. **Label Mapping (`logmap.json`)**: Converts selected record metadata fields into top-level Loki indexed labels.

---

## Pipeline Execution Flow

```mermaid
flowchart LR
    %% TOP BLOCK: INPUT & DUPLICATION STAGE
    subgraph InputStage [Ingestion Stage]
        A["<b>Raw Incoming Log</b><br><small>• Tag: flb.docker.nginx<br>• Payload: { message, source_service, source_category }</small>"]
        -->|Matches ^(?!.*_fmt\.).*| B["<b>1. Filter: rewrite_tag</b><br><small>• Rule: $message .* loki_fmt.$TAG true<br>• Emits copy: loki_fmt.flb.docker.nginx</small>"]
    end

    %% Drop down connection to filter pipeline
    B -->|Copy: loki_fmt.flb.docker.nginx| C

    %% MIDDLE BLOCK: LOKI FORMATTING PIPELINE
    subgraph FormatPipeline [Loki Formatting Pipeline]
        subgraph LuaFormat [Lua Record Reshaping]
            C["<b>2. Filter: lua</b><br>apply_loki_formatting.lua<br><small>• Populates message<br>• Normalizes level & levelname<br>• Ensures source_service & source exist</small>"]
        end

        C --> D

        subgraph LabelMap [Label Mapping Engine]
            D["<b>3. Output Plugin: loki</b><br>logmap.json<br><small>• Maps source_service -> service_name<br>• Maps source_category -> category<br>• Maps levelname -> level</small>"]
        end
    end

    %% Drop down connection to output stage
    D -->|HTTP POST JSON Payload| E

    %% BOTTOM BLOCK: OUTPUT STAGE
    subgraph OutputStage [Target Storage]
        E["<b>Grafana Loki Cluster</b><br><small>Endpoint: http://${GRAFANA_LOKI_HOST}:${GRAFANA_LOKI_PORT}/loki/api/v1/push</small>"]
    end

    %% Structural layout constraints to force blocks to stack vertically
    InputStage ~~~ FormatPipeline
    FormatPipeline ~~~ OutputStage
```

---

## Configuration Reference

### Environment Variables

| Variable                     | Description                                              | Default             |
| ---------------------------- | -------------------------------------------------------- | ------------------- |
| `ENABLE_GRAFANA_LOKI_OUTPUT` | Enable Grafana Loki HTTP push output (`true` / `false`). | `false`             |
| `GRAFANA_LOKI_HOST`          | Hostname or IP address of Grafana Loki instance.         | _(empty)_           |
| `GRAFANA_LOKI_PORT`          | Port of Grafana Loki instance.                           | `3100`              |
| `GRAFANA_LOKI_URI`           | HTTP push endpoint URI.                                  | `/loki/api/v1/push` |

### Generated Configuration Template

When `ENABLE_GRAFANA_LOKI_OUTPUT=true`, `entrypoint.sh` appends the following YAML block to `fluent-bit.yaml`:

```yaml
pipeline:
  filters:
    - name: rewrite_tag
      match_regex: ^(?!.*_fmt\.).*
      rule: $message .* loki_fmt.$TAG true
      emitter_name: emitter_loki
      emitter_storage.type: filesystem
      emitter_mem_buf_limit: 64M

    - name: lua
      match: "loki_fmt.*"
      script: apply_loki_formatting.lua
      call: grafana_loki_formatting

  outputs:
    - name: loki
      match: "loki_fmt.*"
      host: ${GRAFANA_LOKI_HOST}
      port: ${GRAFANA_LOKI_PORT}
      uri: ${GRAFANA_LOKI_URI}
      tls: off
      labels: input=flb
      label_map_path: /tmp/fluent-bit-custom/fluent-bit.grafana-loki.output.logmap.json
      line_format: json
```

---

## Label Mapping & Mutations

Loki labels control how log streams are indexed and queried in Grafana. `fluent-bit-router` uses `/etc/fluent-bit/fluent-bit.grafana-loki.output.logmap.json` to map record fields to Loki labels:

### `logmap.json` Definition

```json
{
  "source_service": "service_name",
  "source_category": "category",
  "source_env": "environment",
  "source_hostname": "hostname",
  "source_project": "project",
  "source_region": "region",
  "levelname": "level"
}
```

### Extracted Loki Labels Summary

| Record Field      | Loki Label Name | Description                                          | Example                             |
| ----------------- | --------------- | ---------------------------------------------------- | ----------------------------------- |
| `source_service`  | `service_name`  | Name of the service, systemd unit, or Swarm service. | `nginx`, `authlog`, `systemd`       |
| `source_category` | `category`      | High-level log category.                             | `docker`, `system`, `auth`, `audit` |
| `source_env`      | `environment`   | Deployment environment.                              | `production`, `homelab`             |
| `source_hostname` | `hostname`      | Host server node name.                               | `node-01`, `homelab-server`         |
| `source_project`  | `project`       | Infrastructure project identifier.                   | `streamingtech`                     |
| `source_region`   | `region`        | Cloud region or datacenter.                          | `us-east-1`, `local`                |
| `levelname`       | `level`         | Normalized log severity level.                       | `info`, `warn`, `error`, `debug`    |
| _(static)_        | `input`         | Static input indicator attached by output plugin.    | `flb`                               |

### Log Payload Structure in Loki

Unmapped record fields (such as `message`, `source_container_id`, `source_tag`, `source_stream`) remain inside the JSON log line payload and can be parsed at query time using LogQL (`| json`).
