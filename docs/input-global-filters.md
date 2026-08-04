# Global Core Filters Architecture

This document details the global Lua filter pipeline applied to all ingested logs in `fluent-bit-router`.

---

## Global Filter Pipeline Overview

Every log record ingested by `fluent-bit-router` passes through two global Lua filters registered in [`fluent-bit.global-filters.yaml`](../docker/overlay/etc/fluent-bit/fluent-bit.global-filters.yaml). These filters are executed **after** all input-specific filters (such as `docker_modify_records.lua` or `systemd_modify_records.lua`) have populated `source_service` and `source_category`:

```mermaid
flowchart LR
    %% TOP BLOCK: INGESTION & LOCAL FILTERS
    subgraph InputStage [Ingestion & Local Filters Stage]
        A["<b>Ingestion Input Plugin</b><br><small>HTTP, Forward, Docker, Systemd, Host Logs</small>"]
        --> B["<b>Input-Specific Filters</b><br><small>docker_modify_records.lua, systemd_modify_records.lua<br>Populates source_service & source_category</small>"]
    end

    %% Drop down connection to global filter pipeline
    B --> C

    %% MIDDLE BLOCK: GLOBAL FILTER PIPELINE
    subgraph GlobalFilterPipeline [Global Lua Filter Pipeline (fluent-bit.global-filters.yaml)]
        subgraph Filter1 [1. Core Record Formatting Filter]
            C["<b>apply_standard_record_formatting.lua</b><br><small>• Decodes string JSON<br>• Normalizes logfmt message<br>• Flattens nested tables<br>• Converts source. to source_<br>• Normalizes timestamps & levels</small>"]
        end

        C --> D

        subgraph Filter2 [2. Environmental Metadata Enrichment]
            D["<b>append_records.lua</b><br><small>• Injects source_env<br>• Injects source_hostname<br>• Injects source_project<br>• Injects source_instance_id<br>• Injects source_tag & source_aggregator</small>"]
        end
    end

    %% Drop down connection to output stage
    D --> E

    %% BOTTOM BLOCK: OUTPUT ROUTING STAGE
    subgraph OutputStage [Output Routing Stage]
        E["<b>Router Output Pipeline</b><br><small>Destination Outputs & Upstream Forwarders</small>"]
    end

    %% Structural layout constraints
    InputStage ~~~ GlobalFilterPipeline
    GlobalFilterPipeline ~~~ OutputStage
```

---

## 1. Core Record Formatting Filter (`apply_standard_record_formatting.lua`)

This Lua filter ([`apply_standard_record_formatting.lua`](../docker/overlay/etc/fluent-bit/apply_standard_record_formatting.lua)) normalizes, flattens, and cleans up raw record structures.

### Execution Flow Diagram

```mermaid
flowchart LR
    %% ROW 1: DECODING & NORMALIZATION
    subgraph Stage1 [Parsing & Normalization]
        A["<b>Raw Record Input</b>"] --> B["<b>1. Decode String JSON</b><br><small>Parses embedded JSON strings</small>"]
        B --> C["<b>2. Normalize Message</b><br><small>Builds logfmt for table messages</small>"]
    end

    %% Drop down connection to Stage 2
    C --> D

    %% ROW 2: FLATTENING & KEY MUTATION
    subgraph Stage2 [Structure & Key Cleanup]
        D["<b>3. Flatten Nested Tables</b><br><small>Converts objects to dotted keys</small>"] --> E["<b>4. Convert source. to source_</b><br><small>Renames keys to underscores</small>"]
        E --> F["<b>5. Remove Empty short_message</b><br><small>Cleans up payload size</small>"]
    end

    %% Drop down connection to Stage 3
    F --> G

    %% ROW 3: DEFAULTS & LEVEL NORMALIZATION
    subgraph Stage3 [Defaults & Severity Mapping]
        G["<b>6 & 7. Fallback Fields</b><br><small>Sets default source & service_name</small>"] --> H["<b>8. Normalize Timestamp</b><br><small>Pads Unix nanoseconds (.000000000)</small>"]
        H --> I["<b>9. Normalize Severity Level</b><br><small>Maps level code (3) & levelname (error)</small>"]
    end

    %% Drop down connection to output
    I --> J

    %% ROW 4: OUTPUT
    subgraph Stage4 [Output Stage]
        J["<b>Formatted Record Output</b>"]
    end

    %% Structural layout constraints
    Stage1 ~~~ Stage2
    Stage2 ~~~ Stage3
    Stage3 ~~~ Stage4
```

---

## 2. Environmental Metadata Enrichment Filter (`append_records.lua`)

This Lua filter ([`append_records.lua`](../docker/overlay/etc/fluent-bit/append_records.lua)) dynamically reads process environment variables at runtime via Lua's native `os.getenv()` function and injects node and environment metadata fields into log records.

### Injected Metadata Fields

| Field Name           | Source Variable          | Description                          | Example                    |
| -------------------- | ------------------------ | ------------------------------------ | -------------------------- |
| `source_tag`         | Tag                      | Full incoming Fluent-Bit tag string. | `flb.homelab.docker.nginx` |
| `source_aggregator`  | Static                   | Always set to `"fluent-bit"`.        | `fluent-bit`               |
| `source_env`         | `${ENVIRONMENT_NAME}`    | Deployment environment name.         | `production`, `homelab`    |
| `source_region`      | `${ENVIRONMENT_REGION}`  | Region identifier.                   | `us-east-1`, `local`       |
| `source_instance_id` | `${INSTANCE_ID}`         | Host instance ID or VM ID.           | `i-0123456789`             |
| `source_hostname`    | `${HOST_HOSTNAME}`       | Host server hostname.                | `homelab-node-01`          |
| `source_project`     | `${ENVIRONMENT_PROJECT}` | Project identifier.                  | `streamingtech`            |
| `source`             | Fallback                 | Defaults to `"node"` if unassigned.  | `node`                     |
