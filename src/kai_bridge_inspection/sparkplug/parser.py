"""Sparkplug B MQTT adapter that normalizes metrics to TelemetryPoint objects."""

from __future__ import annotations

import math
from typing import Final

from kai_bridge_inspection.domain.enums import ProtocolName, Quality
from kai_bridge_inspection.domain.errors import SparkplugStateError
from kai_bridge_inspection.domain.models import IncomingMqttMessage, TelemetryPoint

from .codec import ProtobufSparkplugCodec
from .models import (
    SparkplugDataset,
    SparkplugMessageType,
    SparkplugMetric,
    SparkplugScalar,
    SparkplugTopic,
)
from .state import SparkplugStateRegistry, StateUpdate
from .topics import parse_sparkplug_topic

_NANOSECONDS_PER_SECOND: Final[int] = 1_000_000_000
_DEFAULT_SAMPLE_INTERVAL_NS: Final[int] = 4_000_000
_NEMOSENSE_ALIAS_TO_NAME: Final[dict[int, str]] = {
    1: "ACC/TEMPERATURE",
    2: "ACC/ROLL",
    3: "ACC/PITCH",
    4: "VAR/DOUBLE",
    5: "VAR/STRING",
    16: "ACC/X",
    17: "ACC/Y",
    18: "ACC/Z",
}


