"""Validated settings service."""

from __future__ import annotations

from dataclasses import dataclass

from kai_bridge_inspection.domain.errors import ConfigurationError
from kai_bridge_inspection.domain.models import MqttBrokerProfile

from .repository import SettingsRepository


@dataclass(frozen=True, slots=True)
class EffectiveDaemonConfiguration:
    brokers: tuple[MqttBrokerProfile, ...]
    collection_enabled: bool
    retention_days: int
    sparkplug_namespace: str
    telemetry_backend: str


class SettingsService:
    def __init__(self, repository: SettingsRepository) -> None:
        self.repository = repository

    def effective_daemon_configuration(self) -> EffectiveDaemonConfiguration:
        self.repository.ensure_sensor_subscriptions()
        retention_days = self._positive_int("retention_days", 365, maximum=36_500)
        namespace = self.repository.get_setting("sparkplug_namespace", "spBv1.0").strip()
        if not namespace or "/" in namespace:
            raise ConfigurationError("Sparkplug namespace must be one topic level")
        backend = self.repository.get_setting("telemetry_backend", "sqlite")
        if backend != "sqlite":
            raise ConfigurationError("only the sqlite telemetry backend is enabled in the base installation")
        return EffectiveDaemonConfiguration(
            brokers=tuple(self.repository.list_brokers(enabled_only=True)),
            collection_enabled=self.repository.get_setting("data_gathering", "true") == "true",
            retention_days=retention_days,
            sparkplug_namespace=namespace,
            telemetry_backend=backend,
        )

    def _positive_int(self, key: str, default: int, maximum: int) -> int:
        raw = self.repository.get_setting(key, str(default))
        try:
            value = int(raw)
        except ValueError as exc:
            raise ConfigurationError(f"{key} must be an integer") from exc
        if not 0 <= value <= maximum:
            raise ConfigurationError(f"{key} must be between 0 and {maximum}")
        return value
