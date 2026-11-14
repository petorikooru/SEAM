# -*- mode: python ; coding: utf-8 -*-
from pathlib import Path

project_root = Path(SPECPATH).resolve().parent.parent
source_root = project_root / "src"
package_root = source_root / "kai_bridge_inspection"
qml_root = package_root / "qml"
icon_file = qml_root / "assets" / "KAI.ico"

qml_datas = [(str(qml_root), "kai_bridge_inspection/qml")]

hidden_imports = [
    "PySide6.QtCharts",
    "PySide6.QtLocation",
    "PySide6.QtNetwork",
    "PySide6.QtPositioning",
    "PySide6.QtQml",
    "PySide6.QtQuick",
    "PySide6.QtQuickControls2",
    "PySide6.QtWebChannel",
    "PySide6.QtWebEngineCore",
    "PySide6.QtWebEngineQuick",
    "PySide6.QtWebSockets",
    "PySide6.QtWidgets",
]

analysis = Analysis(
    [str(project_root / "main.py")],
    pathex=[str(source_root)],
    binaries=[],
    datas=qml_datas,
    hiddenimports=hidden_imports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["tkinter", "unittest"],
    noarchive=False,
    optimize=1,
)
pyz = PYZ(analysis.pure)

exe = EXE(
    pyz,
    analysis.scripts,
    [],
    exclude_binaries=True,
    name="KAI Bridge Inspection",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=str(icon_file),
)

collect = COLLECT(
    exe,
    analysis.binaries,
    analysis.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="KAI Bridge Inspection",
)