class SparkplugTelemetryParser:
    def __init__(
        self,
        namespace: str = "spBv1.0",
        codec: ProtobufSparkplugCodec | None = None,
        state_registry: SparkplugStateRegistry | None = None,
    ) -> None:
        self.namespace = namespace
        self.codec = codec or ProtobufSparkplugCodec()
        self.state_registry = state_registry or SparkplugStateRegistry()
        self.last_state_update: StateUpdate | None = None
        self.last_message_ignored = False

    def can_parse(self, topic: str, payload: bytes) -> bool:
        del payload
        return topic.startswith(f"{self.namespace}/")

    def parse(self, message: IncomingMqttMessage) -> list[TelemetryPoint]:
        self.last_message_ignored = False
        topic = parse_sparkplug_topic(message.metadata.topic, self.namespace)
        if not message.payload:
            # Zero-byte retained publications are commonly used by MQTT clients to
            # clear retained Sparkplug topics. They are transport housekeeping, not
            # malformed telemetry.
            self.last_state_update = StateUpdate()
            self.last_message_ignored = True
            return []
        if topic.message_type is SparkplugMessageType.STATE:
            try:
                state_value = message.payload.decode("utf-8", errors="strict").strip()
            except UnicodeDecodeError as exc:
                raise SparkplugStateError("Sparkplug STATE payload is not valid UTF-8") from exc
            if state_value not in {"ONLINE", "OFFLINE"}:
                raise SparkplugStateError(f"invalid Sparkplug STATE payload: {state_value!r}")
            self.last_state_update = StateUpdate()
            return [
                TelemetryPoint(
                    timestamp_ns=message.metadata.received_timestamp_ns,
                    received_timestamp_ns=message.metadata.received_timestamp_ns,
                    device_id=topic.edge_node_id,
                    metric_name="STATE",
                    value=state_value,
                    unit=None,
                    quality=Quality.GOOD,
                    tags={},
                    mqtt_topic=message.metadata.topic,
                    mqtt_qos=message.metadata.qos,
                    mqtt_retain=message.metadata.retain,
                    protocol=ProtocolName.SPARKPLUG_B,
                    sparkplug_edge_node_id=topic.edge_node_id,
                )
            ]
        payload = self.codec.decode(message.payload)
        if topic.message_type in {SparkplugMessageType.NCMD, SparkplugMessageType.DCMD}:
            # Command traffic can share a broad ``spBv1.0/#`` subscription with
            # telemetry. It is valid Sparkplug traffic, but it must not be persisted
            # as sensor telemetry or treated as a rejected message.
            self.last_state_update = StateUpdate()
            self.last_message_ignored = True
            return []
        self.last_state_update = self.state_registry.apply(topic, payload)
        points: list[TelemetryPoint] = []
        for metric in payload.metrics:
            try:
                name = self.state_registry.resolve_metric_name(topic, metric)
            except SparkplugStateError:
                if metric.alias in _NEMOSENSE_ALIAS_TO_NAME:
                    name = _NEMOSENSE_ALIAS_TO_NAME[metric.alias]
                else:
                    # A subscriber can join after the latest BIRTH message. Keep
                    # processing named/known metrics and wait for the next BIRTH to
                    # rebuild this alias instead of rejecting the entire publication.
                    continue
            points.extend(
                self._metric_points(
                    topic=topic,
                    metric=metric,
                    metric_name=name.upper(),
                    payload_timestamp_ns=payload.timestamp_ns,
                    sequence=payload.sequence,
                    message=message,
                )
            )
        return points

    def _metric_points(
        self,
        *,
        topic: SparkplugTopic,
        metric: SparkplugMetric,
        metric_name: str,
        payload_timestamp_ns: int | None,
        sequence: int | None,
        message: IncomingMqttMessage,
    ) -> list[TelemetryPoint]:
        timestamp_ns = metric.timestamp_ns or payload_timestamp_ns or message.metadata.received_timestamp_ns
        if metric.dataset is not None:
            return self._dataset_points(
                topic, metric, metric_name, metric.dataset, timestamp_ns, sequence, message
            )
        if metric.is_null or not _valid_scalar(metric.value):
            return []
        return [
            self._point(
                topic,
                metric,
                metric_name,
                metric.value,
                timestamp_ns,
                sequence,
                message,
            )
        ]

    def _dataset_points(
        self,
        topic: SparkplugTopic,
        metric: SparkplugMetric,
        metric_name: str,
        dataset: SparkplugDataset,
        fallback_timestamp_ns: int,
        sequence: int | None,
        message: IncomingMqttMessage,
    ) -> list[TelemetryPoint]:
        if metric_name in {"ACC/X", "ACC/Y", "ACC/Z"}:
            interval_ns = self._infer_sample_interval_ns(dataset)
            points: list[TelemetryPoint] = []
            for row in dataset.rows:
                if len(row) < 2:
                    continue
                row_timestamp_ns = _microseconds_to_ns(row[0], fallback_timestamp_ns)
                for offset, value in enumerate(row[1:]):
                    if _valid_scalar(value):
                        points.append(
                            self._point(
                                topic,
                                metric,
                                metric_name,
                                value,
                                row_timestamp_ns + offset * interval_ns,
                                sequence,
                                message,
                            )
                        )
            return points
        if metric_name in {"ACC/PITCH", "ACC/ROLL", "ACC/TEMPERATURE"}:
            points = []
            for row in dataset.rows:
                if not row or not _valid_scalar(row[0]):
                    continue
                row_timestamp_ns = (
                    _microseconds_to_ns(row[1], fallback_timestamp_ns)
                    if len(row) > 1
                    else fallback_timestamp_ns
                )
                points.append(
                    self._point(topic, metric, metric_name, row[0], row_timestamp_ns, sequence, message)
                )
            return points
        if metric_name in {"VAR/DOUBLE", "VAR/STRING"}:
            points = []
            for row in dataset.rows:
                timestamp_ns = fallback_timestamp_ns
                for index, column in enumerate(dataset.columns):
                    if index >= len(row):
                        continue
                    column_name = column.upper()
                    value = row[index]
                    if column_name == "TIMESTAMP":
                        timestamp_ns = _microseconds_to_ns(value, fallback_timestamp_ns)
                        continue
                    if _valid_scalar(value):
                        canonical_name = {
                            "BAT_FUEL_GAUGE_REPSOC": "BATTERY",
                            "SIGNAL": "CELLULAR_RSSI",
                            "RSSI": "CELLULAR_RSSI",
                        }.get(column_name, column_name)
                        points.append(
                            self._point(
                                topic,
                                metric,
                                canonical_name,
                                value,
                                timestamp_ns,
                                sequence,
                                message,
                            )
                        )
            return points
        points = []
        for row_index, row in enumerate(dataset.rows):
            for column_index, value in enumerate(row):
                if not _valid_scalar(value):
                    continue
                column_name = (
                    dataset.columns[column_index]
                    if column_index < len(dataset.columns)
                    else f"column_{column_index}"
                )
                points.append(
                    self._point(
                        topic,
                        metric,
                        f"{metric_name}/{column_name}",
                        value,
                        fallback_timestamp_ns,
                        sequence,
                        message,
                        tags={"dataset_row": str(row_index)},
                    )
                )
        return points

    def _point(
        self,
        topic: SparkplugTopic,
        metric: SparkplugMetric,
        metric_name: str,
        value: SparkplugScalar,
        timestamp_ns: int,
        sequence: int | None,
        message: IncomingMqttMessage,
        tags: dict[str, str] | None = None,
    ) -> TelemetryPoint:
        device_id = topic.device_id or topic.edge_node_id
        return TelemetryPoint(
            timestamp_ns=timestamp_ns,
            received_timestamp_ns=message.metadata.received_timestamp_ns,
            device_id=device_id,
            metric_name=metric_name,
            value=value,
            unit=None,
            quality=Quality.GOOD,
            tags=tags or {},
            mqtt_topic=message.metadata.topic,
            mqtt_qos=message.metadata.qos,
            mqtt_retain=message.metadata.retain,
            protocol=ProtocolName.SPARKPLUG_B,
            sparkplug_group_id=topic.group_id,
            sparkplug_edge_node_id=topic.edge_node_id,
            sparkplug_device_id=topic.device_id,
            sparkplug_metric_alias=metric.alias,
            sparkplug_sequence=sequence,
        )

    @staticmethod
    def _infer_sample_interval_ns(dataset: SparkplugDataset) -> int:
        if len(dataset.rows) < 2 or len(dataset.rows[0]) < 2 or not dataset.rows[1]:
            return _DEFAULT_SAMPLE_INTERVAL_NS
        first_timestamp = dataset.rows[0][0]
        second_timestamp = dataset.rows[1][0]
        if not isinstance(first_timestamp, (int, float)) or not isinstance(second_timestamp, (int, float)):
            return _DEFAULT_SAMPLE_INTERVAL_NS
        samples = len(dataset.rows[0]) - 1
        delta_microseconds = float(second_timestamp) - float(first_timestamp)
        if samples <= 0 or delta_microseconds <= 0:
            return _DEFAULT_SAMPLE_INTERVAL_NS
        interval_ns = int((delta_microseconds * 1_000) / samples)
        return interval_ns if interval_ns > 0 else _DEFAULT_SAMPLE_INTERVAL_NS


def _microseconds_to_ns(value: SparkplugScalar, fallback: int) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return fallback
    numeric = float(value)
    if not math.isfinite(numeric) or numeric <= 0:
        return fallback
    if numeric > 1_000_000_000_000:
        return int(numeric * 1_000)
    if numeric > 1_000_000_000:
        return int(numeric * _NANOSECONDS_PER_SECOND)
    return int(numeric * 1_000)


def _valid_scalar(value: SparkplugScalar) -> bool:
    if isinstance(value, float):
        return math.isfinite(value)
    return value is not None
