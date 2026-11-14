"""Incremental latest-value model for controlled QML updates."""

from __future__ import annotations

from dataclasses import dataclass

from PySide6.QtCore import QByteArray, QAbstractListModel, QModelIndex, Qt


@dataclass(frozen=True, slots=True)
class LatestTelemetryRow:
    device_id: str
    metric_name: str
    value: object
    timestamp_ns: int
    unit: str
    quality: str


class LatestTelemetryModel(QAbstractListModel):
    DeviceIdRole = int(Qt.ItemDataRole.UserRole) + 1
    MetricNameRole = DeviceIdRole + 1
    ValueRole = DeviceIdRole + 2
    TimestampNsRole = DeviceIdRole + 3
    UnitRole = DeviceIdRole + 4
    QualityRole = DeviceIdRole + 5

    def __init__(self) -> None:
        super().__init__()
        self._rows: list[LatestTelemetryRow] = []
        self._index_by_key: dict[tuple[str, str], int] = {}

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:
        return 0 if parent.isValid() else len(self._rows)

    def data(self, index: QModelIndex, role: int = int(Qt.ItemDataRole.DisplayRole)) -> object:
        if not index.isValid() or not 0 <= index.row() < len(self._rows):
            return None
        row = self._rows[index.row()]
        return {
            self.DeviceIdRole: row.device_id,
            self.MetricNameRole: row.metric_name,
            self.ValueRole: row.value,
            self.TimestampNsRole: row.timestamp_ns,
            self.UnitRole: row.unit,
            self.QualityRole: row.quality,
        }.get(role)

    def roleNames(self) -> dict[int, QByteArray]:
        return {
            self.DeviceIdRole: QByteArray(b"deviceId"),
            self.MetricNameRole: QByteArray(b"metricName"),
            self.ValueRole: QByteArray(b"value"),
            self.TimestampNsRole: QByteArray(b"timestampNs"),
            self.UnitRole: QByteArray(b"unit"),
            self.QualityRole: QByteArray(b"quality"),
        }

    def upsert(self, row: LatestTelemetryRow) -> None:
        key = (row.device_id, row.metric_name)
        existing = self._index_by_key.get(key)
        if existing is None:
            insert_at = len(self._rows)
            self.beginInsertRows(QModelIndex(), insert_at, insert_at)
            self._rows.append(row)
            self._index_by_key[key] = insert_at
            self.endInsertRows()
            return
        self._rows[existing] = row
        index = self.index(existing, 0)
        self.dataChanged.emit(index, index, list(self.roleNames()))
