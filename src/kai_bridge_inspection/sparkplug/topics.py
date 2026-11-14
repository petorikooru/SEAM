"""Sparkplug B topic parsing and validation."""

from __future__ import annotations

from kai_bridge_inspection.domain.errors import SparkplugStateError

from .models import SparkplugMessageType, SparkplugTopic


def parse_sparkplug_topic(topic: str, expected_namespace: str = "spBv1.0") -> SparkplugTopic:
    parts = topic.split("/")
    if len(parts) == 3 and parts[1] == SparkplugMessageType.STATE.value:
        namespace, _state, host_id = parts
        if namespace != expected_namespace:
            raise SparkplugStateError(
                f"unexpected Sparkplug namespace {namespace!r}; expected {expected_namespace!r}"
            )
        if not host_id or "\x00" in host_id:
            raise SparkplugStateError("Sparkplug STATE host id must be non-empty")
        return SparkplugTopic(namespace, "", SparkplugMessageType.STATE, host_id, None)
    if len(parts) not in (4, 5):
        raise SparkplugStateError(f"invalid Sparkplug topic level count: {topic!r}")
    namespace, group_id, raw_message_type, edge_node_id, *device = parts
    if namespace != expected_namespace:
        raise SparkplugStateError(
            f"unexpected Sparkplug namespace {namespace!r}; expected {expected_namespace!r}"
        )
    if not group_id or not edge_node_id or any("\x00" in part for part in parts):
        raise SparkplugStateError("Sparkplug topic components must be non-empty and contain no NUL")
    try:
        message_type = SparkplugMessageType(raw_message_type)
    except ValueError as exc:
        raise SparkplugStateError(f"unsupported Sparkplug message type: {raw_message_type!r}") from exc
    device_id = device[0] if device else None
    requires_device = message_type in {
        SparkplugMessageType.DBIRTH,
        SparkplugMessageType.DDEATH,
        SparkplugMessageType.DDATA,
        SparkplugMessageType.DCMD,
    }
    if requires_device and not device_id:
        raise SparkplugStateError(f"{message_type} requires a device id")
    if not requires_device and message_type != SparkplugMessageType.STATE and device_id:
        raise SparkplugStateError(f"{message_type} must not include a device id")
    return SparkplugTopic(namespace, group_id, message_type, edge_node_id, device_id)


def build_sparkplug_topic(topic: SparkplugTopic) -> str:
    parts = [topic.namespace, topic.group_id, topic.message_type.value, topic.edge_node_id]
    if topic.device_id:
        parts.append(topic.device_id)
    return "/".join(parts)
