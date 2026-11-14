"""Standard JSON telemetry parsing and parser routing."""

from __future__ import annotations

import json
import math
import re
from datetime import datetime, timezone
from typing import Final

from kai_bridge_inspection.domain.enums import ProtocolName, Quality
from kai_bridge_inspection.domain.errors import TelemetryParseError
from kai_bridge_inspection.domain.interfaces import TelemetryPayloadParser
from kai_bridge_inspection.domain.models import IncomingMqttMessage, TelemetryPoint, TelemetryScalar

_MAX_PAYLOAD_BYTES: Final[int] = 2 * 1024 * 1024
_IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9_.:-]{1,128}$")
_RESERVED_FIELDS = frozenset({"device_id", "timestamp", "timestamp_ns", "unit", "quality", "tags"})


class JsonTelemetryParser:
    """Parse flat or nested JSON objects into one typed point per scalar leaf."""

    def can_parse(self, topic: str, payload: bytes) -> bool:
        stripped = payload.lstrip()
        return bool(stripped) and stripped[:1] in {b"{", b"["} and not topic.startswith("spBv1.0/")

    def parse(self, message: IncomingMqttMessage) -> list[TelemetryPoint]:
        if len(message.payload) > _MAX_PAYLOAD_BYTES:
            raise TelemetryParseError("JSON payload exceeds the 2 MiB limit")
        try:
            text = message.payload.decode("utf-8", errors="strict")
        except UnicodeDecodeError as exc:
            raise TelemetryParseError("JSON payload is not valid UTF-8") from exc
        try:
            document = json.loads(text)
        except json.JSONDecodeError as exc:
            raise TelemetryParseError(f"malformed JSON payload: {exc.msg}") from exc
        objects: list[dict[str, object]]
        if isinstance(document, dict):
            objects = [document]
        elif isinstance(document, list) and all(isinstance(item, dict) for item in document):
            objects = [item for item in document if isinstance(item, dict)]
        else:
            raise TelemetryParseError("JSON telemetry must be an object or an array of objects")
        points: list[TelemetryPoint] = []
        for item in objects:
            device_id = str(item.get("device_id") or _device_from_topic(message.metadata.topic))
            if not _IDENTIFIER_RE.fullmatch(device_id):
                raise TelemetryParseError(f"invalid device_id: {device_id!r}")
            timestamp_ns = _parse_timestamp_ns(item, message.metadata.received_timestamp_ns)
            unit = str(item["unit"]) if isinstance(item.get("unit"), str) else None
            quality = str(item["quality"]) if isinstance(item.get("quality"), str) else Quality.GOOD
            tags_value = item.get("tags")
            tags = (
                {str(key): str(value) for key, value in tags_value.items()}
                if isinstance(tags_value, dict)
                else {}
            )
            for metric_name, value in _flatten_metrics(item):
                if not _IDENTIFIER_RE.fullmatch(metric_name.replace("/", ".")):
                    raise TelemetryParseError(f"invalid metric name: {metric_name!r}")
                points.append(
                    TelemetryPoint(
                        timestamp_ns=timestamp_ns,
                        received_timestamp_ns=message.metadata.received_timestamp_ns,
                        device_id=device_id,
                        metric_name=metric_name,
                        value=value,
                        unit=unit,
                        quality=quality,
                        tags=tags,
                        mqtt_topic=message.metadata.topic,
                        mqtt_qos=message.metadata.qos,
                        mqtt_retain=message.metadata.retain,
                        protocol=ProtocolName.JSON,
                    )
                )
        if not points:
            raise TelemetryParseError("JSON payload contains no scalar telemetry fields")
        return points


class TopicParserRouter:
    """Select the first parser that explicitly accepts a message."""

    def __init__(self, parsers: list[TelemetryPayloadParser]) -> None:
        self._parsers = tuple(parsers)

    def parse(self, message: IncomingMqttMessage) -> list[TelemetryPoint]:
        for parser in self._parsers:
            if parser.can_parse(message.metadata.topic, message.payload):
                return parser.parse(message)
        raise TelemetryParseError(f"no parser accepted topic {message.metadata.topic!r}")


def _flatten_metrics(document: dict[str, object]) -> list[tuple[str, TelemetryScalar]]:
    points: list[tuple[str, TelemetryScalar]] = []

    def visit(prefix: str, value: object) -> None:
        if isinstance(value, bool):
            points.append((prefix, value))
        elif isinstance(value, int):
            points.append((prefix, value))
        elif isinstance(value, float):
            if not math.isfinite(value):
                raise TelemetryParseError(f"metric {prefix!r} is non-finite")
            points.append((prefix, value))
        elif isinstance(value, str):
            points.append((prefix, value))
        elif value is None:
            points.append((prefix, None))
        elif isinstance(value, dict):
            for child_key, child_value in value.items():
                child_name = f"{prefix}/{child_key}" if prefix else str(child_key)
                visit(child_name, child_value)
        elif isinstance(value, list):
            for index, child_value in enumerate(value):
                child_name = f"{prefix}/{index}"
                visit(child_name, child_value)
        else:
            raise TelemetryParseError(f"unsupported JSON value for metric {prefix!r}")

    for key, value in document.items():
        if key in _RESERVED_FIELDS:
            continue
        visit(str(key), value)
    return points


def _parse_timestamp_ns(document: dict[str, object], fallback: int) -> int:
    if "timestamp_ns" in document:
        raw = document["timestamp_ns"]
        if isinstance(raw, bool) or not isinstance(raw, (int, float)):
            raise TelemetryParseError("timestamp_ns must be numeric")
        timestamp_ns = int(raw)
        if timestamp_ns <= 0:
            raise TelemetryParseError("timestamp_ns must be positive")
        return timestamp_ns
    raw_timestamp = document.get("timestamp")
    if raw_timestamp is None:
        return fallback
    if isinstance(raw_timestamp, bool):
        raise TelemetryParseError("timestamp must not be boolean")
    if isinstance(raw_timestamp, (int, float)):
        numeric = float(raw_timestamp)
        if not math.isfinite(numeric) or numeric <= 0:
            raise TelemetryParseError("timestamp must be finite and positive")
        if numeric > 10_000_000_000_000_000:
            return int(numeric)
        if numeric > 10_000_000_000:
            return int(numeric * 1_000_000)
        return int(numeric * 1_000_000_000)
    if isinstance(raw_timestamp, str):
        normalized = raw_timestamp.strip().replace("Z", "+00:00")
        try:
            parsed = datetime.fromisoformat(normalized)
        except ValueError as exc:
            raise TelemetryParseError(f"invalid ISO-8601 timestamp: {raw_timestamp!r}") from exc
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return int(parsed.timestamp() * 1_000_000_000)
    raise TelemetryParseError("timestamp must be numeric or ISO-8601 text")


def _device_from_topic(topic: str) -> str:
    levels = [level for level in topic.split("/") if level]
    candidate = levels[-1] if levels else "unknown-device"
    candidate = re.sub(r"[^A-Za-z0-9_.:-]", "-", candidate)
    return candidate[:128] or "unknown-device"
