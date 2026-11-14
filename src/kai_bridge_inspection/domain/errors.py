"""Typed application exception hierarchy."""

from __future__ import annotations


class IoTDashboardError(Exception):
    """Base exception for expected application failures."""


class ConfigurationError(IoTDashboardError):
    """Raised when persisted or proposed configuration is invalid."""


class MqttConnectionError(IoTDashboardError):
    """Raised when an MQTT connection cannot be established."""


class MqttSubscriptionError(IoTDashboardError):
    """Raised when one or more subscriptions fail."""


class TelemetryParseError(IoTDashboardError):
    """Raised when an incoming payload cannot be normalized."""


class SparkplugDecodeError(TelemetryParseError):
    """Raised when a Sparkplug B protobuf payload is malformed."""


class SparkplugStateError(IoTDashboardError):
    """Raised when Sparkplug state or alias rules are violated."""


class TelemetryStorageError(IoTDashboardError):
    """Raised when telemetry persistence or query operations fail."""


class IpcProtocolError(IoTDashboardError):
    """Raised for malformed, oversized, or unsupported IPC messages."""


class DaemonLifecycleError(IoTDashboardError):
    """Raised for invalid daemon lifecycle transitions."""
