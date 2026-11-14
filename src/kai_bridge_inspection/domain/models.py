"""Immutable, typed domain models."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from typing import Final, TypeAlias

from .enums import DaemonState, ProtocolName, Quality

TelemetryScalar: TypeAlias = float | int | str | bool | bytes | None
TagMap: TypeAlias = Mapping[str, str]

PROTOCOL_VERSION: Final[int] = 1


@dataclass(frozen=True, slots=True)
class MqttSubscription:
    topic: str
    qos: int = 0


@dataclass(frozen=True, slots=True)
class MqttBrokerProfile:
    broker_id: int
    name: str
    host: str
    port: int = 1883
    client_id: str = ""
    username: str = ""
    password_env: str = ""
    keepalive_seconds: int = 60
    clean_session: bool = True
    tls_enabled: bool = False
    ca_certificate_path: str = ""
    client_certificate_path: str = ""
    client_key_path: str = ""
    allow_insecure_tls: bool = False
    enabled: bool = True
    subscriptions: Sequence[MqttSubscription] = field(default_factory=tuple)


@dataclass(frozen=True, slots=True)
class MqttMessageMetadata:
    topic: str
    qos: int
    retain: bool
    received_timestamp_ns: int
    broker_id: int


@dataclass(frozen=True, slots=True)
class IncomingMqttMessage:
    metadata: MqttMessageMetadata
    payload: bytes


@dataclass(frozen=True, slots=True)
class OutboundMqttMessage:
    topic: str
    payload: bytes
    qos: int = 0
    retain: bool = False


@dataclass(frozen=True, slots=True)
class TelemetryPoint:
    timestamp_ns: int
    received_timestamp_ns: int
    device_id: str
    metric_name: str
    value: TelemetryScalar
    unit: str | None
    quality: Quality | str | None
    tags: TagMap
    mqtt_topic: str
    mqtt_qos: int
    mqtt_retain: bool
    protocol: ProtocolName | str
    sparkplug_group_id: str | None = None
    sparkplug_edge_node_id: str | None = None
    sparkplug_device_id: str | None = None
    sparkplug_metric_alias: int | None = None
    sparkplug_sequence: int | None = None


@dataclass(frozen=True, slots=True)
class HistoricalQuery:
    start_timestamp_ns: int = 0
    end_timestamp_ns: int = 0
    device_id: str | None = None
    metric_name: str | None = None
    mqtt_topic: str | None = None
    protocol: str | None = None
    limit: int = 2_000
    offset: int = 0
    max_points: int = 2_000


@dataclass(frozen=True, slots=True)
class TelemetryPage:
    points: Sequence[TelemetryPoint]
    total_count: int
    limit: int
    offset: int


@dataclass(frozen=True, slots=True)
class IngestionStatistics:
    started_timestamp_ns: int
    messages_received: int = 0
    messages_parsed: int = 0
    messages_rejected: int = 0
    telemetry_points_created: int = 0
    telemetry_points_written: int = 0
    write_failures: int = 0
    messages_dropped: int = 0
    queue_depth: int = 0
    queue_capacity: int = 0
    reconnect_count: int = 0
    sparkplug_payloads_decoded: int = 0
    sparkplug_decode_failures: int = 0
    birth_messages_received: int = 0
    death_messages_received: int = 0
    unknown_metric_aliases: int = 0
    last_successful_write_timestamp_ns: int = 0


@dataclass(frozen=True, slots=True)
class DaemonStatus:
    state: DaemonState
    process_running: bool
    collection_enabled: bool
    mqtt_connected: bool
    standard_subscriptions_active: bool
    sparkplug_subscriptions_active: bool
    sparkplug_session_valid: bool
    database_writer_healthy: bool
    ipc_active: bool
    active_broker_count: int
    connected_ui_clients: int
    last_error: str = ""


@dataclass(frozen=True, slots=True)
class LocationRecord:
    name: str
    description: str
    latitude: float
    longitude: float


@dataclass(frozen=True, slots=True)
class SensorRecord:
    name: str
    description: str
    location_name: str
    broker_id: int | None
    mqtt_server: str
    mqtt_port: int
    mqtt_topic: str
    mqtt_username: str
    password_env: str
    device_id: str
    device_type: str
    sample_rate: int
    trigger_mode: str
    latitude: float
    longitude: float
    websocket_endpoint: str = ""
    profile: str = "nemosense"
