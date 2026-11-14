"""Typed settings facade for future QML migration away from the compatibility controller."""

from __future__ import annotations

from PySide6.QtCore import QObject, Signal, Slot

from kai_bridge_inspection.settings.repository import SettingsRepository


class SettingsController(QObject):
    settingChanged = Signal(str, str)

    def __init__(self, repository: SettingsRepository, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._repository = repository

    @Slot(str, str, result=str)
    def value(self, key: str, default: str = "") -> str:
        return self._repository.get_setting(key, default)

    @Slot(str, str)
    def setValue(self, key: str, value: str) -> None:
        self._repository.set_setting(key, value)
        self.settingChanged.emit(key, value)
