"""Desktop Sparkplug diagnostics controller."""

from __future__ import annotations

from PySide6.QtCore import QObject, Signal, Slot

from .daemon_controller import DaemonController


class SparkplugController(QObject):
    stateRequested = Signal()

    def __init__(self, daemon_controller: DaemonController, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._daemon_controller = daemon_controller

    @Slot()
    def refresh(self) -> None:
        self._daemon_controller.refreshStatus()
        self.stateRequested.emit()
