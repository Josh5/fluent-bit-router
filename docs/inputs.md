# Ingestion Inputs & Processing Pipelines

This document provides an overview of all ingestion inputs supported by `fluent-bit-router`. Click any input link below to view its complete environment configuration, input-specific filters, global processing pipeline, and flow diagrams.

---

## Global Core Filtering

All incoming logs pass through global Lua filters before reaching output destinations.

- **[Global Core Filters Architecture Guide](input-global-filters.md)**: Explains [`apply_standard_record_formatting.lua`](input-global-filters.md#1-core-record-formatting-filter-apply_standard_record_formattinglua) (JSON decoding, flattening, `source_` key conversion, timestamp/level normalization) and [`append_records.lua`](input-global-filters.md#2-environmental-metadata-enrichment-filter-append_recordslua) (injecting `source_env`, `source_hostname`, `source_project`, `source_tag`).

---

## 1. Network Ingestion Inputs

Network inputs listen on TCP ports to accept logs pushed from remote agents, applications, or Docker log drivers:

- **[HTTP Input (`ENABLE_HTTP_INPUT`)](input-http.md)**: Receives HTTP `POST` JSON log batches on port `8080`.
- **[Plaintext Forward Input (`ENABLE_PT_FORWARD_INPUT`)](input-pt-forward.md)**: Receives unencrypted Fluent Forward binary streams on port `24224`.
- **[TLS Forward Input (`ENABLE_TLS_FORWARD_INPUT`)](input-tls-forward.md)**: Receives encrypted Fluent Forward binary streams on port `24225` with optional shared key authentication.
- **[Docker Container Forward Input (`ENABLE_DOCKER_FORWARD_INPUT`)](input-docker.md)**: Dedicated input listening on port `24226` for Docker `fluentd` log drivers. Runs `docker_modify_records.lua` to extract container names, IDs, streams, and normalize Docker Swarm service names.
- **[Traefik Reverse Proxy Access Log Input](input-traefik-proxy.md)**: Parses Traefik JSON access log streams, extracts HTTP client IPs, status codes, methods, duration, and sets `source_category = "proxy"`.

---

## 2. Host Log Collection Inputs

When running as an edge node agent with host log directories mounted (`-v /var/log:/host/var/log:ro`), `fluent-bit-router` ingests host log files when explicitly enabled:

- **[Systemd Journal & System Log Input (`ENABLE_SYSTEMD_INPUT`)](input-systemd.md)**: Tails host systemd journald entries (or syslog/messages fallback) and runs `systemd_modify_records.lua` to extract unit names and normalize priority levels.
- **[Host Auth Log Input (`ENABLE_AUTH_LOG_INPUT`) & Audit Log Input (`ENABLE_AUDIT_LOG_INPUT`)](input-auth-audit.md)**: Tails `/var/log/auth.log` (`secure`) and `/var/log/audit/audit.log` using custom `gitops_auth_log` and `gitops_audit_log` regex parsers.
- **[AWS SSM Agent Input (`ENABLE_AWS_SSM_INPUT`) & ECS Host Input (`ENABLE_AWS_ECS_INPUT`)](input-aws-cloud.md)**: Tails AWS SSM Agent logs (`amazon-ssm-agent.log`, `errors.log`) and ECS host logs (`audit.log`, `ecs-agent.log`, `ecs-init.log`, `ecs-volume-plugin.log`) using multiline and logfmt parsers.
