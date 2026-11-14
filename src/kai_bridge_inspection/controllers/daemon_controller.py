"""Node-RED stream controller exposed through the legacy daemon QML contract.

The class name and QML properties are retained to avoid a broad UI migration.
No MQTT client, Sparkplug decoder, parser daemon, or local IPC server is used by
the desktop runtime. Node-RED owns those responsibilities and publishes only
canonical JSON over named WebSocket endpoints.
"""

from __future__ import annotations

import logging
from collections.abc import Sequence
from functools import partial
from pathlib import Path
from urllib.parse import urlsplit

from PySide6.QtCore import Property, QObject, QTimer, QUrl, Signal, Slot
from PySide6.QtNetwork import QAbstractSocket
from PySide6.QtWebSockets import QWebSocket, QWebSocketProtocol

from kai_bridge_inspection.domain.enums import DropPolicy
from kai_bridge_inspection.domain.models import TelemetryPoint
from kai_bridge_inspection.ipc.protocol import telemetry_point_to_dict
from kai_bridge_inspection.nodered.payload import NodeRedPayloadError, parse_node_red_payload
from kai_bridge_inspection.settings.repository import SettingsRepository
from kai_bridge_inspection.telemetry.batch_writer import TelemetryBatchWriter
from kai_bridge_inspection.telemetry.sqlite_repository import SQLiteTelemetryRepository

LOGGER = logging.getLogger(__name__)


