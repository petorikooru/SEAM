"""Dashboard models composed for future direct QML usage."""

from __future__ import annotations

from PySide6.QtCore import Property, QObject, Signal

from kai_bridge_inspection.models.device_list_model import DeviceListModel
from kai_bridge_inspection.models.latest_telemetry_model import LatestTelemetryModel


class DashboardController(QObject):
    modelsChanged = Signal()

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._devices = DeviceListModel()
        self._latest = LatestTelemetryModel()

    @Property(QObject, constant=True)
    def devices(self) -> QObject:
        return self._devices

    @Property(QObject, constant=True)
    def latestTelemetry(self) -> QObject:
        return self._latest
