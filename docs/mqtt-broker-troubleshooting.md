# MQTT broker troubleshooting

## Interpreting the Node-RED error

```text
Connection failed to broker: nodered-kai-bridge@mqtt://127.0.0.1:1883
```

`nodered-kai-bridge` is the configured MQTT client ID. The important part is `127.0.0.1:1883`: Node-RED attempted to connect to a broker on the same runtime host/network namespace and failed.

## Correct host selection

- Node-RED and broker on the same non-container host: `127.0.0.1` may be correct.
- Broker on another computer: use that computer's LAN IP or DNS name.
- Node-RED in Docker and broker on the host: use the platform host gateway, not container loopback.
- Node-RED and broker in Docker Compose: use the broker service name, for example `mosquitto`.
- Managed/cloud broker: use its assigned hostname and TLS port.

## Checks

1. Confirm the broker process is running.
2. Confirm the port: normally 1883 for plain MQTT or 8883 for MQTT over TLS.
3. Confirm username/password and ACL permission for `spBv1.0/#`.
4. Confirm firewall and container network rules.
5. Ensure the MQTT client ID is unique when the broker disallows duplicate active sessions.
6. In Node-RED, open **KAI Sparkplug Broker**, correct the settings, then deploy.

## Command-line test

From the same host or container as Node-RED:

```bash
mosquitto_sub -h <broker-host> -p 1883 -t 'spBv1.0/#' -v
```

With credentials:

```bash
mosquitto_sub -h <broker-host> -p 1883 -u '<username>' -P '<password>' -t 'spBv1.0/#' -v
```

If this command cannot connect, the problem is broker reachability/authentication rather than the desktop application.
