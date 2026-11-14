from __future__ import annotations

import json
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
FLOW_PATH = PROJECT_ROOT / "nodered" / "flows" / "flows.json"


def test_adapted_flow_uses_canonical_decoder_and_dedicated_route() -> None:
    nodes = json.loads(FLOW_PATH.read_text(encoding="utf-8"))
    mqtt = next(node for node in nodes if node.get("type") == "mqtt in")
    assert mqtt["topic"] == "spBv1.0/#"
    assert mqtt["datatype"] == "buffer"

    decoder = next(node for node in nodes if node.get("type") == "kai-sparkplug-decode")
    assert decoder["namespace"] == "spBv1.0"

    route = next(node for node in nodes if node.get("type") == "switch")
    assert route["property"] == "device_id"
    assert route["rules"][0]["v"] == "DA25009046"

    listener = next(node for node in nodes if node.get("type") == "websocket-listener")
    assert listener["path"] == "/kai/sensors/Nemosense-1"
