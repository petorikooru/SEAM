"""Versioned JSON Lines IPC framing and validation."""

from __future__ import annotations

import json
import uuid
from collections.abc import Mapping
from typing import Final

from kai_bridge_inspection.domain.errors import IpcProtocolError
from kai_bridge_inspection.domain.models import PROTOCOL_VERSION, TelemetryPoint

from .messages import IpcEventDict, IpcRequestDict, IpcResponseDict

MAX_IPC_MESSAGE_BYTES: Final[int] = 4 * 1024 * 1024
ALLOWED_COMMANDS: Final[frozenset[str]] = frozenset(
    {
        "ping",
        "get_status",
        "start_collection",
        "stop_collection",
        "reload_settings",
        "get_devices",
        "get_latest_values",
        "query_telemetry",
        "get_ingestion_statistics",
        "get_sparkplug_state",
        "shutdown",
    }
)


def new_request(command: str, payload: Mapping[str, object] | None = None) -> IpcRequestDict:
    if command not in ALLOWED_COMMANDS:
        raise IpcProtocolError(f"unsupported command: {command}")
    return {
        "protocol_version": PROTOCOL_VERSION,
        "request_id": uuid.uuid4().hex,
        "command": command,
        "payload": dict(payload or {}),
    }


def encode_message(message: Mapping[str, object]) -> bytes:
    try:
        encoded = json.dumps(message, separators=(",", ":"), ensure_ascii=False).encode("utf-8") + b"\n"
    except (TypeError, ValueError) as exc:
        raise IpcProtocolError(f"IPC message is not JSON serializable: {exc}") from exc
    if len(encoded) > MAX_IPC_MESSAGE_BYTES:
        raise IpcProtocolError("IPC message exceeds the 4 MiB limit")
    return encoded


def decode_line(line: bytes) -> dict[str, object]:
    if len(line) > MAX_IPC_MESSAGE_BYTES:
        raise IpcProtocolError("IPC message exceeds the 4 MiB limit")
    try:
        decoded = line.decode("utf-8", errors="strict")
        message = json.loads(decoded)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise IpcProtocolError(f"malformed IPC JSON: {exc}") from exc
    if not isinstance(message, dict):
        raise IpcProtocolError("IPC message must be a JSON object")
    version = message.get("protocol_version")
    if version != PROTOCOL_VERSION:
        raise IpcProtocolError(
            f"unsupported protocol version {version!r}; expected {PROTOCOL_VERSION}"
        )
    return {str(key): value for key, value in message.items()}


def validate_request(message: Mapping[str, object]) -> IpcRequestDict:
    request_id = message.get("request_id")
    command = message.get("command")
    payload = message.get("payload", {})
    if not isinstance(request_id, str) or not request_id or len(request_id) > 128:
        raise IpcProtocolError("request_id must be a non-empty string no longer than 128 characters")
    if not isinstance(command, str) or command not in ALLOWED_COMMANDS:
        raise IpcProtocolError(f"unsupported command: {command!r}")
    if not isinstance(payload, dict):
        raise IpcProtocolError("request payload must be an object")
    return {
        "protocol_version": PROTOCOL_VERSION,
        "request_id": request_id,
        "command": command,
        "payload": {str(key): value for key, value in payload.items()},
    }


def success_response(request_id: str, result: Mapping[str, object] | None = None) -> IpcResponseDict:
    return {
        "protocol_version": PROTOCOL_VERSION,
        "request_id": request_id,
        "ok": True,
        "result": dict(result or {}),
        "error": None,
    }


def error_response(request_id: str, code: str, message: str) -> IpcResponseDict:
    return {
        "protocol_version": PROTOCOL_VERSION,
        "request_id": request_id,
        "ok": False,
        "result": None,
        "error": {"code": code, "message": message[:2_000]},
    }


def event_message(event: str, payload: Mapping[str, object]) -> IpcEventDict:
    return {
        "protocol_version": PROTOCOL_VERSION,
        "event": event,
        "payload": dict(payload),
    }


def telemetry_point_to_dict(point: TelemetryPoint) -> dict[str, object]:
    value: object = point.value
    if isinstance(value, bytes):
        value = value.hex()
    return {
        "timestamp_ns": point.timestamp_ns,
        "received_timestamp_ns": point.received_timestamp_ns,
        "device_id": point.device_id,
        "metric_name": point.metric_name,
        "value": value,
        "unit": point.unit,
        "quality": str(point.quality) if point.quality is not None else None,
        "tags": dict(point.tags),
        "mqtt_topic": point.mqtt_topic,
        "mqtt_qos": point.mqtt_qos,
        "mqtt_retain": point.mqtt_retain,
        "protocol": str(point.protocol),
        "sparkplug_group_id": point.sparkplug_group_id,
        "sparkplug_edge_node_id": point.sparkplug_edge_node_id,
        "sparkplug_device_id": point.sparkplug_device_id,
        "sparkplug_metric_alias": point.sparkplug_metric_alias,
        "sparkplug_sequence": point.sparkplug_sequence,
    }
