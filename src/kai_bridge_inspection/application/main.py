"""PySide6/QML desktop entry point."""

from __future__ import annotations

import ctypes
import os
import sys
from pathlib import Path

os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PySide6.QtGui import QFontDatabase, QIcon
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWidgets import QApplication

from kai_bridge_inspection.logging.configuration import configure_logging

from .bootstrap import bootstrap_desktop

PACKAGE_DIR = Path(__file__).resolve().parents[1]
QML_DIR     = PACKAGE_DIR / "qml"
ASSETS_DIR  = QML_DIR / "assets"


def _register_optional_icon_fonts() -> tuple[str, ...]:
    """Register user-provided Nerd Fonts before QML singletons are created.

    Set KAI_NERD_FONT_PATH to one or more .ttf/.otf files separated by the
    platform path separator, or place a font in qml/assets/fonts locally.
    The distributed project intentionally contains no font binary.
    """
    candidates: list[Path] = []
    configured = os.environ.get("KAI_NERD_FONT_PATH", "")
    if configured:
        candidates.extend(Path(value).expanduser() for value in configured.split(os.pathsep) if value)

    local_font_dir = ASSETS_DIR / "fonts"
    if local_font_dir.is_dir():
        candidates.extend(sorted(local_font_dir.glob("*.ttf")))
        candidates.extend(sorted(local_font_dir.glob("*.otf")))

    families: list[str] = []
    seen: set[Path] = set()
    for candidate in candidates:
        try:
            resolved = candidate.resolve()
        except OSError:
            continue
        if resolved in seen or not resolved.is_file():
            continue
        seen.add(resolved)
        font_id = QFontDatabase.addApplicationFont(str(resolved))
        if font_id >= 0:
            families.extend(QFontDatabase.applicationFontFamilies(font_id))
    return tuple(dict.fromkeys(families))


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
    _register_optional_icon_fonts()
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
