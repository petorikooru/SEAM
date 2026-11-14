from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

pytest.importorskip("PySide6")

from PySide6.QtCore import QCoreApplication
from PySide6.QtNetwork import QLocalSocket

from kai_bridge_inspection.daemon.service import IPC_SERVER_NAME
from kai_bridge_inspection.ipc.protocol import decode_line, encode_message, new_request


def send(command: str) -> dict[str, object]:
    _app = QCoreApplication.instance() or QCoreApplication([])
    socket = QLocalSocket()
    socket.connectToServer(IPC_SERVER_NAME)
    assert socket.waitForConnected(3_000)
    socket.write(encode_message(new_request(command)))
    socket.flush()
    assert socket.waitForReadyRead(5_000)
    data = bytes(socket.readAll()).split(b"\n", 1)[0]
    return decode_line(data)


def test_daemon_start_status_and_shutdown(tmp_path: Path) -> None:
    environment = os.environ.copy()
    environment["KAI_BRIDGE_DATA_DIR"] = str(tmp_path)
    process = subprocess.Popen(
        [sys.executable, "-m", "kai_bridge_inspection.daemon"], env=environment
    )
    try:
        deadline = time.monotonic() + 8.0
        while time.monotonic() < deadline:
            try:
                status = send("get_status")
                break
            except AssertionError:
                time.sleep(0.2)
        else:
            pytest.fail("daemon did not expose IPC")
        assert status["ok"] is True
        assert send("stop_collection")["ok"] is True
        assert send("shutdown")["ok"] is True
        process.wait(timeout=10)
    finally:
        if process.poll() is None:
            process.kill()
