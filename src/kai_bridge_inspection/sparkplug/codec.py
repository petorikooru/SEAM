"""Sparkplug B protobuf codec isolated behind typed domain models."""

from __future__ import annotations

import os
from collections.abc import Iterable
from typing import Final

from kai_bridge_inspection.domain.errors import SparkplugDecodeError

from .models import SparkplugDataset, SparkplugMetric, SparkplugPayload, SparkplugScalar

os.environ.setdefault("PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION", "python")
from . import sparkplug_b_pb2  # noqa: E402

_MILLISECONDS_THRESHOLD: Final[int] = 10_000_000_000


class ProtobufSparkplugCodec:
    """Decode the bundled Eclipse Tahu protobuf definition without extra packages."""

    def decode(self, payload: bytes) -> SparkplugPayload:
        if not payload:
            raise SparkplugDecodeError("empty Sparkplug payload")
        message = sparkplug_b_pb2.Payload()
        try:
            message.ParseFromString(payload)
        except Exception as exc:
            raise SparkplugDecodeError(f"invalid Sparkplug protobuf: {exc}") from exc
        try:
            timestamp_ns = _timestamp_to_ns(int(message.timestamp)) if message.HasField("timestamp") else None
            sequence = int(message.seq) if message.HasField("seq") else None
            uuid = str(message.uuid) if message.HasField("uuid") else None
            body = bytes(message.body) if message.HasField("body") else None
            metrics = tuple(self._decode_metric(metric) for metric in message.metrics)
        except Exception as exc:
            raise SparkplugDecodeError(f"unsupported Sparkplug payload structure: {exc}") from exc
        return SparkplugPayload(timestamp_ns, sequence, metrics, uuid, body)

    def encode(self, payload: SparkplugPayload) -> bytes:
        message = sparkplug_b_pb2.Payload()
        if payload.timestamp_ns is not None:
            message.timestamp = payload.timestamp_ns // 1_000_000
        if payload.sequence is not None:
            message.seq = payload.sequence
        if payload.uuid is not None:
            message.uuid = payload.uuid
        if payload.body is not None:
            message.body = payload.body
        for metric_model in payload.metrics:
            metric = message.metrics.add()
            if metric_model.name is not None:
                metric.name = metric_model.name
            if metric_model.alias is not None:
                metric.alias = metric_model.alias
            if metric_model.timestamp_ns is not None:
                metric.timestamp = metric_model.timestamp_ns // 1_000_000
            if metric_model.data_type is not None:
                metric.datatype = metric_model.data_type
            metric.is_null = metric_model.is_null
            metric.is_historical = metric_model.is_historical
            metric.is_transient = metric_model.is_transient
            self._assign_scalar(metric, metric_model.value)
        return bytes(message.SerializeToString())

    def _decode_metric(self, metric: object) -> SparkplugMetric:
        name = str(metric.name) if metric.HasField("name") else None  # type: ignore[attr-defined]
        alias = int(metric.alias) if metric.HasField("alias") else None  # type: ignore[attr-defined]
        timestamp_ns = (
            _timestamp_to_ns(int(metric.timestamp)) if metric.HasField("timestamp") else None  # type: ignore[attr-defined]
        )
        data_type = int(metric.datatype) if metric.HasField("datatype") else None  # type: ignore[attr-defined]
        is_null = bool(metric.is_null) if metric.HasField("is_null") else False  # type: ignore[attr-defined]
        is_historical = bool(metric.is_historical) if metric.HasField("is_historical") else False  # type: ignore[attr-defined]
        is_transient = bool(metric.is_transient) if metric.HasField("is_transient") else False  # type: ignore[attr-defined]
        dataset = self._decode_dataset(metric.dataset_value) if metric.HasField("dataset_value") else None  # type: ignore[attr-defined]
        value = None if dataset is not None else self._metric_scalar(metric)
        return SparkplugMetric(
            name=name,
            alias=alias,
            timestamp_ns=timestamp_ns,
            data_type=data_type,
            value=value,
            dataset=dataset,
            is_null=is_null,
            is_historical=is_historical,
            is_transient=is_transient,
        )

    def _decode_dataset(self, dataset: object) -> SparkplugDataset:
        columns = tuple(str(column) for column in dataset.columns)  # type: ignore[attr-defined]
        types = tuple(int(data_type) for data_type in dataset.types)  # type: ignore[attr-defined]
        rows: list[tuple[SparkplugScalar, ...]] = []
        for row in dataset.rows:  # type: ignore[attr-defined]
            rows.append(tuple(self._dataset_scalar(element) for element in row.elements))
        return SparkplugDataset(columns=columns, types=types, rows=tuple(rows))

    @staticmethod
    def _metric_scalar(metric: object) -> SparkplugScalar:
        for field_name, converter in (
            ("int_value", int),
            ("long_value", int),
            ("float_value", float),
            ("double_value", float),
            ("boolean_value", bool),
            ("string_value", str),
            ("bytes_value", bytes),
        ):
            if metric.HasField(field_name):  # type: ignore[attr-defined]
                return converter(getattr(metric, field_name))
        return None

    @staticmethod
    def _dataset_scalar(element: object) -> SparkplugScalar:
        oneof_name = element.WhichOneof("value")  # type: ignore[attr-defined]
        if not oneof_name:
            return None
        raw = getattr(element, oneof_name)
        if oneof_name in {"int_value", "long_value"}:
            return int(raw)
        if oneof_name in {"float_value", "double_value"}:
            return float(raw)
        if oneof_name == "boolean_value":
            return bool(raw)
        if oneof_name == "string_value":
            return str(raw)
        return None

    @staticmethod
    def _assign_scalar(metric: object, value: SparkplugScalar) -> None:
        if value is None:
            return
        if isinstance(value, bool):
            metric.boolean_value = value  # type: ignore[attr-defined]
        elif isinstance(value, int):
            metric.long_value = value  # type: ignore[attr-defined]
        elif isinstance(value, float):
            metric.double_value = value  # type: ignore[attr-defined]
        elif isinstance(value, str):
            metric.string_value = value  # type: ignore[attr-defined]
        elif isinstance(value, bytes):
            metric.bytes_value = value  # type: ignore[attr-defined]


def _timestamp_to_ns(value: int) -> int:
    if value <= 0:
        return 0
    if value < _MILLISECONDS_THRESHOLD:
        return value * 1_000_000_000
    return value * 1_000_000
