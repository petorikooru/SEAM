"""Small application metadata controller."""

from __future__ import annotations

from PySide6.QtCore import Property, QObject, Signal

from kai_bridge_inspection import __version__


class ApplicationController(QObject):
    changed = Signal()

    @Property(str, constant=True)
    def applicationName(self) -> str:
        return "KAI Bridge Inspection"

    @Property(str, constant=True)
    def version(self) -> str:
        return __version__
