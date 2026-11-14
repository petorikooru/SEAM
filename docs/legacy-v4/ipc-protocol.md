# IPC protocol

Endpoint: `kai-bridge-inspection-telemetry-v1`, restricted to the current user where Qt supports `UserAccessOption`.

Framing is UTF-8 JSON Lines. Each message is one JSON object followed by `\n`. The maximum encoded message and receive buffer are 4 MiB. Partial reads are buffered.

Request:

```json
{"protocol_version":1,"request_id":"...","command":"get_status","payload":{}}
```

Success:

```json
{"protocol_version":1,"request_id":"...","ok":true,"result":{},"error":null}
```

Error:

```json
{"protocol_version":1,"request_id":"...","ok":false,"result":null,"error":{"code":"invalid_request","message":"..."}}
```

Event:

```json
{"protocol_version":1,"event":"telemetry_batch","payload":{"points":[]}}
```

Commands: `ping`, `get_status`, `start_collection`, `stop_collection`, `reload_settings`, `get_devices`, `get_latest_values`, `query_telemetry`, `get_ingestion_statistics`, `get_sparkplug_state`, and `shutdown`.

Requests have IDs and the desktop applies a five-second timeout. Commands are allow-listed; no arbitrary method execution exists. Protocol changes that break compatibility require a new `protocol_version` and endpoint name.
