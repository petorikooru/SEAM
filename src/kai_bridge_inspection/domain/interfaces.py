"""Protocols defining replaceable infrastructure boundaries."""

from __future__ import annotations

from collections.abc import Callable, Iterator, Sequence
from typing import Protocol

from .models import (
    HistoricalQuery,
    IncomingMqttMessage,
    MqttBrokerProfile,
    OutboundMqttMessage,
    TelemetryPage,
    TelemetryPoint,
)


class SecretProvider(Protocol):
    def get_secret(self, reference: str) -> str | None:
        """Resolve a secret reference without persisting the secret."""


class TelemetryRepository(Protocol):
    def write_batch(self, points: Sequence[TelemetryPoint]) -> int:
        """Persist a batch atomically and return the inserted point count."""

    def query(self, query: HistoricalQuery) -> TelemetryPage:
        """Return a bounded, paginated historical query."""

    def iter_points(self, query: HistoricalQuery) -> Iterator[TelemetryPoint]:
        """Stream all matching points in chronological order, without downsampling."""

    def latest_values(self, device_id: str, limit: int = 200) -> Sequence[TelemetryPoint]:
        """Return the newest value for each metric."""

    def list_devices(self) -> Sequence[str]:
        """Return known device identifiers."""

    def list_metrics(self, device_id: str) -> Sequence[str]:
        """Return stored metric names for a device."""

    def purge_before(self, timestamp_ns: int) -> int:
        """Delete old points and return affected rows."""

    def close(self) -> None:
        """Release owned resources."""


MessageHandler = Callable[[IncomingMqttMessage], None]
StateHandler = Callable[[bool, str], None]


class MqttClientService(Protocol):
    def connect(self, profile: MqttBrokerProfile) -> None:
        """Connect and subscribe using a broker profile."""

    def disconnect(self) -> None:
        """Disconnect gracefully."""

    def publish(self, message: OutboundMqttMessage) -> None:
        """Publish a validated outbound message."""

    def is_connected(self) -> bool:
        """Return whether the broker session is connected."""


class TelemetryPayloadParser(Protocol):
    def can_parse(self, topic: str, payload: bytes) -> bool:
        """Return whether this parser owns the payload."""

    def parse(self, message: IncomingMqttMessage) -> list[TelemetryPoint]:
        """Normalize a message into telemetry points."""
