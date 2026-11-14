"""PySide6/QML desktop entry point."""

from __future__ import annotations

import ctypes
import os
import sys
from pathlib import Path

os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtGui import QIcon
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWidgets import QApplication

from kai_bridge_inspection.logging.configuration import configure_logging

from .bootstrap import bootstrap_desktop

PACKAGE_DIR = Path(__file__).resolve().parents[1]
QML_DIR     = PACKAGE_DIR / "qml"
ASSETS_DIR  = QML_DIR / "assets"


def main() -> int:
    if os.name == "nt":
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(  # type: ignore[attr-defined]
            "kai.bridgeinspection.desktop.5.2.0"
        )
    try:
        from PySide6.QtWebEngineQuick import QtWebEngineQuick
        QtWebEngineQuick.initialize()
    except ImportError:
        pass

    application = QApplication(sys.argv)
    services = bootstrap_desktop()
    configure_logging(
        services.paths.desktop_log,
        "desktop",
        debug=services.settings_repository.get_setting("debug_print", "false") == "true",
    )
    application.setApplicationName("KAI Bridge Inspection")
    application.setOrganizationName("KAI")
    application.setWindowIcon(QIcon(str(ASSETS_DIR / "KAI.svg")))

    engine = QQmlApplicationEngine()
    engine.addImportPath(str(PACKAGE_DIR))

    context = engine.rootContext()
    context.setContextProperty("backend", services.backend_controller)
    context.setContextProperty("daemonController", services.daemon_controller)
    context.setContextProperty("applicationController", services.application_controller)
    context.setContextProperty("settingsController", services.settings_controller)
    context.setContextProperty("dashboardController", services.dashboard_controller)
    context.setContextProperty("sparkplugController", services.sparkplug_controller)

    application.aboutToQuit.connect(services.backend_controller.stopServices)
    engine.loadFromModule("qml", "Main")
    if not engine.rootObjects():
        return 1
    return application.exec()
