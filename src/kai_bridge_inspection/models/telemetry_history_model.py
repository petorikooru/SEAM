"""Bounded historical telemetry list model."""

from __future__ import annotations

from dataclasses import dataclass

from PySide6.QtCore import QByteArray, QAbstractListModel, QModelIndex, Qt


@dataclass(frozen=True, slots=True)
class HistoryRow:
    timestamp_ns: int
    value: object


class TelemetryHistoryModel(QAbstractListModel):
    TimestampNsRole = int(Qt.ItemDataRole.UserRole) + 1
    ValueRole = TimestampNsRole + 1

    def __init__(self) -> None:
        super().__init__()
        self._rows: list[HistoryRow] = []

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:
        return 0 if parent.isValid() else len(self._rows)

    def data(self, index: QModelIndex, role: int = int(Qt.ItemDataRole.DisplayRole)) -> object:
        if not index.isValid() or not 0 <= index.row() < len(self._rows):
            return None
        row = self._rows[index.row()]
        return {self.TimestampNsRole: row.timestamp_ns, self.ValueRole: row.value}.get(role)

    def roleNames(self) -> dict[int, QByteArray]:
        return {
            self.TimestampNsRole: QByteArray(b"timestampNs"),
            self.ValueRole: QByteArray(b"value"),
        }

    def replace(self, rows: list[HistoryRow]) -> None:
        self.beginResetModel()
        self._rows = list(rows)
        self.endResetModel()
