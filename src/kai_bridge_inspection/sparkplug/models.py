"""Typed Sparkplug B topic, metric, payload, and state models."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from typing import TypeAlias

SparkplugScalar: TypeAlias = float | int | str | bool | bytes | None
DatasetCell: TypeAlias = SparkplugScalar


class SparkplugMessageType(StrEnum):
    NBIRTH = "NBIRTH"
    NDEATH = "NDEATH"
    DBIRTH = "DBIRTH"
    DDEATH = "DDEATH"
    NDATA = "NDATA"
    DDATA = "DDATA"
    NCMD = "NCMD"
    DCMD = "DCMD"
    STATE = "STATE"


@dataclass(frozen=True, slots=True)
class SparkplugTopic:
    namespace: str
    group_id: str
    message_type: SparkplugMessageType
    edge_node_id: str
    device_id: str | None = None

    @property
    def state_key(self) -> tuple[str, str, str | None]:
        return self.group_id, self.edge_node_id, self.device_id


@dataclass(frozen=True, slots=True)
class SparkplugDataset:
    columns: tuple[str, ...]
    types: tuple[int, ...]
    rows: tuple[tuple[DatasetCell, ...], ...]


@dataclass(frozen=True, slots=True)
class SparkplugMetric:
    name: str | None
    alias: int | None
    timestamp_ns: int | None
    data_type: int | None
    value: SparkplugScalar = None
    dataset: SparkplugDataset | None = None
    is_null: bool = False
    is_historical: bool = False
    is_transient: bool = False


@dataclass(frozen=True, slots=True)
class SparkplugPayload:
    timestamp_ns: int | None
    sequence: int | None
    metrics: tuple[SparkplugMetric, ...]
    uuid: str | None = None
    body: bytes | None = None


@dataclass(slots=True)
class SparkplugEntityState:
    online: bool = False
    aliases: dict[int, str] = field(default_factory=dict)
    last_sequence: int | None = None
    birth_sequence: int | None = None
    last_timestamp_ns: int = 0
