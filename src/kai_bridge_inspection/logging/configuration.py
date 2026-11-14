"""Standard-library logging configuration for desktop and daemon processes."""

from __future__ import annotations

import logging
import logging.handlers
from pathlib import Path


class UtcFormatter(logging.Formatter):
    converter = __import__("time").gmtime


def configure_logging(log_path: Path, process_name: str, debug: bool = False) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    level = logging.DEBUG if debug else logging.INFO
    formatter = UtcFormatter(
        fmt=f"%(asctime)sZ {process_name} %(processName)s %(threadName)s %(name)s %(levelname)s %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )
    root = logging.getLogger()
    root.setLevel(level)
    root.handlers.clear()
    console = logging.StreamHandler()
    console.setFormatter(formatter)
    root.addHandler(console)
    rotating = logging.handlers.RotatingFileHandler(
        log_path, maxBytes=5 * 1024 * 1024, backupCount=3, encoding="utf-8"
    )
    rotating.setFormatter(formatter)
    root.addHandler(rotating)
