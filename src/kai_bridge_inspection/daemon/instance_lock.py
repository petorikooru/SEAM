"""Cross-platform PID/identity lock with stale-lock detection."""

from __future__ import annotations

import json
import os
import sys
import time
import uuid
from pathlib import Path

from kai_bridge_inspection.domain.errors import DaemonLifecycleError


class DaemonInstanceLock:
    def __init__(self, lock_path: Path) -> None:
        self.lock_path = lock_path
        self.token = uuid.uuid4().hex
        self.acquired = False

    def acquire(self) -> None:
        self.lock_path.parent.mkdir(parents=True, exist_ok=True)
        for _attempt in range(2):
            try:
                descriptor = os.open(self.lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            except FileExistsError:
                if self._existing_daemon_is_valid():
                    raise DaemonLifecycleError("telemetry daemon is already running")
                try:
                    self.lock_path.unlink()
                except OSError as exc:
                    raise DaemonLifecycleError(f"cannot remove stale daemon lock: {exc}") from exc
                continue
            payload = {
                "pid": os.getpid(),
                "token": self.token,
                "started_at": time.time(),
                "python": sys.executable,
                "identity": "kai_bridge_inspection.daemon",
            }
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                json.dump(payload, handle)
                handle.flush()
                os.fsync(handle.fileno())
            self.acquired = True
            return
        raise DaemonLifecycleError("failed to acquire daemon lock")

    def release(self) -> None:
        if not self.acquired:
            return
        try:
            data = json.loads(self.lock_path.read_text(encoding="utf-8"))
            if data.get("token") == self.token:
                self.lock_path.unlink(missing_ok=True)
        except (OSError, json.JSONDecodeError):
            pass
        self.acquired = False

    def _existing_daemon_is_valid(self) -> bool:
        try:
            data = json.loads(self.lock_path.read_text(encoding="utf-8"))
            pid = int(data.get("pid", 0))
            identity = str(data.get("identity", ""))
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            return False
        if pid <= 0 or identity != "kai_bridge_inspection.daemon" or not _pid_exists(pid):
            return False
        if sys.platform.startswith("linux"):
            try:
                command_line = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\x00", b" ").decode(
                    "utf-8", errors="replace"
                )
            except OSError:
                return False
            return "kai_bridge_inspection.daemon" in command_line
        return True


def _pid_exists(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True
