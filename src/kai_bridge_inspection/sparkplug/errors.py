"""Compatibility exports for Sparkplug-specific exceptions."""

from kai_bridge_inspection.domain.errors import SparkplugDecodeError, SparkplugStateError

__all__ = ["SparkplugDecodeError", "SparkplugStateError"]
