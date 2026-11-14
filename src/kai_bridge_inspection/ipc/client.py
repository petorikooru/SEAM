"""Qt local-socket IPC client used by the desktop process."""

from __future__ import annotations

import json
from collections.abc import Mapping

from PySide6.QtCore import QObject, QTimer, Signal, Slot
from PySide6.QtNetwork import QLocalSocket

from kai_bridge_inspection.ipc.protocol import MAX_IPC_MESSAGE_BYTES, decode_line, encode_message, new_request


class IpcClient(QObject):
    connectedChanged = Signal(bool)
    responseReceived = Signal(str, bool, "QVariant", "QVariant")
    eventReceived = Signal(str, "QVariant")
    protocolError = Signal(str)

    def __init__(self, server_name: str, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._server_name = server_name
        self._socket = QLocalSocket(self)
        self._buffer = bytearray()
        self._pending: dict[str, str] = {}
        self._socket.connected.connect(lambda: self.connectedChanged.emit(True))
        self._socket.disconnected.connect(lambda: self.connectedChanged.emit(False))
        self._socket.readyRead.connect(self._read_available)
        self._socket.errorOccurred.connect(lambda _error: self.protocolError.emit(self._socket.errorString()))

    @property
    def connected(self) -> bool:
        return self._socket.state() == QLocalSocket.LocalSocketState.ConnectedState

    @Slot()
    def connect_to_server(self) -> None:
        if self.connected:
            return
        self._socket.abort()
        self._socket.connectToServer(self._server_name)

    @Slot()
    def disconnect_from_server(self) -> None:
        self._socket.disconnectFromServer()

    def send_command(self, command: str, payload: Mapping[str, object] | None = None) -> str:
        request = new_request(command, payload)
        request_id = request["request_id"]
        self._pending[request_id] = command
        if not self.connected:
            self.connect_to_server()
            if not self._socket.waitForConnected(500):
                self._pending.pop(request_id, None)
                self.protocolError.emit(self._socket.errorString())
                return ""
        self._socket.write(encode_message(request))
        self._socket.flush()
        QTimer.singleShot(5_000, lambda rid=request_id: self._timeout(rid))
        return request_id

    @Slot()
    def _read_available(self) -> None:
        self._buffer.extend(bytes(self._socket.readAll()))
        if len(self._buffer) > MAX_IPC_MESSAGE_BYTES:
            self._buffer.clear()
            self.protocolError.emit("IPC receive buffer exceeded 4 MiB")
            self._socket.abort()
            return
        while b"\n" in self._buffer:
            raw_line, _, remaining = self._buffer.partition(b"\n")
            self._buffer = bytearray(remaining)
            if not raw_line:
                continue
            try:
                message = decode_line(raw_line)
            except Exception as exc:
                self.protocolError.emit(str(exc))
                continue
            if isinstance(message.get("event"), str):
                payload = message.get("payload", {})
                self.eventReceived.emit(str(message["event"]), payload)
                continue
            request_id = str(message.get("request_id", ""))
            self._pending.pop(request_id, None)
            self.responseReceived.emit(
                request_id,
                bool(message.get("ok", False)),
                message.get("result") or {},
                message.get("error") or {},
            )

    def _timeout(self, request_id: str) -> None:
        command = self._pending.pop(request_id, None)
        if command is not None:
            self.protocolError.emit(f"IPC request timed out: {command}")
