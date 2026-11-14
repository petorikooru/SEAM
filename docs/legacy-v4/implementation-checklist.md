# Implementation checklist

Completed:

- Existing QML inspected and integrated through its stable contract.
- Existing backend and Sparkplug behavior inspected as reference material.
- Desktop/daemon process split.
- QProcess lifecycle controls and independent daemon CLI.
- QLocalServer/QLocalSocket versioned IPC.
- Duplicate daemon lock and stale detection.
- SQLite settings migrations.
- Separate WAL telemetry database, typed values, batching, retention, integrity check, pagination, and downsampling.
- Standard JSON MQTT parsing.
- Sparkplug protobuf decoding, topic validation, lifecycle, aliases, sequences, datasets, and NemoSense compatibility.
- Bounded queues and observable drop counters.
- Existing QML sensor/location/chart/export workflows retained.
- Strict type-checker and linter configuration.
- Unit and integration test scaffolding.
- Architecture, migration, lifecycle, IPC, Sparkplug, storage, MQTT, and QML documentation.

Explicitly deferred:

- Complete Sparkplug Template and PropertySet normalization.
- Automatic NCMD rebirth publication and command-specific QML forms.
- Production InfluxDB adapter implementation.
- OS credential-store provider; environment references are complete and dependency-free.
- Live migration of active databases to a different folder; use `KAI_BRIDGE_DATA_DIR` before startup.
- Full QML migration from the compatibility facade to dedicated controllers/models.
