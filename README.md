# SEAM

SEAM (Structure Evaluation and Acquisition Monitoring) is a PySide6/QML desktop dashboard whose telemetry boundary is Node-RED. Node-RED owns MQTT connectivity and Sparkplug B processing. The desktop receives validated `kai.telemetry.v1` JSON over WebSocket endpoints configured by sensor profile.

## Runtime architecture

```text
Sparkplug B devices
        │ MQTT spBv1.0/#
        ▼
Node-RED
  MQTT In → KAI Sparkplug decoder → route by device_id
                                         ├─ /kai/sensors/nemosense-01
                                         ├─ /kai/sensors/nemosense-02
                                         └─ /kai/sensors/<another-sensor>
        ▼
Desktop application
  profile-based WebSockets → JSON validation → SQLite → widgets/charts
```

NemoSense uses one WebSocket for all metrics. BeanDevice Streaming uses one shared path for the selected channels. BeanDevice Periodic and Custom use separate paths for individual metrics. The application routes telemetry by `metric_name`.

The desktop does not create an MQTT client, subscribe to MQTT topics, decode protobuf, or manage Sparkplug aliases/session state.

## Requirements

- Python 3.12 or newer
- PySide6 6.8 or newer, installed through the project
- Node.js and Node-RED 3.x or newer
- An MQTT broker reachable from the Node-RED runtime

## Desktop installation

```bash
python -m venv .venv
```

Windows PowerShell:

```powershell
.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -e .
python -m kai_bridge_inspection
```

Linux/macOS:

```bash
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -e .
python -m kai_bridge_inspection
```

## Node-RED installation

The supplied assets are:

- Flow: `nodered/flows/spbv1.0-kai-bridge.json`
- Decoder package source: `nodered/node-red-contrib-kai-sparkplug/`
- Detailed guide: `nodered/README.md`

Install the decoder in the Node-RED user directory, restart Node-RED, import the flow, and configure **KAI Sparkplug Broker**.

## Sensor configuration

Open **Add Sensor**, select a sensor card, and fill in the form. For BeanDevice, select both the channel group and acquisition mode. **Sensor Settings** can edit existing mappings.

| Profile | WebSocket paths |
|---|---|
| NemoSense | One path for all metrics, for example `kai/sensors/nemosense-01` |
| BeanDevice Accelerometer (Periodic) | One each for `ACC/X`, `ACC/Y`, and `ACC/Z` |
| BeanDevice Inclinometer (Periodic) | One each for `ACC/ROLL` and `ACC/PITCH` |
| BeanDevice Combo (Periodic) | Five paths covering both sets of metrics |
| BeanDevice Streaming (all channel selections) | One shared path, suggested as `<MAC-ID>/STREAMING` |
| Custom | One path for each metric name you add |

For either BeanDevice acquisition mode, use **Add auxiliary metric** in Add Sensor or Sensor Settings to give temperature, RSSI, battery, or another auxiliary metric its own path. Each path carries only its configured metric for the same sensor device ID.

Use the same case-sensitive `device_id` in the desktop and in Node-RED. Each path must be unique. The desktop trims leading and trailing slashes when storing paths and rejects an entire batch if the device or assigned metric does not match.

On startup, settings database schema v4 adds profiles and metric-specific routes. Existing sensors keep their IDs and paths under the NemoSense profile. The telemetry database uses the existing schema. Back up the database files before upgrading if you need to roll back to a build that only supports settings schema v3.

