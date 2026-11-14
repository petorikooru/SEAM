"""MQTT configuration validation helpers."""

from __future__ import annotations

from kai_bridge_inspection.domain.errors import ConfigurationError
from kai_bridge_inspection.domain.models import MqttBrokerProfile
from kai_bridge_inspection.settings.repository import SettingsRepository


def validate_profile(profile: MqttBrokerProfile) -> None:
    if not profile.host.strip():
        raise ConfigurationError("MQTT broker host is required")
    if not 1 <= profile.port <= 65_535:
        raise ConfigurationError("MQTT broker port must be between 1 and 65535")
    if not 5 <= profile.keepalive_seconds <= 65_535:
        raise ConfigurationError("MQTT keepalive must be between 5 and 65535 seconds")
    for subscription in profile.subscriptions:
        if not SettingsRepository.is_valid_topic_filter(subscription.topic):
            raise ConfigurationError(f"invalid MQTT topic filter: {subscription.topic!r}")
        if subscription.qos not in (0, 1, 2):
            raise ConfigurationError("MQTT QoS must be 0, 1, or 2")
