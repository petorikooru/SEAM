from __future__ import annotations

import json
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
FLOW_PATH = PROJECT_ROOT / "nodered" / "flows" / "spbv1.0-kai-bridge.json"
DECODER_PATH = (
    PROJECT_ROOT
    / "nodered"
    / "node-red-contrib-kai-sparkplug"
    / "nodes"
    / "kai-sparkplug-decode.js"
)


def test_importable_flow_has_one_binary_sparkplug_input_and_per_sensor_outputs() -> None:
    nodes = json.loads(FLOW_PATH.read_text(encoding="utf-8"))
    mqtt_inputs = [node for node in nodes if node.get("type") == "mqtt in"]
    assert len(mqtt_inputs) == 1
    assert mqtt_inputs[0]["topic"] == "spBv1.0/#"
    assert mqtt_inputs[0]["datatype"] == "buffer"

    listeners = {
        node["path"]
        for node in nodes
        if node.get("type") == "websocket-listener"
    }
    assert listeners == {
        "/kai/sensors/nemosense-01",
        "/kai/sensors/nemosense-02",
    }

    switches = [node for node in nodes if node.get("type") == "switch"]
    assert len(switches) == 1
    assert switches[0]["property"] == "device_id"
    assert [rule.get("v") for rule in switches[0]["rules"][:2]] == [
        "NEMOSENSE-01",
        "NEMOSENSE-02",
    ]

    decoders = [node for node in nodes if node.get("type") == "kai-sparkplug-decode"]
    assert len(decoders) == 1
    assert decoders[0]["namespace"] == "spBv1.0"


def test_decoder_scopes_sequence_to_edge_node_and_resets_aliases_on_nbirth() -> None:
    source = DECODER_PATH.read_text(encoding="utf-8")
    assert "sequenceKeyOf(topic)" in source
    assert "topic.messageType === 'NBIRTH'" in source
    assert "clearEdgeAliases(node.aliases, topic)" in source
    assert "Unsupported Sparkplug message type" in source
