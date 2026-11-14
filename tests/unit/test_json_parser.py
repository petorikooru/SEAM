from __future__ import annotations

import json

import pytest

from kai_bridge_inspection.domain.errors import TelemetryParseError
from kai_bridge_inspection.domain.models import IncomingMqttMessage, MqttMessageMetadata
from kai_bridge_inspection.mqtt.payload_parser import JsonTelemetryParser


def message(payload: object) -> IncomingMqttMessage:
    return IncomingMqttMessage(
        MqttMessageMetadata("plant/sensor-001", 1, False, 1_700_000_000_000_000_000, 7),
        json.dumps(payload).encode(),
    )


def test_json_parser_normalizes_scalar_fields() -> None:
    points = JsonTelemetryParser().parse(
        message(
            {
                "device_id": "sensor-001",
                "timestamp": "2026-07-19T10:30:00Z",
                "temperature": 24.7,
                "status": True,
                "electrical": {"voltage": 12.4},
            }
        )
    )
    assert {point.metric_name for point in points} == {
        "temperature",
        "status",
        "electrical/voltage",
    }
    assert all(point.device_id == "sensor-001" for point in points)


def test_json_parser_rejects_non_finite() -> None:
    raw = b'{"device_id":"sensor-001","temperature":NaN}'
    with pytest.raises(TelemetryParseError):
        JsonTelemetryParser().parse(
            IncomingMqttMessage(
                MqttMessageMetadata("plant/sensor-001", 0, False, 1, 1), raw
            )
        )
