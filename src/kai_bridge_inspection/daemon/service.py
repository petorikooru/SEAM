"""Telemetry daemon orchestration: MQTT, parsing, Sparkplug state, storage, and IPC."""

from __future__ import annotations

import logging
import queue
import threading
import time
from collections.abc import Mapping, Sequence
from contextlib import suppress
from dataclasses import dataclass
from typing import Final

from PySide6.QtCore import QCoreApplication, QObject, QTimer, Signal, Slot

from kai_bridge_inspection.application.paths import ApplicationPaths
from kai_bridge_inspection.domain.enums import DaemonState, DropPolicy
from kai_bridge_inspection.domain.models import HistoricalQuery, IncomingMqttMessage, TelemetryPoint
from kai_bridge_inspection.ipc.messages import IpcCommandResult
from kai_bridge_inspection.ipc.protocol import telemetry_point_to_dict
from kai_bridge_inspection.mqtt.client import PahoMqttClientService
from kai_bridge_inspection.mqtt.payload_parser import JsonTelemetryParser, TopicParserRouter
from kai_bridge_inspection.settings.repository import SettingsRepository
from kai_bridge_inspection.settings.secrets import EnvironmentSecretProvider
from kai_bridge_inspection.settings.service import SettingsService
from kai_bridge_inspection.sparkplug.parser import SparkplugTelemetryParser
from kai_bridge_inspection.telemetry.batch_writer import TelemetryBatchWriter
from kai_bridge_inspection.telemetry.sqlite_repository import SQLiteTelemetryRepository

from . import IPC_SERVER_NAME
from .health import StatisticsTracker
from .ipc_server import IpcServer
from .lifecycle import DaemonLifecycle

LOGGER = logging.getLogger(__name__)
_PROCESS_QUEUE_CAPACITY: Final[int] = 2_048
_PROCESS_SENTINEL = object()
_REJECTION_LOG_INTERVAL_SECONDS: Final[float] = 60.0


@dataclass(slots=True)
class _RejectionLogState:
    last_logged_monotonic: float = 0.0
    suppressed: int = 0


class _RejectionLogLimiter:
    """Rate-limit repeated parser warnings without hiding counters or DB records."""

    def __init__(self, interval_seconds: float = _REJECTION_LOG_INTERVAL_SECONDS) -> None:
        self._interval_seconds = interval_seconds
        self._states: dict[tuple[str, str], _RejectionLogState] = {}

    def check(self, topic: str, error: Exception) -> tuple[bool, int]:
        levels = topic.split("/")
        topic_family = "/".join(levels[:3]) if len(levels) >= 3 else topic
        signature = (topic_family, type(error).__name__)
        now = time.monotonic()
        state = self._states.setdefault(signature, _RejectionLogState())
        if state.last_logged_monotonic == 0.0 or now - state.last_logged_monotonic >= self._interval_seconds:
            suppressed = state.suppressed
            state.last_logged_monotonic = now
            state.suppressed = 0
            return True, suppressed
        state.suppressed += 1
        return False, state.suppressed


