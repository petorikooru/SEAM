# MQTT payloads

## Standard JSON

Objects or arrays of objects are accepted. `device_id`, `timestamp`, `timestamp_ns`, `unit`, `quality`, and `tags` are metadata. Every remaining scalar leaf becomes a telemetry point. Nested keys use `/`.

Timestamp inputs may be nanoseconds, Unix seconds/milliseconds, or ISO-8601 text. Naive ISO timestamps are interpreted as UTC. Non-finite numbers, invalid UTF-8, unsupported objects, invalid identifiers, and payloads above 2 MiB are rejected.

## Sparkplug B

Topics beginning with the configured namespace route to the protobuf parser. See `sparkplug-b.md`.

## Backpressure

MQTT callbacks perform a short queue put. When the bounded processing queue is full, the new message is dropped and the counter is incremented. The database writer also has a bounded queue and defaults to dropping the newest submitted batch after a short wait. Loss is never silent: counters are available through `get_ingestion_statistics`.
