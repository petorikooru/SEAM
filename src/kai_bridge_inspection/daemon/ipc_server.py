"""Local-only QLocalServer implementing the versioned JSON Lines protocol."""

from __future__ import annotations

import logging
from collections.abc import Callable, Mapping
from contextlib import suppress

from PySide6.QtCore import QObject, Signal
from PySide6.QtNetwork import QLocalServer, QLocalSocket

from kai_bridge_inspection.domain.errors import IpcProtocolError
from kai_bridge_inspection.ipc.messages import IpcCommandResult
from kai_bridge_inspection.ipc.protocol import (
    MAX_IPC_MESSAGE_BYTES,
    decode_line,
    encode_message,
    error_response,
    event_message,
    success_response,
    validate_request,
)

CommandHandler = Callable[[str, Mapping[str, object]], IpcCommandResult]
LOGGER = logging.getLogger(__name__)


class IpcServer(QObject):
    clientCountChanged = Signal(int)

    def __init__(self, server_name: str, command_handler: CommandHandler, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self.server_name = server_name
        self._command_handler = command_handler
        self._server = QLocalServer(self)
        self._clients: set[QLocalSocket] = set()
        self._buffers: dict[QLocalSocket, bytearray] = {}
        self._request_dispatch_depth = 0
        self._pending_broadcasts: list[bytes] = []
        self._server.newConnection.connect(self._accept_connections)

    @property
    def client_count(self) -> int:
        return len(self._clients)

    def listen(self) -> None:
        QLocalServer.removeServer(self.server_name)
        with suppress(AttributeError, TypeError):
            self._server.setSocketOptions(QLocalServer.SocketOption.UserAccessOption)
        if not self._server.listen(self.server_name):
            raise IpcProtocolError(f"cannot listen on local IPC endpoint: {self._server.errorString()}")

    def close(self) -> None:
        for socket in tuple(self._clients):
            socket.disconnectFromServer()
        self._server.close()
        QLocalServer.removeServer(self.server_name)

    def broadcast(self, event: str, payload: Mapping[str, object]) -> None:
        encoded = encode_message(event_message(event, payload))
        if self._request_dispatch_depth > 0:
            # Command handlers can synchronously emit status events. Queue those
            # events so the requesting client always receives its correlated
            # response before any unsolicited broadcast.
            self._pending_broadcasts.append(encoded)
            return
        self._write_broadcast(encoded)

    def _write_broadcast(self, encoded: bytes) -> None:
        for socket in tuple(self._clients):
            if socket.state() == QLocalSocket.LocalSocketState.ConnectedState:
                socket.write(encoded)
                socket.flush()

    def _flush_pending_broadcasts(self) -> None:
        pending = tuple(self._pending_broadcasts)
        self._pending_broadcasts.clear()
        for encoded in pending:
            self._write_broadcast(encoded)

    def _accept_connections(self) -> None:
        while self._server.hasPendingConnections():
            socket = self._server.nextPendingConnection()
            if socket is None:
                return
            self._clients.add(socket)
            self._buffers[socket] = bytearray()
            socket.readyRead.connect(lambda current=socket: self._read_client(current))
            socket.disconnected.connect(lambda current=socket: self._remove_client(current))
            self.clientCountChanged.emit(len(self._clients))

    def _read_client(self, socket: QLocalSocket) -> None:
        buffer = self._buffers.setdefault(socket, bytearray())
        buffer.extend(bytes(socket.readAll()))
        if len(buffer) > MAX_IPC_MESSAGE_BYTES:
            socket.write(encode_message(error_response("", "message_too_large", "IPC buffer exceeded 4 MiB")))
            socket.disconnectFromServer()
            return
        while b"\n" in buffer:
            raw_line, _, remaining = buffer.partition(b"\n")
            self._buffers[socket] = buffer = bytearray(remaining)
            if not raw_line:
                continue
            request_id = ""
            request_dispatched = False
            try:
                request = validate_request(decode_line(raw_line))
                request_id = request["request_id"]
                self._request_dispatch_depth += 1
                request_dispatched = True
                outcome = self._command_handler(request["command"], request["payload"])
                response = (
                    success_response(request_id, outcome.result)
                    if outcome.ok
                    else error_response(request_id, outcome.error_code, outcome.error_message)
                )
            except Exception as exc:
                LOGGER.warning("Rejected IPC request: %s", exc)
                response = error_response(request_id, "invalid_request", str(exc))
            socket.write(encode_message(response))
            socket.flush()
            if request_dispatched:
                self._request_dispatch_depth -= 1
                if self._request_dispatch_depth == 0:
                    self._flush_pending_broadcasts()

    def _remove_client(self, socket: QLocalSocket) -> None:
        self._clients.discard(socket)
        self._buffers.pop(socket, None)
        socket.deleteLater()
        self.clientCountChanged.emit(len(self._clients))
