# Global Core Filters Architecture

This document details the global Lua filter pipeline applied to all ingested logs in `fluent-bit-router`.

---

## Global Filter Pipeline Overview

Every log record ingested by `fluent-bit-router` passes through two global Lua filters registered in [`fluent-bit.global-filters.yaml`](../docker/overlay/etc/fluent-bit/fluent-bit.global-filters.yaml). These filters are executed **after** all input-specific filters (such as `docker_modify_records.lua` or `systemd_modify_records.lua`) have populated `source_service` and `source_category`:

```mermaid
block-beta
    columns 5

    block:InputStage
        columns 1
        InputTitle["<b>Input Stage</b>"]
        A["<b>Ingestion Input Plugin</b><br/><small>HTTP, Forward, Docker,<br/>Systemd, or host log input</small>"]
    end

    space

    block:FilterStage
        columns 1
        FilterTitle["<b>Filter Stage</b>"]
        B["<b>1. Input-Specific Filter</b><br/><small>For inputs that define one<br/>Populates source_service and source_category</small>"]
        space
        C["<b>2. Global Filter</b><br/>apply_standard_record_formatting.lua<br/><small>Decodes JSON and normalizes message<br/>Flattens tables and source keys<br/>Normalizes timestamps and levels</small>"]
        space
        D["<b>3. Global Filter</b><br/>append_records.lua<br/><small>Adds environment, region, instance,<br/>host, project, tag, and aggregator metadata</small>"]
    end

    space

    block:OutputStage
        columns 1
        OutputTitle["<b>Output Stage</b>"]
        space
        E["<b>Router Output Pipeline</b><br/><small>Destination outputs<br/>Upstream forwarders</small>"]
    end

    A --> B
    B --> C
    C --> D
    D -- "Formatted and enriched records" --> E

    style InputTitle fill:none,stroke:none
    style FilterTitle fill:none,stroke:none
    style OutputTitle fill:none,stroke:none
```

---

## 1. Core Record Formatting Filter (`apply_standard_record_formatting.lua`)

This Lua filter ([`apply_standard_record_formatting.lua`](../docker/overlay/etc/fluent-bit/apply_standard_record_formatting.lua)) normalizes, flattens, and cleans up raw record structures.

Only the `message`, `log`, and `msg` envelope fields are expanded into the record root. Their precedence is `message`, then `log`, then `msg`; conflicting values are preserved as `_extracted`, `_extracted2`, and subsequent fields. JSON decoded from any other field remains under that field's dotted namespace.

Valid application timestamps remain unchanged in the record and are parsed into Fluent Bit's `{sec, nsec}` event-time representation. Numeric timestamps may use Unix seconds, milliseconds, microseconds, or nanoseconds; 19-digit nanosecond values should be strings to avoid Lua floating-point precision loss. When the application timestamp is absent or invalid, the existing Fluent Bit event timestamp is retained and added to the record.

### Execution Flow Diagram

```mermaid
block-beta
    columns 5

    block:InputStage
        columns 1
        InputTitle["<b>Input Stage</b>"]
        A["<b>Raw Record Input</b>"]
    end

    space

    block:FilterStage
        columns 1
        FilterTitle["<b>Filter Stage</b>"]
        B["<b>1. Decode String JSON</b><br/><small>Preserves non-envelope namespaces</small>"]
        C["<b>2. Normalize Message</b><br/><small>Expands log, message, and msg envelopes</small>"]
        D["<b>3. Flatten Nested Tables</b><br/><small>Converts objects to dotted keys</small>"]
        E["<b>4. Convert source. Keys</b><br/><small>Renames source. prefixes to source_</small>"]
        F["<b>5. Remove Empty short_message</b><br/><small>Cleans up the payload</small>"]
        G["<b>6–7. Apply Fallback Fields</b><br/><small>Sets default source and service_name</small>"]
        H["<b>8. Normalize Event Time</b><br/><small>Uses {sec,nsec}; preserves the original field</small>"]
        I["<b>9. Normalize Severity</b><br/><small>Maps numeric level and levelname</small>"]
    end

    space

    block:OutputStage
        columns 1
        OutputTitle["<b>Output Stage</b>"]
        J["<b>Formatted Record Output</b>"]
    end

    A --> B
    B --> C
    C --> D
    D --> E
    E --> F
    F --> G
    G --> H
    H --> I
    I --> J

    style InputTitle fill:none,stroke:none
    style FilterTitle fill:none,stroke:none
    style OutputTitle fill:none,stroke:none
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
