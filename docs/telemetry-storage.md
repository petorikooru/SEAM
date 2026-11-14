# Telemetry storage

`telemetry.db` stores only normalized `kai.telemetry.v1` points received from Node-RED. The desktop never stores raw MQTT packets or Sparkplug protobuf payloads.

SQLite runs in WAL mode with `synchronous=NORMAL`, a busy timeout, explicit batch transactions, and operation-scoped connections. The `telemetry_points` table preserves source and receive timestamps in UTC nanoseconds, device and metric identity, typed scalar values, units, quality, JSON tags, source-topic metadata, and Sparkplug identity fields retained by the canonical Node-RED envelope.

The active write path is:

```text
Node-RED WebSocket → JSON validation → bounded TelemetryBatchWriter → telemetry.db
```

The writer batches up to 1,000 points or approximately 350 ms. A bounded queue prevents unbounded memory growth; under sustained overload, the newest incoming batch is rejected and the desktop surfaces an error. QML receives a batch only after the SQLite transaction succeeds.

Primary indexes support device/metric history, retention ranges, source-topic diagnostics, protocol filtering, and Sparkplug entity lookup. Historical queries are parameterized, paginated, capped, and downsampled before chart rendering.

Retention deletes points older than the configured period and performs a passive WAL checkpoint. For a consistent backup, use SQLite's online backup mechanism or close the desktop application first; copying only the main database file while WAL is active may omit recent committed data.

InfluxDB remains an optional future backend for sustained high event rates, remote multi-client access, long retention, or server-side aggregation. The v5 application requires only local SQLite.
