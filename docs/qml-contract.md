# QML contract

Compatibility names containing `daemon` or `mqtt` now describe Node-RED WebSocket stream state; the desktop does not start an MQTT client or telemetry daemon.

## `daemonController`

Properties include `state`, `running`, `collectionEnabled`, `lastError`, `connectedEndpointCount`, and compatibility property `mqttConnected` meaning at least one Node-RED WebSocket is connected.

Relevant slots:

- `startCollection()`
- `pauseCollection()`
- `resumeCollection()`
- `reloadSettings()`
- `refreshStatus()`
- `isEndpointConnected(endpoint)`

## `backend`

Node-RED service configuration:

- `nodeRedAddress`
- `nodeRedPort`
- `saveNodeRedConfig(address, port)`

Sensor catalogue:

- `saveNewNodeRedSensor(name, description, device_id, websocket_endpoint, location_name)`
- `updateNodeRedSensorSettings(name, device_id, websocket_endpoint, latitude, longitude)`
- `getSensorData(name)` includes `websocket_endpoint` and per-endpoint stream health
- standard location, metadata, GNSS, deletion, chart, history, and export methods remain available

Legacy global widget-binding methods remain callable for database compatibility but are no longer presented in the current Node-RED page.
