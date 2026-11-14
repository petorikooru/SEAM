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

- `sensorProfiles()` returns the supported profiles and their required metric names.
- `saveProfileSensor(name, description, device_id, location_name, profile, streams, acquisition)`
- `updateProfileSensor(name, device_id, profile, streams, latitude, longitude, acquisition)`
- `getSensorData(name)` includes `profile` and `streams`. Each stream has `metric`, `path`, and `connected`. Shared streams use an empty `metric`. The snapshot provides `acquisition` and `profile_metrics` for the BeanDevice controls and charts.
- standard location, metadata, GNSS, deletion, chart, history, and export methods remain available

Legacy global widget-binding methods remain callable for database compatibility but are no longer presented in the current Node-RED page.
