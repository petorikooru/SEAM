# Node-RED to desktop contract

## Transport

Each configured stream has a unique WebSocket listener path:

```text
ws://<node-red-host>:<port>/<sensor-endpoint>
```

Example:

```text
ws://127.0.0.1:1880/kai/sensors/nemosense-01
```

The desktop stores the endpoint without leading or trailing slashes. `https` or `wss` in the configured Node-RED address selects `wss`.

## Binding invariant

For each sensor, these values must match across Node-RED and the desktop:

- the exact case-sensitive `device_id`
- the configured WebSocket path
- for BeanDevice Periodic and Custom, the exact case-sensitive `metric_name` assigned to the path
- for BeanDevice Streaming, the selected profile’s allowed metric set

A NemoSense endpoint can carry all metrics for its device. Each BeanDevice Periodic or Custom endpoint carries only its assigned metric. A BeanDevice Streaming endpoint may carry a mixed batch of acceleration and inclination metrics for its device. Paths are exclusive across all profiles. A wrong device or metric causes the entire batch to be rejected. The desktop rejects a batch when the endpoint is assigned to `NEMOSENSE-01` but the envelope contains another `device_id`.

## Schema

Every message must be a JSON object, or an array of objects, using `schema: "kai.telemetry.v1"`.

### Points form

```json
{
  "schema": "kai.telemetry.v1",
  "device_id": "NEMOSENSE-01",
  "source_topic": "spBv1.0/group/DDATA/node/NEMOSENSE-01",
  "group_id": "group",
  "edge_node_id": "node",
  "sparkplug_device_id": "NEMOSENSE-01",
  "sequence": 17,
  "points": [
    {
      "metric_name": "ACC/X",
      "value": 0.018,
      "timestamp_ns": "1785146400123000000",
      "quality": "good",
      "alias": 16
    }
  ]
}
```

### Metrics form

```json
{
  "schema": "kai.telemetry.v1",
  "device_id": "NEMOSENSE-01",
  "timestamp_ns": "1785146400123000000",
  "metrics": {
    "BATTERY": 91.4,
    "CELLULAR_RSSI": -68
  },
  "units": {
    "BATTERY": "%",
    "CELLULAR_RSSI": "dBm"
  },
  "quality": "good"
}
```

## Validation

- Maximum message size: 4 MiB.
- UTF-8 and JSON must be valid.
- `schema` must equal `kai.telemetry.v1`.
- `device_id` and `metric_name` allow letters, digits, dot, underscore, colon, slash, and dash.
- Values must be JSON scalars.
- Non-finite floating-point values are rejected.
- `timestamp_ns` must be positive; use a decimal string to preserve nanosecond precision in JavaScript.

## Versioning

An incompatible change requires a new schema identifier such as `kai.telemetry.v2`. Additive optional fields do not require a new identifier.
