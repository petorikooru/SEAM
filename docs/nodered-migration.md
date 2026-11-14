# Node-RED migration guide

## Version 5.2 result

The local MQTT/Sparkplug daemon is replaced by Node-RED. Version 5.2 additionally replaces four global widget WebSockets with one dedicated WebSocket per physical sensor.

## Deployment

1. Back up `settings.db` and `telemetry.db`.
2. Install the custom Node-RED decoder.
3. Import `nodered/flows/spbv1.0-kai-bridge.json`.
4. Configure the actual MQTT broker address and credentials.
5. Confirm the MQTT In output type is Buffer.
6. Edit the `device_id` switch rules and dedicated WebSocket paths.
7. Deploy and verify canonical JSON on every sensor endpoint.
8. Configure only the Node-RED host and port on the desktop Node-RED page.
9. Add each desktop sensor with its exact `device_id` and WebSocket path.
10. Verify live charts, indicators, GNSS, storage, and CSV export.

## Database migration

Opening v5.2 migrates `settings.db` to schema version 3 and adds `sensors.websocket_endpoint`. Existing sensors receive `kai/sensors/<device_id>` as an initial endpoint. Review these generated paths and make the Node-RED paths match them, or edit each sensor in Sensor Settings.

Legacy broker tables and four global widget bindings are preserved for compatibility but are not used when per-sensor endpoints are configured.

## Acceptance criteria

- Node-RED alone holds MQTT credentials and subscriptions.
- Each physical sensor has a unique WebSocket endpoint.
- Every endpoint carries all normalized metrics for one `device_id`.
- A mismatched endpoint/device envelope is rejected before persistence.
- Stopping the desktop does not interrupt Node-RED MQTT processing.
- One sensor endpoint may reconnect without stopping other sensor streams.
- Location and sensor pages retain the same chart interaction model.

## Profile-based routing

Settings schema v4 retains existing NemoSense endpoints and adds per-metric
routes for BeanDevice Periodic and Custom profiles. BeanDevice Streaming uses a shared route. Existing BeanDevice split routes load as Periodic. No change to existing NemoSense
Node-RED routes is required. See the [Node-RED setup](../nodered/README.md#configure-beandevice-and-custom-streams)
for routing new devices.
