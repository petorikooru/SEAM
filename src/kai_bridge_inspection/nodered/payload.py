"""Parse the canonical JSON emitted by the supplied Node-RED flow.

Node-RED performs all MQTT and Sparkplug B protocol work. The desktop accepts
only normalized JSON envelopes and never receives MQTT packets or protobuf.
"""

from __future__ import annotations

import json
import math
import re
import time
from collections.abc import Mapping, Sequence
from typing import Final

from kai_bridge_inspection.domain.enums import ProtocolName, Quality
from kai_bridge_inspection.domain.models import TelemetryPoint, TelemetryScalar

_MAX_MESSAGE_BYTES: Final[int] = 4 * 1024 * 1024
_IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9_.:/-]{1,192}$")


class NodeRedPayloadError(ValueError):
    """Raised when a Node-RED endpoint violates the desktop JSON contract."""


def parse_node_red_payload(payload: str | bytes, endpoint: str) -> list[TelemetryPoint]:
    """Convert one Node-RED WebSocket message into normalized telemetry points.

    Supported envelope forms::

        {"schema":"kai.telemetry.v1", "device_id":"sensor-1",
         "timestamp_ns": 123, "metrics":{"ACC/X": 0.1}}

        {"schema":"kai.telemetry.v1", "points":[
            {"device_id":"sensor-1", "metric_name":"ACC/X",
             "timestamp_ns":123, "value":0.1}
        ]}
    """
    raw = payload.encode("utf-8") if isinstance(payload, str) else bytes(payload)
    if len(raw) > _MAX_MESSAGE_BYTES:
        raise NodeRedPayloadError("Node-RED message exceeds the 4 MiB limit")
    try:
        document = json.loads(raw.decode("utf-8", errors="strict"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise NodeRedPayloadError(f"invalid Node-RED JSON: {exc}") from exc

    envelopes: Sequence[object] = document if isinstance(document, list) else (document,)
    points: list[TelemetryPoint] = []
    received_ns = time.time_ns()
    for envelope in envelopes:
        if not isinstance(envelope, Mapping):
            raise NodeRedPayloadError("Node-RED message must be an object or array of objects")
        schema = envelope.get("schema", "kai.telemetry.v1")
        if schema != "kai.telemetry.v1":
            raise NodeRedPayloadError(f"unsupported Node-RED schema: {schema!r}")
        raw_points = envelope.get("points")
        if raw_points is not None:
            if not isinstance(raw_points, list):
                raise NodeRedPayloadError("points must be an array")
            for raw_point in raw_points:
                if not isinstance(raw_point, Mapping):
                    raise NodeRedPayloadError("each points entry must be an object")
                points.append(_point_from_mapping(raw_point, envelope, endpoint, received_ns))
            continue

        metrics = envelope.get("metrics")
        if not isinstance(metrics, Mapping):
            raise NodeRedPayloadError("message requires either points[] or metrics{}")
        device_id = _identifier(envelope.get("device_id"), "device_id")
        timestamp_ns = _timestamp_ns(envelope, received_ns)
        unit_map = envelope.get("units") if isinstance(envelope.get("units"), Mapping) else {}
        quality = str(envelope.get("quality", Quality.GOOD))
        tags = _tags(envelope.get("tags"), endpoint)
        source_topic = str(envelope.get("source_topic", f"nodered://{endpoint}"))
        for raw_name, value in metrics.items():
            metric_name = _identifier(raw_name, "metric_name")
            scalar = _scalar(value, metric_name)
            unit = unit_map.get(metric_name) if isinstance(unit_map, Mapping) else None
            points.append(
                TelemetryPoint(
                    timestamp_ns=timestamp_ns,
                    received_timestamp_ns=received_ns,
                    device_id=device_id,
                    metric_name=metric_name,
                    value=scalar,
                    unit=str(unit) if unit is not None else None,
                    quality=quality,
                    tags=tags,
                    mqtt_topic=source_topic,
                    mqtt_qos=0,
                    mqtt_retain=False,
                    protocol=ProtocolName.NODE_RED,
                    sparkplug_group_id=_optional_text(envelope.get("group_id")),
                    sparkplug_edge_node_id=_optional_text(envelope.get("edge_node_id")),
                    sparkplug_device_id=_optional_text(envelope.get("sparkplug_device_id")),
                    sparkplug_sequence=_optional_int(envelope.get("sequence")),
                )
            )
    if not points:
        raise NodeRedPayloadError("Node-RED message contains no telemetry points")
    return points


def _point_from_mapping(
    raw_point: Mapping[object, object],
    envelope: Mapping[object, object],
    endpoint: str,
    received_ns: int,
) -> TelemetryPoint:
    merged: dict[object, object] = dict(envelope)
    merged.update(raw_point)
    device_id = _identifier(merged.get("device_id"), "device_id")
    metric_name = _identifier(merged.get("metric_name"), "metric_name")
    value = _scalar(merged.get("value"), metric_name)
    return TelemetryPoint(
        timestamp_ns=_timestamp_ns(merged, received_ns),
        received_timestamp_ns=received_ns,
        device_id=device_id,
        metric_name=metric_name,
        value=value,
        unit=_optional_text(merged.get("unit")),
        quality=str(merged.get("quality", Quality.GOOD)),
        tags=_tags(merged.get("tags"), endpoint),
        mqtt_topic=str(merged.get("source_topic", f"nodered://{endpoint}")),
        mqtt_qos=0,
        mqtt_retain=False,
        protocol=ProtocolName.NODE_RED,
        sparkplug_group_id=_optional_text(merged.get("group_id")),
        sparkplug_edge_node_id=_optional_text(merged.get("edge_node_id")),
        sparkplug_device_id=_optional_text(merged.get("sparkplug_device_id")),
        sparkplug_metric_alias=_optional_int(merged.get("alias")),
        sparkplug_sequence=_optional_int(merged.get("sequence")),
    )


def _identifier(value: object, label: str) -> str:
    text = str(value or "").strip()
    if not _IDENTIFIER_RE.fullmatch(text):
        raise NodeRedPayloadError(f"invalid {label}: {text!r}")
    return text


def _timestamp_ns(mapping: Mapping[object, object], fallback: int) -> int:
    raw_ns = mapping.get("timestamp_ns")
    if raw_ns is not None:
        if isinstance(raw_ns, bool):
            raise NodeRedPayloadError("timestamp_ns must be a positive integer")
        try:
            if isinstance(raw_ns, str):
                text = raw_ns.strip()
                if not text.isdigit():
                    raise ValueError
                result = int(text)
            elif isinstance(raw_ns, int):
                result = raw_ns
            elif isinstance(raw_ns, float) and math.isfinite(raw_ns) and raw_ns.is_integer():
                result = int(raw_ns)
            else:
                raise ValueError
        except (TypeError, ValueError) as exc:
            raise NodeRedPayloadError("timestamp_ns must be a positive integer") from exc
        if result <= 0:
            raise NodeRedPayloadError("timestamp_ns must be a positive integer")
        return result
    raw_ms = mapping.get("timestamp")
    if isinstance(raw_ms, (int, float)) and not isinstance(raw_ms, bool):
        numeric = float(raw_ms)
        if not math.isfinite(numeric) or numeric <= 0:
            raise NodeRedPayloadError("timestamp must be finite and positive")
        if numeric > 10_000_000_000_000_000:
            return int(numeric)
        if numeric > 10_000_000_000:
            return int(numeric * 1_000_000)
        return int(numeric * 1_000_000_000)
    return fallback


def _scalar(value: object, metric_name: str) -> TelemetryScalar:
    if value is None or isinstance(value, (bool, int, str)):
        return value
    if isinstance(value, float):
        if not math.isfinite(value):
            raise NodeRedPayloadError(f"metric {metric_name!r} is non-finite")
        return value
    raise NodeRedPayloadError(f"metric {metric_name!r} must be a JSON scalar")


def _tags(value: object, endpoint: str) -> dict[str, str]:
    result = {"node_red_endpoint": endpoint}
    if isinstance(value, Mapping):
        result.update({str(key): str(item) for key, item in value.items()})
    return result


def _optional_text(value: object) -> str | None:
    return None if value is None else str(value)


def _optional_int(value: object) -> int | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None
