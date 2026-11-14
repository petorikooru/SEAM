"""Sparkplug session facade."""

from __future__ import annotations

from .state import SparkplugStateRegistry


class SparkplugSession:
    def __init__(self) -> None:
        self.registry = SparkplugStateRegistry()

    def reset_after_reconnect(self) -> None:
        self.registry.reset()
