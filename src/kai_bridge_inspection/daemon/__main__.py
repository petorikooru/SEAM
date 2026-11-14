"""Independent telemetry daemon CLI."""

from __future__ import annotations

import argparse
import json
import sys

from PySide6.QtCore import QCoreApplication
from PySide6.QtNetwork import QLocalSocket

from kai_bridge_inspection.application.paths import ApplicationPaths
from kai_bridge_inspection.ipc.protocol import decode_line, encode_message, new_request
from kai_bridge_inspection.logging.configuration import configure_logging

from .instance_lock import DaemonInstanceLock
from .service import IPC_SERVER_NAME, DaemonService


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="KAI Bridge Inspection telemetry daemon")
    commands = parser.add_mutually_exclusive_group()
    commands.add_argument("--status", action="store_true", help="print daemon status")
    commands.add_argument("--start-collection", action="store_true", help="enable MQTT collection")
    commands.add_argument("--stop-collection", action="store_true", help="pause MQTT collection")
    commands.add_argument("--reload-settings", action="store_true", help="reload saved settings")
    commands.add_argument("--shutdown", action="store_true", help="gracefully stop the daemon")
    return parser


def send_existing_daemon_command(command: str) -> int:
    app = QCoreApplication.instance() or QCoreApplication(sys.argv[:1])
    socket = QLocalSocket()
    socket.connectToServer(IPC_SERVER_NAME)
    if not socket.waitForConnected(1_500):
        print(json.dumps({"ok": False, "error": "daemon is not running"}, indent=2))
        return 1
    socket.write(encode_message(new_request(command)))
    socket.flush()
    if not socket.waitForReadyRead(5_000):
        print(json.dumps({"ok": False, "error": "daemon command timed out"}, indent=2))
        return 2
    data = bytearray(bytes(socket.readAll()))
    while b"\n" not in data and socket.waitForReadyRead(250):
        data.extend(bytes(socket.readAll()))
    line = bytes(data).split(b"\n", 1)[0]
    message = decode_line(line)
    print(json.dumps(message, indent=2, ensure_ascii=False))
    socket.disconnectFromServer()
    del app
    return 0 if message.get("ok") else 3


def main() -> int:
    arguments = build_parser().parse_args()
    command = ""
    if arguments.status:
        command = "get_status"
    elif arguments.start_collection:
        command = "start_collection"
    elif arguments.stop_collection:
        command = "stop_collection"
    elif arguments.reload_settings:
        command = "reload_settings"
    elif arguments.shutdown:
        command = "shutdown"
    if command:
        return send_existing_daemon_command(command)

    paths = ApplicationPaths.resolve()
    configure_logging(
        paths.daemon_log,
        "telemetry-daemon",
        debug=settings_debug_flag(paths),
    )
    lock = DaemonInstanceLock(paths.daemon_lock)
    try:
        lock.acquire()
    except Exception as exc:
        print(f"Unable to start telemetry daemon: {exc}", file=sys.stderr)
        return 4
    app = QCoreApplication(sys.argv)
    app.setApplicationName("KAI Bridge Inspection Telemetry Daemon")
    service = DaemonService(paths)
    app.aboutToQuit.connect(service.shutdown)
    try:
        return app.exec()
    finally:
        lock.release()


def settings_debug_flag(paths: ApplicationPaths) -> bool:
    """Read debug mode without making daemon startup depend on full service construction."""
    try:
        from kai_bridge_inspection.settings.repository import SettingsRepository

        return SettingsRepository(paths.settings_db).get_setting("debug_print", "false") == "true"
    except Exception:
        return False


if __name__ == "__main__":
    raise SystemExit(main())
