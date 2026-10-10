# Fluent Bit Router deployment

Use [docker-compose.yml](./docker-compose.yml) for Docker Swarm. For standalone Docker Compose, merge [overrides/docker-compose.standalone.yml](./overrides/docker-compose.standalone.yml) after the base template.

The override sets the router's service-level CPU quota using `FLUENTBIT_CPU_LIMIT`, matching the base template's `deploy.resources.limits.cpus`. The default `0` leaves CPU usage unlimited; set a value such as `0.25` to cap it at one quarter of a CPU's runtime. Keep both quota definitions consistent when editing them.

Both the router and certificate challenge proxy set `cpu_shares: 512` for lower relative CPU priority under contention than containers using the usual weight of `1024`. Both also have Unraid Dockerman and icon labels. Neither has an application WebUI, so no WebUI labels are included.

## Standalone Docker Compose

From the source repository root:

1. Prepare a local `.env` using the configuration header in `docker-swarm-templates/docker-compose.yml`. Set `FLUENTBIT_STORAGE_PATH` and `FLUENTBIT_CERTS_PATH` to absolute host directories and create them before starting. Configure the inputs and outputs you need.
2. Ensure the external `swarm-public` network exists. On a standalone host, create a bridge network with `docker network create swarm-public` if it does not already exist. On a Swarm host using an overlay network, it must allow manual container attachment. Compose creates `private-net` automatically.
3. Check that the published ports listed in the base template are available on the host, then deploy:

```bash
docker compose \
    --env-file .env \
    -f docker-swarm-templates/docker-compose.yml \
    -f docker-swarm-templates/overrides/docker-compose.standalone.yml \
    up -d
```

Use the same files and environment values for subsequent `config`, `up`, `logs` and `down` commands. Swarm placement constraints do not schedule Compose containers across hosts, and `deploy.labels` Traefik routing is intended for Swarm deployments.

On `release/latest`, the base template and `overrides/` are at the repository root: omit `docker-swarm-templates/` from the paths above. The publish action generates `docker-compose.env.example` from the base template's configuration header; use it to prepare your deployment environment.

## Portainer

On a **Docker Standalone** environment, add a stack using **Repository** and configure:

| Setting                     | Release branch value                      |
| :-------------------------- | :---------------------------------------- |
| Repository reference        | `refs/heads/release/latest`               |
| Compose path                | `docker-compose.yml`                      |
| Additional paths → Add file | `overrides/docker-compose.standalone.yml` |

For a source branch, prefix both file paths with `docker-swarm-templates/`. Load the base template's environment variables, prepare the network and host directories described above, then deploy. The override must be explicitly included. For Web editor or Upload deployments, merge the override's settings into the corresponding services in the base YAML before submitting it.

For a **Swarm** environment, use only the base template. Service-level `cpus` and `cpu_shares` belong in the standalone override because Portainer's Swarm deployment rejects them.
