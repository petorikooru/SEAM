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

A NemoSense endpoint carries the complete canonical envelope for that device.

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

## Configure BeanDevice and Custom streams

The supplied Sparkplug flow covers the NemoSense pipeline. For BeanDevice and
Custom devices, use an input and decoder in Node-RED that match the firmware or
gateway configuration. Inspect an actual device payload to identify the vendor's
channels, time base, and units before mapping them.

1. Normalize each measurement to a `kai.telemetry.v1` point. Preserve the sample
   timestamp as a decimal string in UTC nanoseconds. Match the configured desktop
   `device_id` exactly.
2. For BeanDevice, normalize acceleration in g to `ACC/X`, `ACC/Y`, and `ACC/Z`.
   Normalize tilt in degrees to `ACC/ROLL` and `ACC/PITCH` using the sensor's
   mounting orientation to determine the corresponding channel and sign.
3. Match the sensor's acquisition mode when routing the normalized points.
   - **Periodic (LDCDA)** uses a separate topic per channel. The BeanAir
     manual shows `<MAC-ID>/SENSOR/0`, and the protocol specifies the X-INC
     channel IDs 0 = Z, 1 = X, 2 = Y, 3 = INC_X, and 4 = INC_Y. SEAM
     suggests corresponding WebSocket paths with the same suffixes and
     maps channels 3 and 4 to roll and pitch respectively. Adjust the
     mapping for the actual mounting orientation and signs.
   - **Streaming** uses one dynamic MQTT topic, typically
     `<MAC-ID>/STREAMING`. The streaming frame packs samples for the
     enabled channels. Decode and normalize them in Node-RED, then send
     all selected channels through a single WebSocket Listener/Out at
     `/<MAC-ID>/STREAMING` or the matching override entered in SEAM.
     A Combo batch may contain acceleration and tilt points together.
   - **Auxiliary metrics** in either BeanDevice mode use one dedicated
     WebSocket path per metric. For example, route `ACC/TEMPERATURE` to
     `/<MAC-ID>/temperature` and `CELLULAR_RSSI` to `/<MAC-ID>/rssi`. Configure
     the same metric names and paths through **Add auxiliary metric** in SEAM.
     Keep the BeanDevice's configured `device_id` in these envelopes.
   - **Custom** routes one configured metric per WebSocket path.
4. Keep the exact device ID and metric spelling when publishing. The device's
   MQTT topic is configurable in BeanScape. SEAM's suggested paths are editable.
   The desktop acquisition selector configures routing and validation. Set the
   actual device acquisition mode separately in BeanScape.

Example normalized Combo streaming message for `/F4B85E00A14B0000/STREAMING`:

```json
{
  "schema": "kai.telemetry.v1",
  "device_id": "F4B85E00A14B0000",
  "points": [
    {"metric_name": "ACC/X", "value": 0.018, "unit": "g", "timestamp_ns": "1785146400123000000"},
    {"metric_name": "ACC/PITCH", "value": -0.24, "unit": "deg", "timestamp_ns": "1785146400123000000"}
  ]
}
```

BeanAir's dynamic topic can also carry event-triggered and shock frames.
Filter for the intended acquisition frame in the Node-RED decoder.
The desktop expects canonical JSON from Node-RED. The bundled Sparkplug
flow and decoder do not decode BeanAir's binary MQTT frames.

- [BeanDevice Wilow User Manual, sections 9.7–9.8](https://www.wireless-iot.beanair.com/files/UM-RF-07-ENG-Wilow-Wifi-Sensor.pdf)
- [BeanAir MQTT Communication Protocol, sections 7–8](https://www.wireless-iot.beanair.com/files/TN-RF-004-MQTT-Comnmunication-Protocol.pdf)

Picker photographs are from the [Dewesoft NemoSense product page](https://dewesoft.com/products/nemosense)
and [BeanAir WiLow X-INC datasheet](https://www.wireless-iot-sensors.beanair.com/files/Datasheet-wifi-accelerometer-and-inclinometer-sensors-beandevice-Wilow-X-Inc.pdf).

## Remote BeanDevice streaming configuration

Import `nodered/flows/beandevice-otac.json` alongside the telemetry flow.
In **Allowlisted DAQ OTAC**, add each device's 16-digit MAC ID, its actual
OTAC subscription topic from BeanScape, and the sample rates supported by
its model and firmware. The allowlist starts empty. In **Select BeanAir
broker**, select the broker the device uses and deploy the flow. Enable
OTAC subscription on the device in BeanScape if it is disabled.

Restrict access to the Node-RED HTTP endpoint to trusted SEAM operators
through your deployment firewall or authenticated gateway. Use HTTPS across
networks. Give the Node-RED broker account publish permission only on the
intended OTAC topics. Commands use QoS 0 and retain disabled.

In SEAM, save the sensor as **BeanDevice → Streaming** using the hardware
MAC as the device ID. Reopen **Sensor Settings → Remote streaming
configuration**, enter the rate, set logging and store-and-forward, and click
**Send streaming configuration**. This sends a complete continuous-streaming
DAQ configuration with transmission enabled. Store-and-forward uses the
vendor's 65535 rollover setting when enabled. It can replace existing burst
or one-shot settings. A queued response confirms only that Node-RED accepted
the request. Verify the reported sample rate and device settings separately.

The command frame follows BeanAir TN-RF-004 sections 7.1 and 7.3.1. The
command endpoint is separate from the telemetry WebSocket.