See [Node-RED setup](nodered/README.md#configure-beandevice-and-custom-streams) for normalization and routing.

## Route custom device metrics with Node-RED

In **Add Sensor → Custom**, enter the device ID and add one row per metric.
For example, use device ID `CUSTOM-01` with these mappings:
| Metric name | SEAM path | Node-RED WebSocket listener |
|---|---|---|
| `TEMPERATURE` | `kai/custom/custom-01/temperature` | `/kai/custom/custom-01/temperature` |
| `BATTERY` | `kai/custom/custom-01/battery` | `/kai/custom/custom-01/battery` |
| `CELLULAR_RSSI` | `kai/custom/custom-01/rssi` | `/kai/custom/custom-01/rssi` |
| `SIGNAL_STRENGTH_LABEL` | `kai/custom/custom-01/signal-label` | `/kai/custom/custom-01/signal-label` |
| `INFERRED_SAMPLE_RATE` | `kai/custom/custom-01/sample-rate` | `/kai/custom/custom-01/sample-rate` |
| `BAT_CHARGER_STATUS_LABEL` | `kai/custom/custom-01/charger-status` | `/kai/custom/custom-01/charger-status` |
| `POWER_SOURCE_LABEL` | `kai/custom/custom-01/power-source` | `/kai/custom/custom-01/power-source` |
| `MQTT_DEVICE_STATUS` | `kai/custom/custom-01/mqtt-status` | `/kai/custom/custom-01/mqtt-status` |
| `NTP_STATUS` | `kai/custom/custom-01/ntp-status` | `/kai/custom/custom-01/ntp-status` |
| `ACC_LOST_SAMPLES_COUNT` | `kai/custom/custom-01/lost-samples` | `/kai/custom/custom-01/lost-samples` |
| `DATA_LATENCY_SECONDS` | `kai/custom/custom-01/latency` | `/kai/custom/custom-01/latency` |
| `ACC/X` | `kai/custom/custom-01/acc-x` | `/kai/custom/custom-01/acc-x` |
| `ACC/Y` | `kai/custom/custom-01/acc-y` | `/kai/custom/custom-01/acc-y` |
| `ACC/Z` | `kai/custom/custom-01/acc-z` | `/kai/custom/custom-01/acc-z` |
| `ACC/ROLL` | `kai/custom/custom-01/roll` | `/kai/custom/custom-01/roll` |
| `ACC/PITCH` | `kai/custom/custom-01/pitch` | `/kai/custom/custom-01/pitch` |

Use only the rows your device supplies. The Function example below wires
temperature and battery. For each additional metric, configure a matching
output and listener, and send the exact case-sensitive metric name and
device ID. Custom profiles also accept other metric names allowed by the
[telemetry contract](docs/nodered-contract.md). Those metrics are available
in Historical Graph.
In Node-RED, connect your device decoder to a **Function** node with two
outputs. The decoder should place the sample timestamp in
`msg.payload.timestamp_ns` as a decimal string of UTC nanoseconds, the
temperature in `msg.payload.temperature` in °C, and the battery level in
`msg.payload.battery` as a percentage. Paste this into the Function node:

```javascript
const { timestamp_ns, temperature, battery } = msg.payload;
if (typeof timestamp_ns !== "string" || !/^[1-9][0-9]*$/.test(timestamp_ns)) {
    node.error("Expected a positive UTC nanosecond timestamp string", msg);
    return null;
}

function point(metric_name, value, unit) {
    if (!Number.isFinite(value)) return null;
    return {
        payload: JSON.stringify({
            schema: "kai.telemetry.v1",
            device_id: "CUSTOM-01",
            points: [{ metric_name, value, unit, timestamp_ns }]
        })
    };
}

return [point("TEMPERATURE", temperature, "°C"), point("BATTERY", battery, "%")];
```

Wire output 1 to a **WebSocket Out** node listening on the temperature
path and output 2 to another listening on the battery path. Configure both
nodes to send the payload only, then deploy. Set the Node-RED host and port
on the SEAM **Node-RED** page. SEAM automatically connects to the saved paths
and Node-RED routes each new sample to its configured listener. To add another
metric, add a Function output, a WebSocket listener, and a matching SEAM row.

## MQTT connection error

This status:

```text
Connection failed to broker: nodered-kai-bridge@mqtt://127.0.0.1:1883
```

means Node-RED cannot reach an MQTT broker at its own loopback address. `127.0.0.1` is valid only when the broker runs on the same machine and, for containers, the same network namespace as Node-RED. Otherwise edit the broker node and use the broker's LAN address, DNS name, or container service name. See `docs/mqtt-broker-troubleshooting.md`.

## Canonical JSON

```json
{
  "schema": "kai.telemetry.v1",
  "device_id": "NEMOSENSE-01",
  "source_topic": "spBv1.0/group/DDATA/node/NEMOSENSE-01",
  "points": [
    {
      "metric_name": "ACC/X",
      "value": 0.018,
      "timestamp_ns": "1785146400123000000",
      "quality": "good"
    }
  ]
}
```

See `docs/nodered-contract.md` for the complete contract.

## Validation

```bash
python -m compileall -q src tests main.py
pytest -q
node --check nodered/node-red-contrib-kai-sparkplug/nodes/kai-sparkplug-decode.js
python -m json.tool nodered/flows/spbv1.0-kai-bridge.json > /dev/null
```

## Documentation

- `docs/architecture.md`
- `docs/nodered-migration.md`
- `docs/nodered-contract.md`
- `docs/mqtt-broker-troubleshooting.md`
- `docs/sparkplug-b.md`
- `nodered/README.md`
