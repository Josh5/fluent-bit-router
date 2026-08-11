# Fluent-Bit Log Router & Edge Agent

`fluent-bit-router` is a high-performance, containerized log router and edge collection agent built on [Fluent-Bit](https://fluentbit.io/). It provides dynamic log collection, host/container metadata enrichment, and multi-destination routing for Docker Swarm clusters, homelab server stacks, Docker-in-Docker (DIND) environments, and cloud virtual machines.

---

## What Problem Does This Project Solve?

Modern multi-host and containerized environments generate logs across diverse sources (Docker container streams, systemd journald, SSH authentication logs, kernel audit events, and reverse proxies). Standardizing log collection across heterogenous infrastructure requires a lightweight agent that can:

- **Ingest Multi-Source Logs**: Collect from network protocols (HTTP, Fluent Forward), Docker log drivers, systemd journals, and host log files.
- **Enrich Records in Real Time**: Normalize Swarm service names (`stack_service.slot.taskid`), extract container IDs, classify log categories (`docker`, `system`, `auth`, `audit`), and inject environmental metadata (`source_env`, `source_type`, `source_region`, `source_hostname`, `source_project`).
- **Route & Split Streams**: Route raw enriched log streams to central storage backends (Grafana Loki, OpenObserve, Graylog, Amazon S3) or forward un-altered streams upstream across multi-hop network topologies without cross-contaminating output formatters.
- **Run Anywhere**: Deploy as a Docker Swarm service, standalone Docker container with `--net=host`, or inside DIND containers.

---

## Quickstart Guide

1. **Clone the repository and prepare environment configuration**:

   ```bash
   cp -fv .env.example .env
   ```

2. **Configure environment variables** in `.env`:
   - Set inputs to enable (e.g. `ENABLE_DOCKER_FORWARD_INPUT=true`, `ENABLE_HTTP_INPUT=true`).
   - Set destination backends (e.g. `ENABLE_GRAFANA_LOKI_OUTPUT=true`, `GRAFANA_LOKI_HOST=loki`).
   - Refer to the [Configuration Reference Guide](docs/configuration.md) for all available options.

3. **Start the router container**:

   ```bash
   sudo docker compose --env-file .env up -d --build
   ```

4. **Verify container logs**:
   ```bash
   sudo docker compose logs -f
   ```

> [!TIP]
> **Single Node Connection Debugging (`stdout_debug`)**:
> To debug log delivery for a specific node, prepend `stdout_debug` to its tag prefix (e.g. `stdout_debug.flb.privatecloud.docker.app`). When `ENABLE_STDOUT_OUTPUT=true`, `fluent-bit-router` prints all clean records directly to container logs for real-time payload auditing.

---

## Development Setup

From the root of this project:

```bash
# 1. Copy sample environment config
cp -fv .env.example .env

# 2. Source environment variables and create required local directories
source .env
mkdir -p \
    "${FLUENTBIT_STORAGE_PATH:-/tmp/fluent-bit/storage}" \
    "${FLUENTBIT_CERTS_PATH:-/tmp/fluent-bit/certs}"

# 3. Build and launch development stack
sudo docker compose --env-file .env up -d --build
```

To send a test log payload during development:

```bash
./tests/send-single-log.sh
```

### Creating a Tagged Release

Tagged container releases use `v<fluent-bit-version>-<UTC-date>`, where the version must match `FLUENT_BIT_RELEASE_VERSION` in [`docker/Dockerfile`](docker/Dockerfile). For example, a router built with Fluent Bit `5.0.9` and released on 11 August 2026 is tagged `v5.0.9-20260811` and published as `ghcr.io/josh5/fluent-bit-router:v5.0.9-20260811`.

The Fluent Bit version identifies the upstream runtime embedded in the image, while the date distinguishes router releases that use the same upstream version. If more than one release is required on the same UTC date, append a numeric revision such as `.2`: `v5.0.9-20260811.2`. Release tags are immutable; never move or reuse an existing tag.

1. Ensure the intended changes are committed and pushed on `master`, the working tree is clean, the local branch matches its upstream branch, and the local tag list is current.
2. Confirm `FLUENT_BIT_RELEASE_VERSION` identifies the intended upstream version. When changing it, build the image and verify the reported Fluent Bit version before creating the release commit.
3. Build the release candidate and confirm that the installed runtime matches `FLUENT_BIT_RELEASE_VERSION`:

   ```bash
   sudo docker build --pull --tag fluent-bit-router:release-candidate docker
   sudo docker run --rm \
       --entrypoint /opt/fluent-bit/bin/fluent-bit \
       fluent-bit-router:release-candidate \
       --version
   ```

4. Create the annotated release tag. The task reads `FLUENT_BIT_RELEASE_VERSION` from the Dockerfile, uses the current UTC date, and automatically selects `.2`, `.3`, and so on when a tag for that version and date already exists locally:

   ```bash
   task tag
   ```

5. Run the exact `git push origin ...` command displayed in the task's `NEXT STEP` block.

6. The tag push triggers the `Publish` GitHub Actions workflow, which builds the multi-architecture image once and publishes it under both the exact release tag and `latest`. Verify the tagged image before updating a deployment to use it:

   ```bash
   sudo docker pull "ghcr.io/josh5/fluent-bit-router:${RELEASE_TAG:?}"
   sudo docker run --rm \
       --entrypoint /opt/fluent-bit/bin/fluent-bit \
       "ghcr.io/josh5/fluent-bit-router:${RELEASE_TAG:?}" \
       --version
   ```

Keep deployments on their existing image reference until the tagged GHCR image has been published and verified. Update pinned deployments deliberately so that each version change is reviewable and reversible.

---

## Documentation Sitemap

Detailed documentation is available in the `docs/` directory:

- **[Configuration Reference](docs/configuration.md)**: Complete guide to all supported environment variables, flags, ports, and storage settings.
- **[Routing & Upstream Forwarding](docs/routing-and-forwarding.md)**: Architecture guide covering rich tagging, tag isolation (`^(?!.*_fmt\.).*`), and multi-hop Plaintext/TLS forwarding.
- **[Global Core Filters Architecture](docs/input-global-filters.md)**: Deep-dive guide covering [`apply_standard_record_formatting.lua`](docs/input-global-filters.md#1-core-record-formatting-filter-apply_standard_record_formattinglua) and [`append_records.lua`](docs/input-global-filters.md#2-environmental-metadata-enrichment-filter-append_recordslua).
- **[Ingestion Inputs Overview](docs/inputs.md)**: Index and overview of all network and host log collection inputs.
  - **[HTTP Input](docs/input-http.md)**: Ingesting HTTP `POST` JSON log batches on port `8080`.
  - **[Plaintext Forward Input](docs/input-pt-forward.md)**: Ingesting unencrypted Fluent Forward streams on port `24224`.
  - **[TLS Forward Input](docs/input-tls-forward.md)**: Ingesting TLS-encrypted Fluent Forward streams on port `24225`.
  - **[Docker Container Forward Input](docs/input-docker.md)**: Dedicated Docker log driver input on port `24226` with `docker_modify_records.lua`.
  - **[Traefik Proxy Access Log Input](docs/input-traefik-proxy.md)**: Parsing Traefik reverse proxy JSON access logs with `traefik_modify_records.lua`.
  - **[Systemd Journal Input](docs/input-systemd.md)**: Tailing host systemd journald entries with `systemd_modify_records.lua`.
  - **[Host Auth & Audit Log Input](docs/input-auth-audit.md)**: Auto-detecting and tailing `/var/log/auth.log` and `/var/log/audit/audit.log`.
  - **[AWS Cloud Agent Log Input](docs/input-aws-cloud.md)**: Auto-detecting and tailing AWS SSM Agent and ECS host logs.
- **[Grafana Loki Integration](docs/output-loki.md)**: In-depth documentation on `rewrite_tag`, `logmap.json`, and Loki label mapping.
- **[OpenObserve Integration](docs/output-openobserve.md)**: Documentation on HTTP JSON streaming, `_timestamp` ISO8601 formatting, and gzip compression for OpenObserve.

---

## Related Swarm Stacks

- **[Grafana Docker Swarm Stack](https://github.com/Josh5/grafana-docker-swarm)**: Production Docker Swarm stack deploying Grafana, Loki, and Prometheus.
- **[OpenObserve Docker Swarm Stack](https://github.com/Josh5/openobserve-docker-swarm)**: Production Docker Swarm stack deploying OpenObserve observability cluster.
