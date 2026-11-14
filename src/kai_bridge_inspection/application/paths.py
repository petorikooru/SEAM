"""Platform-aware application data paths without third-party dependencies."""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Final

APP_DIR_NAME: Final[str] = "KAI Bridge Inspection"
ENV_DATA_DIR: Final[str] = "KAI_BRIDGE_DATA_DIR"


@dataclass(frozen=True, slots=True)
class ApplicationPaths:
    data_dir    : Path
    settings_db : Path
    telemetry_db: Path
    desktop_log : Path
    daemon_log  : Path
    daemon_lock : Path

    @classmethod
    def resolve(cls) -> "ApplicationPaths":
        explicit = os.getenv(ENV_DATA_DIR, "").strip()
        if explicit:
            data_dir = Path(explicit).expanduser().resolve()
        elif sys.platform == "win32":
            data_dir = Path(os.getenv("LOCALAPPDATA", Path.home() / "AppData" / "Local")) / APP_DIR_NAME
        elif sys.platform == "darwin":
            data_dir = Path.home() / "Library" / "Application Support" / APP_DIR_NAME
        else:
            data_dir = Path(os.getenv("XDG_DATA_HOME", Path.home() / ".local" / "share")) / "kai-bridge-inspection"
        data_dir.mkdir(parents=True, exist_ok=True)
        try:
            data_dir.chmod(0o700)
        except OSError:
            pass

        return cls(
            data_dir=data_dir,
            settings_db=data_dir / "settings.db",
            telemetry_db=data_dir / "telemetry.db",
            desktop_log=data_dir / "desktop.log",
            daemon_log=data_dir / "daemon.log",
            daemon_lock=data_dir / "telemetry-daemon.lock",
        )
