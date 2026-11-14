# KAI Node-RED multi-sensor installation

## 1. Install the Sparkplug decoder node

Stop Node-RED and install the included package into the Node-RED user directory.

Linux/macOS:

```bash
cd ~/.node-red
npm install /absolute/path/to/project/nodered/node-red-contrib-kai-sparkplug
```

Windows PowerShell:

```powershell
cd $env:USERPROFILE\.node-red
npm install C:\absolute\path\to\project\nodered\node-red-contrib-kai-sparkplug
```

Restart Node-RED. The palette should contain **Sparkplug B decode**.

## 2. Import and configure the flow

1. Open **Menu → Import**.
2. Import `nodered/flows/spbv1.0-kai-bridge.json` into a new tab.
3. Open **KAI Sparkplug Broker**.
4. Enter the actual broker host, port, credentials, and TLS settings.
5. Confirm the MQTT In node subscribes to `spBv1.0/#` and outputs a **Buffer**.
6. Deploy.

`127.0.0.1` refers to the host or container running Node-RED. Do not use it for a broker running on another machine or in another container unless networking explicitly maps that address.

## 3. Configure multiple sensors

The flow includes two examples:

| Switch `device_id` | WebSocket path |
|---|---|
| `NEMOSENSE-01` | `/kai/sensors/nemosense-01` |
| `NEMOSENSE-02` | `/kai/sensors/nemosense-02` |

To add another sensor:

1. Open **Route by device_id**.
2. Add an equality rule for the exact canonical `device_id`.
3. Add a new output to the switch node.
4. Add a **WebSocket Out** node with a unique listener path such as `/kai/sensors/nemosense-03`.
5. Connect the new switch output to that WebSocket Out node.
6. Deploy.
7. Add the sensor in the desktop with the same `device_id` and WebSocket path.

Each endpoint carries the complete canonical envelope for one sensor. Do not split accelerometer, inclinometer, location, and indicator metrics into separate endpoints.

## 4. Verify each endpoint

Browser console example:

```javascript
const ws = new WebSocket("ws://127.0.0.1:1880/kai/sensors/nemosense-01");
ws.onmessage = event => console.log(JSON.parse(event.data));
ws.onerror = event => console.error(event);
```

Expected envelope fields include:

```text
schema = kai.telemetry.v1
device_id = NEMOSENSE-01
points = [...]
```

## 5. Unmatched devices

Messages whose `device_id` has no switch rule are sent to **Unmatched device_id** in the Node-RED Debug sidebar. Add a route only after confirming the exact case-sensitive `device_id` emitted by the decoder.

## Security

- Keep MQTT credentials only in Node-RED credential storage.
- Use TLS for MQTT where supported.
- Use `wss` behind an authenticated reverse proxy for non-local WebSocket access.
- Restrict Node-RED editor and WebSocket access to trusted networks.
