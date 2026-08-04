# AWS Cloud Agent Log Ingestion Input

This document details AWS SSM Agent and AWS ECS host log ingestion supported by `fluent-bit-router`.

---

## Overview

When deployed on AWS EC2 instances with `/host/var/log` mounted, `fluent-bit-router` automatically detects AWS SSM Agent logs (`amazon-ssm-agent.log`, `errors.log`) and AWS ECS host logs (`audit.log`, `ecs-agent.log`, `ecs-init.log`, `ecs-volume-plugin.log`), tailing them with specialized multiline and logfmt parsers.

---

## Configuration Reference & Auto-Detection

### File Detection Triggers

| Target Directory           | Log Files Tailed                                                      | Ingested `source_service`                                 | Parsers Used                                                                          |
| -------------------------- | --------------------------------------------------------------------- | --------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `/host/var/log/amazon/ssm` | `amazon-ssm-agent.log`, `errors.log`                                  | `amazon-ssm-agent`                                        | `amazon-ssm-agent-access`, `amazon-ssm-agent-multiline-error`                         |
| `/host/var/log/ecs`        | `audit.log`, `ecs-agent.log`, `ecs-init.log`, `ecs-volume-plugin.log` | `ecs-audit`, `ecs-agent`, `ecs-init`, `ecs-volume-plugin` | `amazon-ecs-audit`, `amazon-ecs-agent`, `amazon-ecs-init`, `amazon-ecs-volume-plugin` |

---

## Ingestion & Filtering Flow Diagram

```mermaid
block-beta
    columns 5

    block:InputStage
        columns 1
        InputTitle["<b>Input Stage</b>"]
        A["<b>AWS SSM Agent Logs</b><br/><small>/host/var/log/amazon/ssm<br/>amazon-ssm-agent.log and errors.log</small>"]
        B["<b>SSM Tail Input</b><br/><small>Access and multiline-error parsers</small>"]
        space
        C["<b>AWS ECS Host Logs</b><br/><small>/host/var/log/ecs<br/>audit, agent, init, and volume-plugin logs</small>"]
        D["<b>ECS Tail Inputs</b><br/><small>Specialized ECS parsers</small>"]
    end

    space

    block:FilterStage
        columns 1
        FilterTitle["<b>Filter Stage</b>"]
        E["<b>1. SSM Input Filter</b><br/>modify<br/><small>Sets source_service=amazon-ssm-agent</small>"]
        space
        F["<b>1. ECS Input Filters</b><br/>modify<br/><small>Set source_service to ecs-audit,<br/>ecs-agent, ecs-init, or ecs-volume-plugin</small>"]
        space
        G["<b>2. Global Filter</b><br/>apply_standard_record_formatting.lua<br/><small>Flattens objects<br/>Normalizes message, level, and timestamp</small>"]
        space
        H["<b>3. Global Filter</b><br/>append_records.lua<br/><small>Adds environment, host, project,<br/>tag, and aggregator metadata</small>"]
    end

    space

    block:OutputStage
        columns 1
        OutputTitle["<b>Output Stage</b>"]
        space
        I["<b>Router Output Pipeline</b><br/><small>Destination outputs<br/>Upstream forwarders</small>"]
    end

    A --> B
    C --> D
    B -- "Parsed SSM records" --> E
    D -- "Parsed ECS records" --> F
    E --> G
    F --> G
    G --> H
    H -- "Enriched AWS records" --> I

    style InputTitle fill:none,stroke:none
    style FilterTitle fill:none,stroke:none
    style OutputTitle fill:none,stroke:none
```

---

## Applied Parsers & Filters

### Custom Parsers (`pipeline.parsers` & `multiline_parsers`)

```yaml
pipeline:
  parsers:
    - name: amazon-ssm-agent-access
      format: regex
      regex: '^(?<time>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})(?>\.\d{1,4})?\s+(?<level>\w+)\s*(?>\[(?<component>[^\]]+)\])?\s*(?<message>.*)$'
      time_key: time
      time_format: '%Y-%m-%d %H:%M:%S'

    - name: amazon-ecs-agent
      format: logfmt
      time_key: time
      time_keep: On

  multiline_parsers:
    - name: amazon-ssm-agent-multiline-error
      type: regex
      flush_timeout: 1000
      rules:
        - state: start_state
          regex: '/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,4})/'
          next_state: cont
        - state: cont
          regex: '/^(?!\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{1,4}).*/'
          next_state: cont
```

### Global Core Filters

- **[`apply_standard_record_formatting.lua`](input-global-filters.md#1-core-record-formatting-filter-apply_standard_record_formattinglua)**: Decodes string JSON, normalizes `message`, flattens nested objects, converts `source.` keys to `source_`, and normalizes level/timestamp.
- **[`append_records.lua`](input-global-filters.md#2-environmental-metadata-enrichment-filter-append_recordslua)**: Appends `source_env`, `source_hostname`, `source_project`, `source_tag`, and `source_aggregator`.
