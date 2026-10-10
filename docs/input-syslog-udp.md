# Network Syslog Servers

Receive modern (RFC 5424) and legacy (RFC 3164) syslog from remote hosts and network devices, using either listener or both together. Messages go to your enabled outputs with the sender's hostname, application and severity. No host log mounts or systemd input are required.

## Configuration

| Variable                     | Default | Purpose                                               |
| :--------------------------- | :------ | :---------------------------------------------------- |
| `ENABLE_SYSLOG_INPUT`        | `false` | Enable the RFC 5424 listener.                         |
| `SYSLOG_INPUT_MODE`          | `udp`   | RFC 5424 transport: `udp` or newline-delimited `tcp`. |
| `SYSLOG_INPUT_PORT`          | `5140`  | RFC 5424 listener and published host port.            |
| `ENABLE_SYSLOG_LEGACY_INPUT` | `false` | Enable the RFC 3164 legacy listener.                  |
| `SYSLOG_LEGACY_INPUT_MODE`   | `udp`   | RFC 3164 transport: `udp` or newline-delimited `tcp`. |
| `SYSLOG_LEGACY_INPUT_PORT`   | `5141`  | RFC 3164 listener and published host port.            |

Enable either listener independently, or both together:

```dotenv
ENABLE_SYSLOG_INPUT=true
SYSLOG_INPUT_MODE=udp
SYSLOG_INPUT_PORT=5140

ENABLE_SYSLOG_LEGACY_INPUT=true
SYSLOG_LEGACY_INPUT_MODE=udp
SYSLOG_LEGACY_INPUT_PORT=5141
```

Set these values in `.env` or Portainer's stack environment, then recreate the stack. Configure each sender with the router host's LAN address, matching format, transport and port. For traditional Unraid syslog, use the legacy listener on port `5141`.

The Compose templates publish the configured ports, including those of disabled listeners. Choose free ports from 1–65535; listeners using the same transport need different ports. You can use `514` if it is free on the host. With direct `docker run` deployments, publish the ports yourself, for example `-p 5140:5140/udp -p 5141:5141/udp`.

Allow intended senders through the host firewall. Keep these unencrypted listeners on a trusted network.

## Verify delivery

Temporarily set `ENABLE_STDOUT_OUTPUT=true`, then send one message to each enabled UDP listener:

```bash
logger --udp --server ROUTER_LAN_IP --port 5140 --rfc5424 \
    --tag syslog-test --priority user.warning 'RFC 5424 test'
logger --udp --server ROUTER_LAN_IP --port 5141 --rfc3164 \
    --tag syslog-test --priority user.warning 'RFC 3164 test'
```

Look in the router logs for `service_name=syslog-test`, the sender's hostname and `levelname=warn`, then check your configured destination. For TCP listeners, use `logger --tcp` instead of `--udp`. Disable stdout again after testing if you do not need it.

## Troubleshooting

- **No messages:** Check that the matching listener is enabled, the sender uses the correct format and transport, and the host port is reachable. Confirm that your router image supports these settings and that an output is enabled.
- **Stack cannot start:** Check for occupied ports, including mappings for disabled listeners. Unraid's own syslog server may already use port `514`.
- **Unexpected timestamps:** Legacy messages contain no year or timezone, so these must be inferred. RFC 5424 messages without a timestamp use the receive time. Prefer RFC 5424 when accurate dates across hosts matter.
- **Missing messages:** UDP does not guarantee delivery. If the sender supports it, use newline-delimited TCP and set that listener's mode to `tcp`.