class DaemonController(QObject):
    """Connect Node-RED WebSocket Out endpoints to the existing widget facade."""

    stateChanged = Signal()
    statusChanged = Signal("QVariant")
    telemetryBatch = Signal("QVariant")
    errorOccurred = Signal(str)
    _batchCommitted = Signal(object)

    def __init__(
        self,
        settings: SettingsRepository,
        telemetry_database: Path,
        parent: QObject | None = None,
    ) -> None:
        super().__init__(parent)
        self._settings = settings
        self._state = "STOPPED"
        self._running = False
        self._collection_enabled = False
        self._mqtt_connected = False  # compatibility name: means a Node-RED stream is connected
        self._ipc_connected = False  # compatibility name: no longer used
        self._last_error = ""
        self._sockets: dict[str, QWebSocket] = {}
        self._connected_endpoints: set[str] = set()
        self._server_config: tuple[str, str] | None = None
        self._endpoint_streams: dict[str, tuple[str, frozenset[str]]] = {}
        self._repository = SQLiteTelemetryRepository(telemetry_database)
        self._writer = TelemetryBatchWriter(
            self._repository,
            queue_capacity=2_048,
            batch_size=1_000,
            flush_interval_seconds=0.35,
            drop_policy=DropPolicy.DROP_NEWEST,
            on_batch_written=self._on_batch_written,
        )
        self._batchCommitted.connect(self._publish_committed_batch)
        self._reconnect_timer = QTimer(self)
        self._reconnect_timer.setInterval(3_000)
        self._reconnect_timer.timeout.connect(self._ensure_connections)
        self._reconnect_timer.start()
        if self._settings.get_setting("data_gathering", "true") == "true":
            QTimer.singleShot(0, self.startCollection)

    @Property(str, notify=stateChanged)
    def state(self) -> str:
        return self._state

    @Property(bool, notify=stateChanged)
    def running(self) -> bool:
        return self._running

    @Property(bool, notify=stateChanged)
    def collectionEnabled(self) -> bool:
        return self._collection_enabled

    @Property(bool, notify=stateChanged)
    def mqttConnected(self) -> bool:
        """Compatibility property: true when at least one Node-RED endpoint is live."""
        return self._mqtt_connected

    @Property(bool, notify=stateChanged)
    def ipcConnected(self) -> bool:
        return self._ipc_connected

    @Property(str, notify=stateChanged)
    def lastError(self) -> str:
        return self._last_error

    @Property(int, notify=stateChanged)
    def connectedEndpointCount(self) -> int:
        return len(self._connected_endpoints)

    @Slot(str, result=bool)
    def isEndpointConnected(self, endpoint: str) -> bool:
        normalized = endpoint.strip().strip("/")
        return bool(normalized and normalized in self._connected_endpoints)

    @Slot()
    def startDaemon(self) -> None:
        self.startCollection()

    @Slot()
    def stopDaemon(self) -> None:
        self._collection_enabled = False
        self._close_sockets()
        self._set_state("STOPPED", running=False, connected=False)

    @Slot()
    def restartDaemon(self) -> None:
        self._close_sockets()
        self.startCollection()

    @Slot()
    def startCollection(self) -> None:
        self._collection_enabled = True
        self._running = True
        self._state = "CONNECTING"
        self._last_error = ""
        self.stateChanged.emit()
        self._ensure_connections()

    @Slot()
    def pauseCollection(self) -> None:
        self._collection_enabled = False
        self._close_sockets()
        self._set_state("PAUSED", running=True, connected=False)

    @Slot()
    def resumeCollection(self) -> None:
        self.startCollection()

    @Slot()
    def reloadSettings(self) -> None:
        if self._collection_enabled:
            self._ensure_connections()
        else:
            self.refreshStatus()

    @Slot()
    def refreshStatus(self) -> None:
        self.statusChanged.emit(self._status_snapshot())

    def close(self) -> None:
        self._collection_enabled = False
        self._close_sockets()
        self._writer.flush(timeout_seconds=5.0)
        self._writer.stop(timeout_seconds=5.0)
        self._repository.close()

    @Slot()
    def _ensure_connections(self) -> None:
        if not self._collection_enabled:
            return
        server_config = (
            self._settings.get_setting("nr_address", "127.0.0.1"),
            self._settings.get_setting("nr_port", "1880"),
        )
        if server_config != self._server_config:
            self._close_sockets()
            self._server_config = server_config
        streams = {
            path: binding for path, binding in self._settings.list_node_red_sensor_streams().items()
            if binding[0]
        }
        for endpoint in self._sockets.keys() - streams.keys():
            self._remove_socket(endpoint)
        for endpoint, binding in streams.items():
            if self._endpoint_streams.get(endpoint) != binding and endpoint in self._sockets:
                self._remove_socket(endpoint)
            if endpoint not in self._sockets:
                self._sockets[endpoint] = self._create_socket(endpoint)
        self._endpoint_streams = streams
        if not streams:
            self._fail("No Node-RED WebSocket paths are configured")
            return
        for endpoint, socket in tuple(self._sockets.items()):
            if socket.state() != QAbstractSocket.SocketState.UnconnectedState:
                continue
            try:
                endpoint_url = self._endpoint_url(endpoint)
            except ValueError as exc:
                self._fail(f"Invalid Node-RED endpoint configuration: {exc}")
                return
            socket.open(endpoint_url)
        state = "RUNNING" if self._connected_endpoints else "CONNECTING"
        if self._state != state:
            self._state = state
            self.stateChanged.emit()
        self.refreshStatus()

    def _create_socket(self, endpoint: str) -> QWebSocket:
        socket = QWebSocket("", QWebSocketProtocol.Version.VersionLatest, self)
        socket.connected.connect(partial(self._on_connected, endpoint))
        socket.disconnected.connect(partial(self._on_disconnected, endpoint))
        socket.textMessageReceived.connect(partial(self._on_text_message, endpoint))
        socket.binaryMessageReceived.connect(partial(self._on_binary_message, endpoint))
        socket.errorOccurred.connect(partial(self._on_socket_error, endpoint))
        return socket

    def _endpoint_url(self, endpoint: str) -> QUrl:
        raw_host = self._settings.get_setting("nr_address", "127.0.0.1").strip()
        port = self._settings.get_setting("nr_port", "1880").strip() or "1880"
        parsed = urlsplit(raw_host if "://" in raw_host else f"http://{raw_host}")
        scheme = "wss" if parsed.scheme in {"https", "wss"} else "ws"
        host = parsed.hostname or "127.0.0.1"
        configured_port = parsed.port or int(port)
        if not 1 <= configured_port <= 65_535:
            raise ValueError("port must be between 1 and 65535")
        base_path = parsed.path.strip("/")
        path = "/".join(part for part in (base_path, endpoint.strip("/")) if part)
        return QUrl(f"{scheme}://{host}:{configured_port}/{path}")

    def _on_connected(self, endpoint: str) -> None:
        self._connected_endpoints.add(endpoint)
        self._mqtt_connected = True
        self._running = True
        self._state = "RUNNING"
        self._last_error = ""
        self.stateChanged.emit()
        self.refreshStatus()

    def _on_disconnected(self, endpoint: str) -> None:
        self._connected_endpoints.discard(endpoint)
        self._mqtt_connected = bool(self._connected_endpoints)
        if self._collection_enabled:
            self._state = "RUNNING" if self._mqtt_connected else "RECONNECTING"
        else:
            self._state = "PAUSED"
        self.stateChanged.emit()
        self.refreshStatus()

    def _on_text_message(self, endpoint: str, message: str) -> None:
        self._ingest_message(endpoint, message)

    def _on_binary_message(self, endpoint: str, message: object) -> None:
        self._ingest_message(endpoint, bytes(message))

    def _ingest_message(self, endpoint: str, message: str | bytes) -> None:
        binding = self._endpoint_streams.get(endpoint)
        if not self._collection_enabled or binding is None:
            return
        try:
            points = parse_node_red_payload(message, endpoint)
        except NodeRedPayloadError as exc:
            self._last_error = f"{endpoint}: {exc}"
            self.errorOccurred.emit(self._last_error)
            self.stateChanged.emit()
            return
        expected_device, allowed_metrics = binding
        if any(point.device_id != expected_device for point in points):
            self._last_error = f"{endpoint}: expected device_id {expected_device!r}"
        elif allowed_metrics and any(point.metric_name not in allowed_metrics for point in points):
            self._last_error = f"{endpoint}: expected metric_name in {sorted(allowed_metrics)!r}"
        else:
            if self._writer.submit(points):
                return
            self._last_error = "Telemetry writer queue is full; newest Node-RED batch was dropped"
        self.errorOccurred.emit(self._last_error)
        self.stateChanged.emit()

    def _on_batch_written(self, points: Sequence[TelemetryPoint]) -> None:
        self._batchCommitted.emit(tuple(points[-1_000:]))

    @Slot(object)
    def _publish_committed_batch(self, raw_points: object) -> None:
        points = raw_points if isinstance(raw_points, tuple) else tuple()
        payload = {
            "points": [
                telemetry_point_to_dict(point)
                for point in points
                if isinstance(point, TelemetryPoint)
            ]
        }
        if payload["points"]:
            self.telemetryBatch.emit(payload)

    def _on_socket_error(self, endpoint: str, _error: object) -> None:
        socket = self._sockets.get(endpoint)
        detail = socket.errorString() if socket is not None else "WebSocket error"
        self._last_error = f"{endpoint}: {detail}"
        if self._collection_enabled and not self._connected_endpoints:
            self._state = "RECONNECTING"
        self.errorOccurred.emit(self._last_error)
        self.stateChanged.emit()
        self.refreshStatus()

    def _remove_socket(self, endpoint: str) -> None:
        socket = self._sockets.pop(endpoint)
        socket.blockSignals(True)
        socket.abort()
        socket.deleteLater()
        self._connected_endpoints.discard(endpoint)
        self._mqtt_connected = bool(self._connected_endpoints)

    def _close_sockets(self) -> None:
        for endpoint in tuple(self._sockets):
            self._remove_socket(endpoint)

    def _fail(self, message: str) -> None:
        self._last_error = message
        self._state = "FAILED"
        self._running = False
        self._mqtt_connected = False
        self.errorOccurred.emit(message)
        self.stateChanged.emit()
        self.refreshStatus()

    def _set_state(self, state: str, *, running: bool, connected: bool) -> None:
        self._state = state
        self._running = running
        self._mqtt_connected = connected
        self.stateChanged.emit()
        self.refreshStatus()

    def _status_snapshot(self) -> dict[str, object]:
        writer = self._writer.snapshot()
        configured_count = len(self._settings.list_node_red_sensor_endpoints())
        return {
            "daemon_state": self._state,
            "process_running": self._running,
            "collection_enabled": self._collection_enabled,
            "mqtt_connected": self._mqtt_connected,
            "node_red_connected": self._mqtt_connected,
            "node_red_endpoints_connected": len(self._connected_endpoints),
            "node_red_endpoints_configured": configured_count,
            "database_writer_healthy": writer.healthy,
            "queue_depth": writer.queue_depth,
            "points_written": writer.points_written,
            "last_error": self._last_error,
        }