class DaemonService(QObject):
    """Own all high-frequency telemetry resources outside the GUI process."""

    mqttStateChanged = Signal(int, bool, str)
    telemetryCommitted = Signal(object)
    lifecycleChanged = Signal(str)

    def __init__(self, paths: ApplicationPaths, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self.paths = paths
        self.settings_repository = SettingsRepository(paths.settings_db)
        self.settings_service = SettingsService(self.settings_repository)
        self.telemetry_repository = SQLiteTelemetryRepository(paths.telemetry_db)
        self.statistics = StatisticsTracker()
        self.lifecycle = DaemonLifecycle(on_change=lambda state: self.lifecycleChanged.emit(state.value))
        self.lifecycle.transition(DaemonState.STARTING)
        self._collection_enabled = False
        self._shutdown_started = False
        self._last_error = ""
        self._mqtt_connected: dict[int, bool] = {}
        self._mqtt_messages: queue.Queue[IncomingMqttMessage | object] = queue.Queue(
            maxsize=_PROCESS_QUEUE_CAPACITY
        )
        self._processor_stop = threading.Event()
        self._rejection_log_limiter = _RejectionLogLimiter()
        self._processor_thread = threading.Thread(
            target=self._processing_loop, name="TelemetryProcessor", daemon=True
        )
        self._sparkplug_parser = SparkplugTelemetryParser(
            namespace=self.settings_repository.get_setting("sparkplug_namespace", "spBv1.0")
        )
        self._router = TopicParserRouter([self._sparkplug_parser, JsonTelemetryParser()])
        self._writer = TelemetryBatchWriter(
            self.telemetry_repository,
            queue_capacity=2_048,
            batch_size=1_000,
            flush_interval_seconds=0.5,
            drop_policy=DropPolicy.DROP_NEWEST,
            on_batch_written=self._on_writer_batch,
        )
        self._mqtt_clients: dict[int, PahoMqttClientService] = {}
        self._processor_thread.start()
        self.ipc_server = IpcServer(IPC_SERVER_NAME, self.handle_command, self)
        self.ipc_server.listen()
        self.mqttStateChanged.connect(self._apply_mqtt_state)
        self.telemetryCommitted.connect(self._broadcast_telemetry)
        self.lifecycleChanged.connect(lambda _state: self.broadcast_status())
        self._status_timer = QTimer(self)
        self._status_timer.setInterval(1_000)
        self._status_timer.timeout.connect(self.broadcast_status)
        self._status_timer.start()
        self._retention_timer = QTimer(self)
        self._retention_timer.setInterval(60 * 60 * 1_000)
        self._retention_timer.timeout.connect(self._purge_retention)
        self._retention_timer.start()
        self.lifecycle.transition(DaemonState.IDLE)
        try:
            config = self.settings_service.effective_daemon_configuration()
            if config.collection_enabled:
                QTimer.singleShot(0, self.start_collection)
        except Exception as exc:
            self._fail(str(exc))

    @Slot()
    def start_collection(self) -> None:
        if self.lifecycle.state in {DaemonState.RUNNING, DaemonState.CONNECTING, DaemonState.RECONNECTING}:
            return
        try:
            if self.lifecycle.state == DaemonState.FAILED:
                self.lifecycle.transition(DaemonState.STARTING)
                self.lifecycle.transition(DaemonState.IDLE)
            config = self.settings_service.effective_daemon_configuration()
            self._sparkplug_parser.namespace = config.sparkplug_namespace
            self._collection_enabled = True
            self.lifecycle.transition(DaemonState.CONNECTING)
            self._disconnect_mqtt_clients()
            self._mqtt_connected.clear()
            if not config.brokers:
                self.lifecycle.transition(DaemonState.PAUSED)
                self._last_error = "No enabled MQTT broker profiles are configured"
                self.broadcast_status()
                return
            secret_provider = EnvironmentSecretProvider(self.paths.data_dir / ".env")
            for profile in config.brokers:
                client = PahoMqttClientService(
                    message_handler=self._enqueue_message,
                    state_handler=lambda connected, detail, broker_id=profile.broker_id: self.mqttStateChanged.emit(
                        broker_id, connected, detail
                    ),
                    secret_provider=secret_provider,
                )
                self._mqtt_clients[profile.broker_id] = client
                self._mqtt_connected[profile.broker_id] = False
                client.connect(profile)
            self._last_error = ""
        except Exception as exc:
            self._fail(str(exc))

    @Slot()
    def stop_collection(self) -> None:
        if self.lifecycle.state in {DaemonState.STOPPING, DaemonState.STOPPED}:
            return
        self._collection_enabled = False
        self._disconnect_mqtt_clients()
        target = DaemonState.PAUSED if self.lifecycle.state != DaemonState.IDLE else DaemonState.IDLE
        with suppress(Exception):
            self.lifecycle.transition(target)
        self.broadcast_status()

    @Slot()
    def reload_settings(self) -> None:
        was_enabled = self._collection_enabled
        self.stop_collection()
        if was_enabled:
            self.start_collection()

    @Slot()
    def shutdown(self) -> None:
        if self._shutdown_started:
            return
        self._shutdown_started = True
        if self.lifecycle.state not in {DaemonState.STOPPING, DaemonState.STOPPED}:
            with suppress(Exception):
                self.lifecycle.transition(DaemonState.STOPPING)
        self._collection_enabled = False
        self._disconnect_mqtt_clients()
        self._processor_stop.set()
        with suppress(queue.Full):
            self._mqtt_messages.put(_PROCESS_SENTINEL, timeout=0.2)
        self._processor_thread.join(timeout=5.0)
        self._writer.flush(timeout_seconds=10.0)
        self._writer.stop(timeout_seconds=10.0)
        self.telemetry_repository.checkpoint(truncate=True)
        self.ipc_server.close()
        with suppress(Exception):
            self.lifecycle.transition(DaemonState.STOPPED)
        QCoreApplication.quit()

    def handle_command(self, command: str, payload: Mapping[str, object]) -> IpcCommandResult:
        try:
            if command == "ping":
                return IpcCommandResult(True, {"pong": True, "timestamp_ns": time.time_ns()})
            if command == "get_status":
                return IpcCommandResult(True, self.status_snapshot())
            if command == "start_collection":
                self.start_collection()
                return IpcCommandResult(True, self.status_snapshot())
            if command == "stop_collection":
                self.stop_collection()
                return IpcCommandResult(True, self.status_snapshot())
            if command == "reload_settings":
                self.reload_settings()
                return IpcCommandResult(True, self.status_snapshot())
            if command == "get_devices":
                return IpcCommandResult(True, {"devices": list(self.telemetry_repository.list_devices())})
            if command == "get_latest_values":
                device_id = _required_string(payload, "device_id")
                limit = _bounded_int(payload.get("limit"), 200, 1, 2_000)
                points = self.telemetry_repository.latest_values(device_id, limit)
                return IpcCommandResult(
                    True, {"points": [telemetry_point_to_dict(point) for point in points]}
                )
            if command == "query_telemetry":
                query = HistoricalQuery(
                    start_timestamp_ns=_bounded_int(payload.get("start_timestamp_ns"), 0, 0, 9_223_372_036_854_775_807),
                    end_timestamp_ns=_bounded_int(payload.get("end_timestamp_ns"), 0, 0, 9_223_372_036_854_775_807),
                    device_id=_optional_string(payload.get("device_id")),
                    metric_name=_optional_string(payload.get("metric_name")),
                    mqtt_topic=_optional_string(payload.get("mqtt_topic")),
                    protocol=_optional_string(payload.get("protocol")),
                    limit=_bounded_int(payload.get("limit"), 2_000, 1, 50_000),
                    offset=_bounded_int(payload.get("offset"), 0, 0, 10_000_000),
                    max_points=_bounded_int(payload.get("max_points"), 2_000, 1, 10_000),
                )
                page = self.telemetry_repository.query(query)
                return IpcCommandResult(
                    True,
                    {
                        "points": [telemetry_point_to_dict(point) for point in page.points],
                        "total_count": page.total_count,
                        "limit": page.limit,
                        "offset": page.offset,
                    },
                )
            if command == "get_ingestion_statistics":
                return IpcCommandResult(True, self.statistics_snapshot())
            if command == "get_sparkplug_state":
                return IpcCommandResult(True, {"entities": self._sparkplug_parser.state_registry.snapshot()})
            if command == "shutdown":
                QTimer.singleShot(0, self.shutdown)
                return IpcCommandResult(True, {"accepted": True})
            return IpcCommandResult(False, error_code="unsupported_command", error_message=command)
        except Exception as exc:
            LOGGER.exception("IPC command %s failed", command)
            return IpcCommandResult(False, error_code="command_failed", error_message=str(exc))

    def status_snapshot(self) -> dict[str, object]:
        writer = self._writer.snapshot()
        connected_count = sum(1 for connected in self._mqtt_connected.values() if connected)
        subscriptions = [
            subscription.topic
            for profile in self.settings_repository.list_brokers(enabled_only=True)
            for subscription in profile.subscriptions
        ]
        return {
            "daemon_state": self.lifecycle.state.value,
            "process_running": True,
            "collection_enabled": self._collection_enabled,
            "mqtt_connected": connected_count > 0,
            "active_broker_count": connected_count,
            "standard_subscriptions_active": any(not self._is_sparkplug_topic(topic) for topic in subscriptions),
            "sparkplug_subscriptions_active": any(self._is_sparkplug_topic(topic) for topic in subscriptions),
            "sparkplug_session_valid": bool(self._sparkplug_parser.state_registry.snapshot()),
            "database_writer_healthy": writer.healthy,
            "ipc_active": True,
            "connected_ui_clients": self.ipc_server.client_count,
            "last_error": self._last_error,
            "database_size_bytes": self.telemetry_repository.database_size_bytes(),
        }

    def statistics_snapshot(self) -> dict[str, object]:
        snapshot = self.statistics.snapshot()
        writer = self._writer.snapshot()
        snapshot.update(
            {
                "queue_depth": self._mqtt_messages.qsize(),
                "queue_capacity": self._mqtt_messages.maxsize,
                "writer_queue_depth": writer.queue_depth,
                "writer_queue_capacity": writer.queue_capacity,
                "telemetry_points_written": writer.points_written,
                "write_failures": writer.write_failures,
                "messages_dropped": int(snapshot["messages_dropped"]) + writer.points_dropped,
                "last_successful_write_timestamp_ns": writer.last_successful_write_timestamp_ns,
            }
        )
        return snapshot

    @Slot()
    def broadcast_status(self) -> None:
        self.ipc_server.broadcast("status_changed", self.status_snapshot())

    def _enqueue_message(self, message: IncomingMqttMessage) -> None:
        self.statistics.increment("messages_received")
        try:
            self._mqtt_messages.put(message, timeout=0.02)
        except queue.Full:
            self.statistics.increment("messages_dropped")

    def _processing_loop(self) -> None:
        while not self._processor_stop.is_set():
            try:
                item = self._mqtt_messages.get(timeout=0.2)
            except queue.Empty:
                continue
            if item is _PROCESS_SENTINEL:
                self._mqtt_messages.task_done()
                return
            message = item
            try:
                points = self._router.parse(message)  # type: ignore[arg-type]
                self.statistics.increment("messages_parsed")
                self.statistics.increment("telemetry_points_created", len(points))
                if self._is_sparkplug_topic(message.metadata.topic):  # type: ignore[union-attr]
                    self.statistics.increment("sparkplug_payloads_decoded")
                    if self._sparkplug_parser.last_message_ignored:
                        self.statistics.increment("messages_ignored")
                    update = self._sparkplug_parser.last_state_update
                    if getattr(update, "birth", False):
                        self.statistics.increment("birth_messages_received")
                    if getattr(update, "death", False):
                        self.statistics.increment("death_messages_received")
                    self.statistics.increment("unknown_metric_aliases", int(getattr(update, "unknown_aliases", 0)))
                if points and not self._writer.submit(points):
                    self.statistics.increment("messages_dropped")
            except Exception as exc:
                self.statistics.increment("messages_rejected")
                if self._is_sparkplug_topic(message.metadata.topic):  # type: ignore[union-attr]
                    self.statistics.increment("sparkplug_decode_failures")
                try:
                    self.telemetry_repository.record_rejection(
                        message.metadata.received_timestamp_ns,  # type: ignore[union-attr]
                        message.metadata.topic,  # type: ignore[union-attr]
                        str(exc),
                        len(message.payload),  # type: ignore[union-attr]
                    )
                except Exception:
                    LOGGER.exception("Failed to record rejected MQTT message")
                should_log, suppressed = self._rejection_log_limiter.check(
                    message.metadata.topic, exc  # type: ignore[union-attr]
                )
                if should_log:
                    suffix = f"; suppressed {suppressed} similar rejection(s)" if suppressed else ""
                    LOGGER.warning(
                        "Rejected MQTT message on %s: %s%s",
                        message.metadata.topic,  # type: ignore[union-attr]
                        exc,
                        suffix,
                    )
                else:
                    LOGGER.debug(
                        "Suppressed repeated MQTT rejection on %s: %s",
                        message.metadata.topic,  # type: ignore[union-attr]
                        exc,
                    )
            finally:
                self._mqtt_messages.task_done()


    def _is_sparkplug_topic(self, topic: str) -> bool:
        return topic.startswith(f"{self._sparkplug_parser.namespace}/")

    def _on_writer_batch(self, points: Sequence[TelemetryPoint]) -> None:
        self.statistics.increment("telemetry_points_written", len(points))
        self.statistics.set_value("last_successful_write_timestamp_ns", time.time_ns())
        self.telemetryCommitted.emit(tuple(points[-500:]))

    @Slot(object)
    def _broadcast_telemetry(self, raw_points: object) -> None:
        points = raw_points if isinstance(raw_points, tuple) else tuple()
        payload = {
            "points": [
                telemetry_point_to_dict(point)
                for point in points
                if isinstance(point, TelemetryPoint)
            ]
        }
        if payload["points"]:
            self.ipc_server.broadcast("telemetry_batch", payload)

    @Slot(int, bool, str)
    def _apply_mqtt_state(self, broker_id: int, connected: bool, detail: str) -> None:
        previously_connected = self._mqtt_connected.get(broker_id, False)
        self._mqtt_connected[broker_id] = connected
        if connected:
            if self.lifecycle.state in {DaemonState.CONNECTING, DaemonState.RECONNECTING}:
                self.lifecycle.transition(DaemonState.RUNNING)
            self._last_error = ""
        elif self._collection_enabled:
            if previously_connected:
                self.statistics.increment("reconnect_count")
            if self.lifecycle.state in {DaemonState.RUNNING, DaemonState.CONNECTING}:
                self.lifecycle.transition(DaemonState.RECONNECTING)
            self._last_error = detail
        self.broadcast_status()

    def _disconnect_mqtt_clients(self) -> None:
        clients = tuple(self._mqtt_clients.values())
        self._mqtt_clients.clear()
        for client in clients:
            try:
                client.disconnect()
            except Exception:
                LOGGER.exception("MQTT disconnect failed")
        self._mqtt_connected.clear()

    @Slot()
    def _purge_retention(self) -> None:
        try:
            config = self.settings_service.effective_daemon_configuration()
            if config.retention_days > 0:
                cutoff = time.time_ns() - config.retention_days * 86_400 * 1_000_000_000
                deleted = self.telemetry_repository.purge_before(cutoff)
                LOGGER.info("Retention cleanup removed %d telemetry points", deleted)
        except Exception:
            LOGGER.exception("Retention cleanup failed")

    def _fail(self, message: str) -> None:
        self._last_error = message
        with suppress(Exception):
            self.lifecycle.transition(DaemonState.FAILED)
        LOGGER.error("Daemon failure: %s", message)
        self.broadcast_status()


def _required_string(payload: Mapping[str, object], key: str) -> str:
    value = payload.get(key)
    if not isinstance(value, str) or not value.strip() or len(value) > 256:
        raise ValueError(f"{key} must be a non-empty string no longer than 256 characters")
    return value.strip()


def _optional_string(value: object) -> str | None:
    if value is None or value == "":
        return None
    if not isinstance(value, str) or len(value) > 65_535:
        raise ValueError("query string filter is invalid")
    return value


def _bounded_int(value: object, default: int, minimum: int, maximum: int) -> int:
    if value is None:
        return default
    if isinstance(value, bool):
        raise ValueError("boolean is not a valid integer")
    parsed = int(value)
    if not minimum <= parsed <= maximum:
        raise ValueError(f"integer must be between {minimum} and {maximum}")
    return parsed
