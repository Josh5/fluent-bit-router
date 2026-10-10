# Docker Swarm Stack Setup

## Choose a template

| Template                                   | Purpose                                             |
| :----------------------------------------- | :-------------------------------------------------- |
| [docker-compose.yml](./docker-compose.yml) | Collect logs and forward them to your destinations. |

Configure the inputs and outputs you need using the template's environment settings. For remote syslog collection, see the [syslog setup and troubleshooting guide](<url>/blob/master/docs/input-syslog-udp.md).

## Deploy with Portainer

1. Prepare the external `swarm-public` network and host directories. Set `FLUENTBIT_STORAGE_PATH` and `FLUENTBIT_CERTS_PATH` to absolute paths and create them on the node that will run the router. Check that the template's published ports are available.
2. In your Swarm environment, add a stack and select **Repository** as the build method. Name it `fluent-bit-router`.
3. Set **Repository URL** to `<url>` and **Repository reference** to `refs/heads/<branch>`.
4. Set **Compose path** to `docker-compose.yml`.
5. Open [docker-compose.env.example](<url>/blob/<branch>/docker-compose.env.example) on the release branch. Copy its contents into **Environment variables → Advanced mode**, then enter your deployment values. Option descriptions and defaults come from the YAML header.
6. Enable GitOps polling updates with an interval of `5m`, then deploy the stack.

For a source branch, use `docker-swarm-templates/docker-compose.yml` and prepare your environment from its configuration header instead of the release branch's `.env.example`.

## Deploy with standalone Docker Compose

Include the override below after the base template. For Swarm, use only the base template; Portainer rejects the standalone CPU settings.

| Base template                              | Standalone override                                                                  |
| :----------------------------------------- | :----------------------------------------------------------------------------------- |
| [docker-compose.yml](./docker-compose.yml) | [overrides/docker-compose.standalone.yml](./overrides/docker-compose.standalone.yml) |

Prepare the host directories and ports described above. On a standalone host, create the external network with `docker network create swarm-public` if it does not already exist. If using a Swarm overlay network, it must allow manual container attachment.

From the repository root, prepare `.env` using the base template's configuration header, then run:

```bash
docker compose \
    --env-file .env \
    -f docker-swarm-templates/docker-compose.yml \
    -f docker-swarm-templates/overrides/docker-compose.standalone.yml \
    up -d
```

On the release branch, templates are at the repository root: omit `docker-swarm-templates/` from these paths and use `docker-compose.env.example` to prepare your environment. Use the same files and environment values for subsequent Compose commands, including `config`, `up` and `down`.

Standalone Compose runs on the local host; configure any reverse proxy for that host separately.

For **Portainer on a Docker Standalone environment**, select **Repository** and set:

| Setting                     | Release branch value                      |
| :-------------------------- | :---------------------------------------- |
| Repository reference        | `refs/heads/release/latest`               |
| Compose path                | `docker-compose.yml`                      |
| Additional paths → Add file | `overrides/docker-compose.standalone.yml` |

For a source branch, prefix both paths with `docker-swarm-templates/`. Load your environment variables and deploy. Include the override explicitly in **Additional paths**. For Web editor or Upload deployments, merge the override into the base YAML before submitting it.
