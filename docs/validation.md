# Validation procedure and current result

Run from the project root:

```bash
python -m compileall -q src tests main.py
pytest -q
node --check nodered/node-red-contrib-kai-sparkplug/nodes/kai-sparkplug-decode.js
python -m json.tool nodered/flows/spbv1.0-kai-bridge.json > /dev/null
```

## Source-package result

- Python compilation: passed.
- Project JSON validation: passed.
- Node-RED decoder JavaScript syntax: passed.
- QML static delimiter/import scan: passed.
- Test suite: **40 passed, 4 skipped**.

The skipped tests require PySide6/Qt runtime modules or a generated build mirror unavailable in the validation environment. A live Node-RED, MQTT broker, and field-device smoke test remains required before production deployment.

## Integration smoke test

1. Configure a reachable MQTT broker.
2. Publish NBIRTH/DBIRTH followed by NDATA/DDATA.
3. Confirm each configured `device_id` reaches only its dedicated WebSocket.
4. Confirm unmatched devices appear in the Node-RED Debug sidebar.
5. Register matching sensor mappings in the desktop.
6. Verify per-sensor connection status, charts, indicators, GNSS, persistence, reconnection, and CSV export.
7. Deliberately route one device to another sensor endpoint and confirm the desktop rejects it.
