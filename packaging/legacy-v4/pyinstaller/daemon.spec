# -*- mode: python ; coding: utf-8 -*-
from pathlib import Path

project_root = Path(SPECPATH).resolve().parent.parent
source_root = project_root / "src"
icon_file = source_root / "kai_bridge_inspection" / "qml" / "assets" / "KAI.ico"

analysis = Analysis(
    [str(project_root / "packaging" / "entrypoints" / "daemon_entry.py")],
    pathex=[str(source_root)],
    binaries=[],
    datas=[],
    hiddenimports=[
        "PySide6.QtCore",
        "PySide6.QtNetwork",
        "google.protobuf",
        "paho.mqtt.client",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        "PySide6.QtCharts",
        "PySide6.QtLocation",
        "PySide6.QtQml",
        "PySide6.QtQuick",
        "PySide6.QtWebEngineCore",
        "PySide6.QtWebEngineQuick",
        "PySide6.QtWidgets",
        "tkinter",
        "unittest",
    ],
    noarchive=False,
    optimize=1,
)
pyz = PYZ(analysis.pure)

exe = EXE(
    pyz,
    analysis.scripts,
    analysis.binaries,
    analysis.datas,
    [],
    name="kai-bridge-telemetry-daemon",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=str(icon_file),
)
