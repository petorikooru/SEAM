# Architecture

## Boundary

Node-RED owns MQTT and Sparkplug B. The desktop owns sensor catalogue data, per-sensor WebSocket clients, validation, persistence, historical queries, and presentation.

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
Desktop per-sensor WebSocket clients
   ├─ endpoint/device_id consistency check
   ├─ canonical JSON validation
   ├─ bounded SQLite writer
   └─ committed telemetry → charts, indicators, GNSS, history, export
```

## Per-sensor binding model

`settings.db` schema version 3 adds `sensors.websocket_endpoint`. A sensor record contains:

- friendly application name
- exact canonical `device_id`
- unique WebSocket endpoint
- location and GNSS metadata

The desktop opens the unique set of sensor endpoints. For a configured endpoint, every incoming point must contain that endpoint's assigned `device_id`; otherwise the batch is rejected.

Legacy `node_red_bindings` remains in the database only for migration compatibility and is not used by the v5.2 runtime.

## Simplification

One sensor now uses one WebSocket endpoint for all metrics. Widget routing is no longer represented in transport configuration. The existing chart and indicator layers select values by `metric_name`, reducing the flow from four widget channels to one channel per physical sensor.

## Failure behaviour

- Disconnected sensor endpoints reconnect every three seconds.
- Other connected sensors continue operating when one endpoint is unavailable.
- Malformed JSON or endpoint/device mismatch is not persisted.
- Historical data remains available during Node-RED or MQTT outages.
- A bounded writer queue prevents unbounded memory growth.
