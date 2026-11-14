"""QML device list model with stable roles."""

from __future__ import annotations

from dataclasses import dataclass

from PySide6.QtCore import QByteArray, QAbstractListModel, QModelIndex, Qt


@dataclass(frozen=True, slots=True)
class DeviceRow:
    device_id: str
    display_name: str
    online: bool
    metric_count: int


class DeviceListModel(QAbstractListModel):
    DeviceIdRole = int(Qt.ItemDataRole.UserRole) + 1
    DisplayNameRole = DeviceIdRole + 1
    OnlineRole = DeviceIdRole + 2
    MetricCountRole = DeviceIdRole + 3

    def __init__(self) -> None:
        super().__init__()
        self._rows: list[DeviceRow] = []

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:
        return 0 if parent.isValid() else len(self._rows)

    def data(self, index: QModelIndex, role: int = int(Qt.ItemDataRole.DisplayRole)) -> object:
        if not index.isValid() or not 0 <= index.row() < len(self._rows):
            return None
        row = self._rows[index.row()]
        return {
            self.DeviceIdRole: row.device_id,
            self.DisplayNameRole: row.display_name,
            self.OnlineRole: row.online,
            self.MetricCountRole: row.metric_count,
        }.get(role)

    def roleNames(self) -> dict[int, QByteArray]:
        return {
            self.DeviceIdRole: QByteArray(b"deviceId"),
            self.DisplayNameRole: QByteArray(b"displayName"),
            self.OnlineRole: QByteArray(b"online"),
            self.MetricCountRole: QByteArray(b"metricCount"),
        }

    def replace(self, rows: list[DeviceRow]) -> None:
        self.beginResetModel()
        self._rows = list(rows)
        self.endResetModel()
