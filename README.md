# My custom Fluent-Bit container for collecting and routing logs

I use this for collecting logs and formatting them before forwarding to Graylog, S3, Grafana Loki, or OpenObserve.

See [grafana-docker-swarm](https://github.com/Josh5/grafana-docker-swarm) project for how it can be used.

## Development setup

From the root of this project, run these commands:

1. Create the `.env` file

   ```
   cp -fv .env.example .env
   ```

2. Modify any additional config options in the `.env` file.

3. Create any required directories

   ```
   source .env
   mkdir -p \
       ${FLUENTBIT_STORAGE_PATH:?} \
       ${FLUENTBIT_CERTS_PATH:?}
   ```

4. Run the dev compose stack

   ```
   sudo docker compose --env-file .env up -d --build
   ```
