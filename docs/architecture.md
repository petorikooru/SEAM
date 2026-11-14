# Architecture

## Boundary

Node-RED owns MQTT and Sparkplug B. The desktop owns sensor catalogue data, WebSocket clients, validation, persistence, historical queries, and presentation.

## Data flow

```text
MQTT broker
   │ spBv1.0/# binary payloads
   ▼
Node-RED MQTT In
   ▼
KAI Sparkplug B decoder
   ├─ topic and message-type validation
   ├─ protobuf decoding
   ├─ NBIRTH/DBIRTH alias maps
   ├─ NDEATH/DDEATH state
   ├─ sequence validation
   └─ dataset expansion
   ▼ kai.telemetry.v1
Route by device_id
   ├─ NEMOSENSE-01 → /kai/sensors/nemosense-01
   ├─ NEMOSENSE-02 → /kai/sensors/nemosense-02
   └─ another device → another unique path
   ▼
Desktop WebSocket clients
   ├─ endpoint/device_id consistency check
   ├─ canonical JSON validation
   ├─ bounded SQLite writer
   └─ committed telemetry → charts, indicators, GNSS, history, export
```

## Sensor profiles and stream bindings

Settings schema v4 stores the sensor profile and adds `sensor_metric_endpoints` for BeanDevice and Custom paths. NemoSense retains its existing `sensors.websocket_endpoint` for all its metrics. BeanDevice Periodic and Custom bind one canonical metric per path. BeanDevice Streaming stores its shared path on the sensor record and accepts the selected profile’s metrics on that path.

The desktop checks each batch against its endpoint's configured device and optional metric before queuing it. Chart and indicator routing still uses `metric_name`. A sensor can report partial connectivity if only some of its paths are connected.

Existing sensor records, legacy bindings, and telemetry history are preserved when upgrading. Node-RED handles normalization for each hardware vendor and routes the resulting payloads to the configured paths.

## Failure behaviour

- Disconnected sensor endpoints reconnect every three seconds.
- Other connected sensors continue operating when one endpoint is unavailable.
- Malformed JSON or endpoint/device mismatch is not persisted.
- Historical data remains available during Node-RED or MQTT outages.
- A bounded writer queue prevents unbounded memory growth.
