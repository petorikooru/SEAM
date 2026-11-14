# Backend migration

## Supplied reference backend

The supplied project used a flat package, one large `BackendController`, YAML configuration, plaintext-equivalent password handling, direct GUI-process MQTT clients, a parser multiprocessing/thread mode, two overlapping telemetry implementations, and direct coupling between MQTT parsing, QML signals, charts, and SQLite.

The reference code nevertheless contained valuable domain behavior: the existing QML method/signal contract, Sparkplug topic expectations, bundled Tahu protobuf classes, NemoSense aliases 1–5 and 16–18, accelerometer dataset timestamp conventions, selected VAR/DOUBLE fields, battery/RSSI naming, and chart/export expectations.

## Retained behavior

- Existing QML pages, visual design, navigation, dialogs, and backend method names.
- Sparkplug namespace and topic semantics.
- Bundled protobuf definition.
- NemoSense alias compatibility and accelerometer burst interpretation.
- Existing display metric names such as `ACC/X`, `ACC/TEMPERATURE`, `BATTERY`, and `CELLULAR_RSSI`.
- Sensor/location workflows and chart series registration.

## Reimplemented

- YAML configuration became migrated SQLite settings.
- MQTT clients moved to the independent daemon.
- Parser multiprocessing became a bounded processing thread with explicit ownership.
- Telemetry persistence became one typed repository and one bounded writer.
- Local IPC, lifecycle state machine, daemon CLI, duplicate-instance lock, structured status, and statistics were added.
- Sparkplug topics, aliases, sequence state, and payload decoding were separated into dedicated modules.
- Secrets became environment references rather than stored values.
- QML daemon controls and offline/error visibility were added.

## Removed

- Global/implicit service ownership in the GUI.
- YAML and PyYAML dependency.
- Base64 password obfuscation.
- Direct MQTT callbacks into QML and SQLite.
- Duplicate legacy telemetry tables and unbounded write queues.
- Parser child processes without profiling evidence.

## Compatibility risks

Sensor device IDs inferred by the legacy application may differ when the topic contains wildcards. The migration uses the explicit Sparkplug device level when available and otherwise a stable sensor-name slug. Existing deployments should verify each saved sensor's device ID.

The old backend accepted a literal password. The new backend treats input as an environment reference and never stores the literal secret. Operators must configure the referenced variable.

The custom data-folder UI saves the requested path, but moving active databases is intentionally not performed while processes may own them. Set `KAI_BRIDGE_DATA_DIR` before the next start.
