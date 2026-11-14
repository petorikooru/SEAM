from __future__ import annotations

import json

import pytest

from kai_bridge_inspection.domain.enums import ProtocolName
from kai_bridge_inspection.nodered.payload import NodeRedPayloadError, parse_node_red_payload


def test_parses_metrics_envelope() -> None:
    payload = json.dumps(
        {
            "schema": "kai.telemetry.v1",
            "device_id": "NEMO-01",
            "timestamp_ns": 1_700_000_000_000_000_000,
            "metrics": {"ACC/X": 0.25, "ACC/Y": -0.5},
        }
    )
    points = parse_node_red_payload(payload, "kai/accelerometer")
    assert [point.metric_name for point in points] == ["ACC/X", "ACC/Y"]
    assert all(point.device_id == "NEMO-01" for point in points)
    assert all(point.protocol == ProtocolName.NODE_RED for point in points)
    assert all(point.tags["node_red_endpoint"] == "kai/accelerometer" for point in points)


def test_parses_points_envelope_and_inherits_device_id() -> None:
    payload = json.dumps(
        {
            "schema": "kai.telemetry.v1",
            "device_id": "NEMO-02",
            "points": [
                {"metric_name": "GNSS_LAT", "value": -6.9, "timestamp_ns": 10},
                {"metric_name": "GNSS_LON", "value": 107.6, "timestamp_ns": 11},
            ],
        }
    )
    points = parse_node_red_payload(payload, "kai/location")
    assert [(point.metric_name, point.value) for point in points] == [
        ("GNSS_LAT", -6.9),
        ("GNSS_LON", 107.6),
    ]
    assert all(point.device_id == "NEMO-02" for point in points)


def test_rejects_non_scalar_metric() -> None:
    payload = json.dumps(
        {
            "schema": "kai.telemetry.v1",
            "device_id": "NEMO-03",
            "metrics": {"ACC/X": [1, 2, 3]},
        }
    )
    with pytest.raises(NodeRedPayloadError, match="JSON scalar"):
        parse_node_red_payload(payload, "kai/accelerometer")


def test_accepts_exact_nanosecond_timestamp_as_decimal_string() -> None:
    timestamp = "1785146400123000000"
    payload = json.dumps(
        {
            "schema": "kai.telemetry.v1",
            "device_id": "NEMO-04",
            "timestamp_ns": timestamp,
            "metrics": {"ACC/X": 1.25},
        }
    )
    points = parse_node_red_payload(payload, "kai/accelerometer")
    assert points[0].timestamp_ns == int(timestamp)


def test_rejects_invalid_explicit_nanosecond_timestamp() -> None:
    payload = json.dumps(
        {
            "schema": "kai.telemetry.v1",
            "device_id": "NEMO-05",
            "timestamp_ns": "not-a-timestamp",
            "metrics": {"ACC/X": 1.25},
        }
    )
    with pytest.raises(NodeRedPayloadError, match="timestamp_ns"):
        parse_node_red_payload(payload, "kai/accelerometer")
