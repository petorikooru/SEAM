# Sparkplug B processing in Node-RED

## Namespace and topics

The supplied decoder defaults to `spBv1.0` and accepts:

```text
spBv1.0/<group-id>/<message-type>/<edge-node-id>[/<device-id>]
spBv1.0/STATE/<host-id>
```

Recognized telemetry message types are NBIRTH, NDEATH, DBIRTH, DDEATH, NDATA, and DDATA. NCMD and DCMD are valid but intentionally excluded from telemetry persistence.

## State handling

- NBIRTH starts a new edge-node session and clears node/device alias maps for that edge node; DBIRTH resets the corresponding device alias map.
- Named metrics with aliases populate the map.
- Alias-only data metrics resolve from the current map.
- Known NemoSense aliases are available as a late-subscriber fallback.
- NDEATH and DDEATH emit `ONLINE = false`; birth messages emit `ONLINE = true`.
- Sequence numbers are tracked per group/edge-node session and checked modulo 256. NBIRTH resets the sequence baseline; a discontinuity emits `SPARKPLUG_SEQUENCE_VALID = false`.

Compatibility aliases:

| Alias | Metric |
|---:|---|
| 1 | `ACC/TEMPERATURE` |
| 2 | `ACC/ROLL` |
| 3 | `ACC/PITCH` |
| 4 | `VAR/DOUBLE` |
| 5 | `VAR/STRING` |
| 16 | `ACC/X` |
| 17 | `ACC/Y` |
| 18 | `ACC/Z` |

## Dataset normalization

- `ACC/X`, `ACC/Y`, and `ACC/Z`: each row begins with a microsecond timestamp followed by samples. Sample interval is inferred from adjacent rows, with a 250 Hz fallback.
- `ACC/PITCH`, `ACC/ROLL`, and `ACC/TEMPERATURE`: row value and optional row timestamp are converted to scalar points.
- `VAR/DOUBLE` and `VAR/STRING`: each non-timestamp column becomes a metric. `BAT_FUEL_GAUGE_REPSOC` maps to `BATTERY`; `SIGNAL` and `RSSI` map to `CELLULAR_RSSI`.
- Other datasets use `<metric>/<column>` names and retain the dataset row index in tags.

## Implementation asset

The Node-RED custom node is `kai-sparkplug-decode`. It uses the bundled official-schema-compatible `sparkplug_b.proto` and `protobufjs`. MQTT In must provide a binary Buffer.

## Current limits

Template expansion, PropertySet normalization, and automated rebirth command publication are not implemented. Unknown aliases not covered by a received birth message or compatibility fallback are skipped rather than mislabelled.
