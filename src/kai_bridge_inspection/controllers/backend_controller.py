"""Compatibility QML controller backed by modular settings, daemon, and query services.

The supplied QML calls this stable facade. Node-RED owns MQTT, Sparkplug B
parsing, alias/state handling, normalization, and routing. This class performs
catalog operations, endpoint binding, read-only queries, and chart rendering.
"""

from __future__ import annotations

import json
import logging
import re
import time
from uuid import uuid4
from collections import defaultdict, deque
from collections.abc import Callable
from concurrent.futures import CancelledError, Future, ThreadPoolExecutor
from dataclasses import replace
from itertools import pairwise
from pathlib import Path
from statistics import median
from threading import Event
from typing import Final

from PySide6.QtCharts import QXYSeries
from PySide6.QtCore import Property, QIODevice, QObject, QPointF, QSaveFile, QTimer, QUrl, Qt, Signal, Slot
from PySide6.QtGui import QDesktopServices
from PySide6.QtNetwork import QNetworkAccessManager, QNetworkReply, QNetworkRequest

from kai_bridge_inspection.application.paths import ApplicationPaths
from kai_bridge_inspection.domain.models import HistoricalQuery, LocationRecord, SensorRecord
from kai_bridge_inspection.settings.repository import (
    SENSOR_PROFILES,
    SettingsRepository,
    sensor_acquisition_mode,
)
from kai_bridge_inspection.telemetry.query_service import TelemetryQueryService
from kai_bridge_inspection.telemetry.sqlite_repository import SQLiteTelemetryRepository

from .daemon_controller import DaemonController

LOGGER = logging.getLogger(__name__)
_CHART_METRICS: Final[tuple[str, ...]] = ("ACC/X", "ACC/Y", "ACC/Z", "ACC/PITCH", "ACC/ROLL")
_LIVE_WINDOW_SECONDS: Final[float] = 60.0
_LIVE_POINT_LIMIT: Final[int] = 1_000
_HISTORY_POINT_LIMIT: Final[int] = 2_000
_DEFAULT_LAT: Final[float] = -6.917464
_DEFAULT_LON: Final[float] = 107.619123


def _live_plot_points(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    if len(points) <= _LIVE_POINT_LIMIT:
        return points
    interior = points[1:-1]
    buckets = (_LIVE_POINT_LIMIT - 2) // 2
    width = (len(interior) + buckets - 1) // buckets
    result = [points[0]]
    for start in range(0, len(interior), width):
        bucket = interior[start:start + width]
        low = min(range(len(bucket)), key=lambda index: bucket[index][1])
        high = max(range(len(bucket)), key=lambda index: bucket[index][1])
        result.extend(bucket[index] for index in sorted({low, high}))
    result.append(points[-1])
    return result


class BackendController(QObject):
    """Stable bridge for the supplied QML while core services remain replaceable."""

    historyMetricsReady = Signal(int, "QVariantList")
    _historyMetricsCompleted = Signal(int, "QVariantList")
    historyProgress = Signal(int, int)
    _historyProgress = Signal(int, int)
    historyReady = Signal(int, "QVariantList")
    _historyCompleted = Signal(int, "QVariantList")
    nodeRedConfigChanged = Signal()
    nodeRedBindingsChanged = Signal()
    mqttConfigChanged = Signal()
    mqttBrokersChanged = Signal()
    locationAdded = Signal()
    sensorAdded = Signal()
    indicatorsUpdated = Signal("QVariant")
    mqttHealthUpdated = Signal("QVariant")
    sensorConnectionChanged = Signal(str, bool)
    notificationRaised = Signal(str, str)
    csvExportStarted = Signal()
    csvExportFinished = Signal(str)

    def __init__(
        self,
        paths: ApplicationPaths,
        settings: SettingsRepository,
        daemon_controller: DaemonController,
        parent: QObject | None = None,
    ) -> None:
        super().__init__(parent)
        self._otac_network = QNetworkAccessManager(self)
        self.paths = paths
        self.settings = settings
        self.daemon_controller = daemon_controller
        self.telemetry_repository = SQLiteTelemetryRepository(paths.telemetry_db)
        self.query_service = TelemetryQueryService(self.telemetry_repository)
        self._broker_ids: list[int] = []
        self._charts_paused = False
        self._history_visible = False
        self._history_metrics_request = 0
        self._history_metrics_job: Future[list[str]] | None = None
        self._history_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="seam-history")
        self._history_job: Future[list[dict[str, object]]] | None = None
        self._history_request = 0
        self._history_cancel = Event()
        self._export_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="seam-export")
        self._stop_export = Event()
        self._export_job: Future[int | None] | None = None
        self.csvExportFinished.connect(self._finish_export, Qt.ConnectionType.QueuedConnection)
        self._historyMetricsCompleted.connect(self.historyMetricsReady.emit, Qt.ConnectionType.QueuedConnection)
        self._historyProgress.connect(self.historyProgress.emit, Qt.ConnectionType.QueuedConnection)
        self._historyCompleted.connect(self.historyReady.emit, Qt.ConnectionType.QueuedConnection)
        self._pending_indicators: dict[str, dict[str, object]] = defaultdict(dict)
        self._render_keys: dict[tuple[str, str], tuple[float, float, int, float]] = {}
        self._chart_series: dict[str, dict[str, QXYSeries | None]] = {}
        self._buffers: dict[str, dict[str, deque[tuple[float, float]]]] = {}
        self._latest_values: dict[str, dict[str, object]] = defaultdict(dict)
        self._device_to_sensor: dict[str, str] = {}
        self._sensor_to_device: dict[str, str] = {}
        self._sensor_activity: dict[str, tuple[float, bool]] = {}
        self._refresh_sensor_mapping()
        self._sensor_watch = QTimer(self, interval=1000)
        self._sensor_watch.timeout.connect(self._check_sensor_activity)
        self._sensor_watch.start()
        self.daemon_controller.telemetryBatch.connect(self._on_telemetry_batch)
        self.daemon_controller.statusChanged.connect(self._on_daemon_status)
        self._render_timer = QTimer(self)
        self._render_timer.setInterval(max(50, int(self.settings.get_setting("ui_refresh_ms", "100"))))
        self._render_timer.timeout.connect(self._flush_indicators)
        self._render_timer.timeout.connect(self._render_charts)
        self._render_timer.start()

    @Slot(result=str)
    def getDbPath(self) -> str:
        return str(self.paths.data_dir)

    @Slot(result=str)
    def getTelemetryDbPath(self) -> str:
        return str(self.paths.telemetry_db)

    @Slot()
    def openDbFolder(self) -> None:
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(self.paths.data_dir)))

    @Slot(str)
    def setDbFolder(self, folder_url: str) -> None:
        path = Path(self._normalise_path(folder_url)).expanduser()
        try:
            path.mkdir(parents=True, exist_ok=True)
            self.settings.set_setting("requested_data_dir", str(path.resolve()))
            self.notificationRaised.emit(
                "Database location",
                "The custom data directory is saved and applies on the next application and daemon start via KAI_BRIDGE_DATA_DIR.",
            )
        except OSError as exc:
            self.notificationRaised.emit("Database error", str(exc))

    @Slot()
    def stopServices(self) -> None:
        self._history_cancel.set()
        self._stop_export.set()
        self._export_executor.shutdown(wait=True, cancel_futures=True)
        self.daemon_controller.close()
        self.telemetry_repository.close()

    @Slot(str, str, result=str)
    def getSetting(self, key: str, default_val: str = "") -> str:
        return self.settings.get_setting(key, default_val)

    @Slot(str, str)
    def saveSetting(self, key: str, value: str) -> None:
        allowed = {
            "theme",
            "language",
            "debug_print",
            "data_gathering",
            "retention_days",
            "nr_address",
            "nr_port",
            "daemon_autostart",
            "daemon_stop_with_app",
            "ui_refresh_ms",
        }
        if key not in allowed:
            return
        self.settings.set_setting(key, value)
        if key == "data_gathering":
            if value == "true":
                self.daemon_controller.startCollection()
            else:
                self.daemon_controller.pauseCollection()
        elif key in {"retention_days", "debug_print"}:
            self.daemon_controller.reloadSettings()

    @Slot(result="QVariant")
    def getMqttBrokers(self) -> list[dict[str, object]]:
        brokers = self.settings.list_brokers()
        self._broker_ids = [broker.broker_id for broker in brokers]
        result: list[dict[str, object]] = []
        for broker in brokers:
            sensor_names = self.settings.sensor_names_for_broker(broker.broker_id)
            result.append(
                {
                    "id": broker.broker_id,
                    "name": broker.name,
                    "server": broker.host,
                    "port": str(broker.port),
                    "user": broker.username,
                    "pwd": "",
                    "password_env": broker.password_env,
                    "tls_enabled": broker.tls_enabled,
                    "enabled": broker.enabled,
                    "sensor_count": len(sensor_names),
                    "sensor_names": sensor_names,
                }
            )
        return result

    @Slot(str, str, str, str, str)
    def addMqttBroker(self, name: str, server: str, port: str, user: str, pwd: str) -> None:
        try:
            broker_id = self.settings.add_broker(
                name=name,
                host=server,
                port=int(port or "1883"),
                username=user,
                password_env=self._secret_reference(pwd, name or server),
            )
            self.settings.replace_subscription(broker_id, "spBv1.0/#", 0)
            self.mqttBrokersChanged.emit()
            self.daemon_controller.reloadSettings()
        except Exception as exc:
            self.notificationRaised.emit("MQTT broker error", str(exc))

    @Slot(int, result="QVariant")
    def deleteMqttBroker(self, index: int) -> dict[str, object]:
        broker_id = self._broker_id_for_index(index)
        if broker_id is None:
            return {"ok": False, "reason": "not_found", "sensors": []}

        sensor_names = self.settings.sensor_names_for_broker(broker_id)
        if sensor_names:
            return {
                "ok": False,
                "reason": "in_use",
                "sensors": sensor_names,
                "sensor_count": len(sensor_names),
            }

        try:
            self.settings.delete_broker(broker_id)
        except Exception as exc:
            self.notificationRaised.emit("MQTT broker error", str(exc))
            return {"ok": False, "reason": "error", "message": str(exc), "sensors": []}

        self.mqttBrokersChanged.emit()
        self.sensorAdded.emit()
        self.daemon_controller.reloadSettings()
        return {"ok": True, "reason": "deleted", "sensors": []}

    @Slot(int, str, str, str, str, str)
    def updateMqttBroker(
        self,
        index: int,
        name: str,
        server: str,
        port: str,
        user: str,
        pwd: str,
    ) -> None:
        broker_id = self._broker_id_for_index(index)
        if broker_id is None:
            return
        current = next((item for item in self.settings.list_brokers() if item.broker_id == broker_id), None)
        password_env = current.password_env if current is not None and not pwd else self._secret_reference(pwd, name)
        try:
            self.settings.update_broker(
                broker_id,
                name=name,
                host=server,
                port=int(port or "1883"),
                username=user,
                password_env=password_env,
            )
            self.mqttBrokersChanged.emit()
            self.daemon_controller.reloadSettings()
        except Exception as exc:
            self.notificationRaised.emit("MQTT broker error", str(exc))

    @Slot(bool)
    def setDebugPrint(self, enabled: bool) -> None:
        self.saveSetting("debug_print", "true" if enabled else "false")

    @Slot(result=bool)
    def getDebugPrint(self) -> bool:
        return self.settings.get_setting("debug_print", "false") == "true"

    @Slot(bool)
    def setLiveChartsPaused(self, paused: bool) -> None:
        # Capture one final frame before freezing, and render immediately when
        # resuming.  Previously the paused flag was set first, so the attempted
        # final render returned early and a stale global pause could survive page
        # navigation until the view was reopened.
        if paused and not self._charts_paused:
            self._render_charts()
        self._charts_paused = paused
        if not paused:
            self._render_charts()

    @Property(str, notify=nodeRedConfigChanged)
    def nodeRedAddress(self) -> str:
        return self.settings.get_setting("nr_address", "127.0.0.1")

    @Property(str, notify=nodeRedConfigChanged)
    def nodeRedPort(self) -> str:
        return self.settings.get_setting("nr_port", "1880")

    beanCommandFinished = Signal(str, str)

    beanRatesLoaded = Signal(str, "QVariantList")
    beanDownloadProgress = Signal(str, int)
    beanDownloadFinished = Signal(str, bool, str)

    def _bean_request(self) -> QNetworkRequest | None:
        address = self.nodeRedAddress
        url = QUrl(address if "://" in address else "http://" + address)
        if url.scheme() == "wss":
            url.setScheme("https")
        elif url.scheme() == "ws":
            url.setScheme("http")
        if url.scheme() not in {"http", "https"} or not url.host() or not self.nodeRedPort.isdecimal():
            return None
        port = int(self.nodeRedPort)
        if not 1 <= port <= 65535:
            return None
        url.setPort(port)
        url.setPath("/kai/beandevice/streaming")
        url.setQuery("")
        url.setFragment("")
        request = QNetworkRequest(url)
        request.setTransferTimeout(5000)
        request.setAttribute(QNetworkRequest.Attribute.RedirectPolicyAttribute,
                             QNetworkRequest.RedirectPolicy.ManualRedirectPolicy)
        request.setHeader(QNetworkRequest.KnownHeaders.ContentTypeHeader, "application/json")
        return request

    @Slot(str)
    def loadBeanRates(self, name: str) -> None:
        sensor = self.settings.get_sensor(name)
        request = self._bean_request()
        if sensor is None or request is None or not re.fullmatch(r"[0-9A-Fa-f]{16}", sensor.device_id):
            self.beanRatesLoaded.emit(name, [])
            return
        url = request.url()
        url.setQuery("device_id=" + sensor.device_id.upper())
        request.setUrl(url)
        reply = self._otac_network.get(request)

        def finish() -> None:
            rates: list[int] = []
            if reply.error() == QNetworkReply.NetworkError.NoError:
                try:
                    body = json.loads(bytes(reply.readAll().data()))
                    values = body.get("rates") if isinstance(body, dict) else None
                    if isinstance(values, list):
                        rates = sorted({rate for rate in values if type(rate) is int and 1 <= rate <= 65535})
                except (ValueError, TypeError):
                    pass
            self.beanRatesLoaded.emit(name, rates)
            reply.deleteLater()

        reply.finished.connect(finish)

    @Slot(str, int, QUrl, result=bool)
    def downloadBeanRecording(self, name: str, index: int, destination: QUrl) -> bool:
        sensor = self.settings.get_sensor(name)
        request = self._bean_request()
        if (sensor is None or request is None or not destination.isLocalFile()
                or not sensor.profile.startswith("beandevice_")
                or not re.fullmatch(r"[0-9A-Fa-f]{16}", sensor.device_id)
                or not 0 <= index <= 65535):
            return False
        url = request.url()
        url.setPath("/kai/beandevice/recording")
        request.setUrl(url)
        request.setTransferTimeout(125000)
        token = uuid4().hex
        reply = self._otac_network.post(request, json.dumps({
            "device_id": sensor.device_id.upper(), "file_index": index, "token": token,
        }).encode())
        progress_request = self._bean_request()
        assert progress_request is not None
        url.setQuery("token=" + token)
        progress_request.setUrl(url)
        poll = QTimer(reply)
        poll.setInterval(1000)
        in_flight = False
        finished = False

        def poll_progress() -> None:
            nonlocal in_flight
            if in_flight:
                return
            in_flight = True
            response = self._otac_network.get(progress_request)

            def read_progress() -> None:
                nonlocal in_flight
                in_flight = False
                if not finished and response.error() == QNetworkReply.NetworkError.NoError:
                    try:
                        value = json.loads(bytes(response.readAll().data())).get("percent")
                        if type(value) is int and 0 <= value < 100:
                            self.beanDownloadProgress.emit(name, value)
                    except (ValueError, TypeError, AttributeError):
                        pass
                response.deleteLater()

            response.finished.connect(read_progress)

        poll.timeout.connect(poll_progress)
        poll.start()

        def finish() -> None:
            nonlocal finished
            finished = True
            poll.stop()
            saved = False
            status = reply.attribute(QNetworkRequest.Attribute.HttpStatusCodeAttribute)
            data = reply.readAll()
            error = ""
            if status != 200 or reply.error() != QNetworkReply.NetworkError.NoError:
                detail = bytes(data.data()[:300]).decode("utf-8", errors="replace").strip()
                if detail.startswith("<"):
                    detail = ""
                reason = detail or reply.errorString()
                error = f"HTTP {status}: {reason}" if status is not None else reason
            elif bytes(reply.rawHeader(b"Content-Type").data()).split(b";", 1)[0].strip().lower() != b"application/octet-stream":
                error = "Node-RED returned an unexpected recording format."
            elif not 0 < data.size() <= 32 * 1024 * 1024:
                error = "The recording was empty or exceeded 32 MiB."
            else:
                output = QSaveFile(destination.toLocalFile())
                if output.open(QIODevice.OpenModeFlag.WriteOnly):
                    saved = output.write(data.data()) == data.size() and output.commit()
                if not saved:
                    error = output.errorString()
            self.beanDownloadFinished.emit(name, saved, error)
            reply.deleteLater()

        deadline = QTimer(reply)
        deadline.setSingleShot(True)
        deadline.timeout.connect(reply.abort)
        deadline.start(130000)
        reply.finished.connect(finish)
        return True

    @Slot(str, int, str, bool, int, int, str, result=bool)
    def applyBeanStreaming(self, name: str, rate: int, mode: str, store_forward: bool, cycle: int, duration: int, pattern: str) -> bool:
        sensor = self.settings.get_sensor(name)
        if sensor is None or sensor_acquisition_mode(sensor.profile, sensor.trigger_mode) != "streaming":
            return False
        if not re.fullmatch(r"[0-9A-Fa-f]{16}", sensor.device_id) or not 1 <= rate <= 65535:
            return False
        request = self._bean_request()
        if request is None:
            return False
        reply = self._otac_network.post(request, json.dumps({
            "device_id": sensor.device_id.upper(), "sample_rate": rate,
            "mode": mode, "store_forward": store_forward,
            "cycle": cycle, "duration": duration, "pattern": pattern,
        }).encode())

        def finish() -> None:
            status = reply.attribute(QNetworkRequest.Attribute.HttpStatusCodeAttribute)
            outcome = "queued" if status == 202 and reply.error() == QNetworkReply.NetworkError.NoError else "unconfirmed"
            self.beanCommandFinished.emit(name, outcome)
            reply.deleteLater()

        reply.finished.connect(finish)
        return True

    @Slot(str, str)
    def saveNodeRedConfig(self, address: str, port: str) -> None:
        self.settings.set_setting("nr_address", address.strip() or "127.0.0.1")
        self.settings.set_setting("nr_port", port.strip() or "1880")
        self.nodeRedConfigChanged.emit()
        self.daemon_controller.reloadSettings()

    @Slot(result="QVariant")
    def getNodeRedBindings(self) -> dict[str, str]:
        return self.settings.get_node_red_bindings()

    @Slot(str, str)
    def saveNodeRedBinding(self, widget_key: str, endpoint_name: str) -> None:
        try:
            self.settings.set_node_red_binding(widget_key, endpoint_name)
            self.nodeRedBindingsChanged.emit()
            self.daemon_controller.reloadSettings()
        except Exception as exc:
            self.notificationRaised.emit("Node-RED binding error", str(exc))

    @Slot(str, str, str, str, result=bool)
    def saveNodeRedBindings(
        self,
        accelerometer: str,
        inclinometer: str,
        indicators: str,
        location: str,
    ) -> bool:
        try:
            self.settings.set_node_red_bindings(
                {
                    "accelerometer": accelerometer,
                    "inclinometer": inclinometer,
                    "indicators": indicators,
                    "location": location,
                }
            )
            self.nodeRedBindingsChanged.emit()
            self.daemon_controller.reloadSettings()
            return True
        except Exception as exc:
            self.notificationRaised.emit("Node-RED binding error", str(exc))
            return False

    @Property(str, notify=mqttConfigChanged)
    def mqttAddress(self) -> str:
        brokers = self.settings.list_brokers()
        return brokers[0].host if brokers else ""

    @Property(str, notify=mqttConfigChanged)
    def mqttPort(self) -> str:
        brokers = self.settings.list_brokers()
        return str(brokers[0].port) if brokers else ""

    @Slot(str, str)
    def saveMqttConfig(self, address: str, port: str) -> None:
        brokers = self.settings.list_brokers()
        if brokers:
            first = brokers[0]
            self.settings.update_broker(
                first.broker_id,
                first.name,
                address,
                int(port or "1883"),
                first.username,
                first.password_env,
            )
        else:
            self.settings.add_broker(address, address, int(port or "1883"))
        self.mqttConfigChanged.emit()
        self.mqttBrokersChanged.emit()
        self.daemon_controller.reloadSettings()

    @Slot(str, result="QVariant")
    def getLocationData(self, name: str) -> dict[str, object]:
        location = self.settings.get_location(name)
        if location is None:
            return {}
        return {
            "name": location.name,
            "description": location.description,
            "lat": location.latitude,
            "lon": location.longitude,
            "sensors": [sensor.name for sensor in self.settings.list_sensors(location.name)],
        }

    @Slot(result="QVariantMap")
    def getSidebarSearchIndex(self) -> dict[str, str]:
        terms = {
            location.name: [location.name, location.description]
            for location in self.settings.list_locations()
        }
        for sensor in self.settings.list_sensors():
            if sensor.location_name in terms:
                terms[sensor.location_name].extend((sensor.name, sensor.description))
        return {name: " ".join(parts).lower() for name, parts in terms.items()}

    @Slot(result=list)
    def getLocationNames(self) -> list[str]:
        return [location.name for location in self.settings.list_locations()]

    @Slot(str, str, float, float)
    def saveNewLocation(self, name: str, description: str, lat: float, lon: float) -> None:
        try:
            self.settings.save_location(LocationRecord(name.strip(), description.strip(), lat, lon))
            self.locationAdded.emit()
        except Exception as exc:
            self.notificationRaised.emit("Location error", str(exc))

    @Slot(str, str, str, float, float)
    def updateLocationMeta(
        self,
        old_name: str,
        new_name: str,
        new_desc: str,
        lat: float,
        lon: float,
    ) -> None:
        try:
            self.settings.save_location(
                LocationRecord(new_name.strip(), new_desc.strip(), lat, lon), old_name=old_name
            )
            self.locationAdded.emit()
            self.sensorAdded.emit()
        except Exception as exc:
            self.notificationRaised.emit("Location error", str(exc))

    @Slot(str)
    def deleteLocation(self, name: str) -> None:
        self.settings.delete_location(name)
        self._refresh_sensor_mapping()
        self.locationAdded.emit()
        self.sensorAdded.emit()
        self.daemon_controller.reloadSettings()

    @Slot(str, str, str, str, str, result=bool)
    def saveNewNodeRedSensor(
        self,
        name: str,
        description: str,
        device_id: str,
        websocket_endpoint: str,
        location_name: str,
    ) -> bool:
        return self.saveProfileSensor(name, description, device_id, location_name, "nemosense", [
            {"metric": "", "path": websocket_endpoint},
        ])

    @Slot(result="QVariantMap")
    def sensorProfiles(self) -> dict[str, object]:
        return {profile: list(metrics) for profile, (_, metrics) in SENSOR_PROFILES.items()}

    @staticmethod
    def _bean_acquisition(profile: str, acquisition: str) -> str:
        if not profile.startswith("beandevice_"):
            return ""
        if acquisition not in {"periodic", "streaming"}:
            raise ValueError("Choose Periodic or Streaming for BeanDevice")
        return acquisition

    @staticmethod
    def _sensor_routes(streams: list[dict[str, str]]) -> dict[str, str]:
        routes: dict[str, str] = {}
        for stream in streams:
            metric = stream["metric"].strip()
            if metric in routes:
                raise ValueError(f"Duplicate metric name: {metric!r}")
            routes[metric] = stream["path"]
        return routes

    @Slot(str, str, str, str, str, "QVariantList", result=bool)
    @Slot(str, str, str, str, str, "QVariantList", str, result=bool)
    def saveProfileSensor(
        self, name: str, description: str, device_id: str, location_name: str,
        profile: str, streams: list[dict[str, str]], acquisition: str = "periodic",
    ) -> bool:
        try:
            normalized_device = self.settings.validate_node_red_device_id(device_id)
            label = SENSOR_PROFILES[profile][0]
            routes = self._sensor_routes(streams)
            record = SensorRecord(
                name=name.strip(),
                description=description.strip(),
                location_name=location_name,
                broker_id=None,
                mqtt_server="",
                mqtt_port=1883,
                mqtt_topic=f"nodered/{normalized_device}",
                mqtt_username="",
                password_env="",
                device_id=normalized_device,
                device_type=label,
                sample_rate=250 if profile == "nemosense" else 0,
                trigger_mode="Continuous" if profile == "nemosense" else self._bean_acquisition(profile, acquisition),
                latitude=_DEFAULT_LAT,
                longitude=_DEFAULT_LON,
            )
            success = self.settings.save_sensor(record, profile=profile, routes=routes, create_only=True)
            self._refresh_sensor_mapping()
            self.sensorAdded.emit()
            self.daemon_controller.reloadSettings()
            return success
        except Exception as exc:
            self.notificationRaised.emit("Sensor error", str(exc))
            return False

    @Slot(str, str, str, str, str, str, str, str, result=bool)
    def saveNewSensor(
        self,
        name: str,
        description: str,
        server: str,
        port: str,
        user: str,
        pwd: str,
        topic: str,
        location_name: str,
    ) -> bool:
        try:
            if self.settings.get_sensor(name) is not None:
                return False
            broker_id = self._find_broker_id(server, int(port or "1883"), user)
            if broker_id is None and server:
                broker_id = self.settings.add_broker(server, server, int(port or "1883"), user, self._secret_reference(pwd, name))
                self.mqttBrokersChanged.emit()
            if broker_id is not None:
                self.settings.replace_subscription(broker_id, topic or "spBv1.0/#", 0)
            legacy_device_id = self._device_id_from_topic(topic, name)
            record = SensorRecord(
                name=name.strip(),
                description=description.strip(),
                location_name=location_name,
                broker_id=broker_id,
                mqtt_server=server,
                mqtt_port=int(port or "1883"),
                mqtt_topic=topic or "spBv1.0/#",
                mqtt_username=user,
                password_env=self._secret_reference(pwd, name),
                device_id=legacy_device_id,
                device_type="Dewesoft Nemosense",
                sample_rate=250,
                trigger_mode="Continuous",
                latitude=_DEFAULT_LAT,
                longitude=_DEFAULT_LON,
                websocket_endpoint=f"kai/sensors/{legacy_device_id}",
            )
            success = self.settings.save_sensor(record)
            self._refresh_sensor_mapping()
            self.sensorAdded.emit()
            self.daemon_controller.reloadSettings()
            return success
        except Exception as exc:
            self.notificationRaised.emit("Sensor error", str(exc))
            return False

    @Slot(str, str, str, result=bool)
    def updateSensorMeta(self, old_name: str, new_name: str, new_desc: str) -> bool:
        existing = self.settings.get_sensor(old_name)
        if existing is None:
            return False
        updated = SensorRecord(
            name=new_name.strip(),
            description=new_desc.strip(),
            location_name=existing.location_name,
            broker_id=existing.broker_id,
            mqtt_server=existing.mqtt_server,
            mqtt_port=existing.mqtt_port,
            mqtt_topic=existing.mqtt_topic,
            mqtt_username=existing.mqtt_username,
            password_env=existing.password_env,
            device_id=existing.device_id,
            device_type=existing.device_type,
            sample_rate=existing.sample_rate,
            trigger_mode=existing.trigger_mode,
            latitude=existing.latitude,
            longitude=existing.longitude,
            websocket_endpoint=existing.websocket_endpoint,
        )
        success = self.settings.save_sensor(updated, old_name=old_name)
        self._refresh_sensor_mapping()
        self.sensorAdded.emit()
        return success

    @Slot(str, str, str, str, str, str)
    def updateSensorSettings(
        self,
        name: str,
        server: str,
        port: str,
        topic: str,
        user: str,
        pwd: str,
    ) -> None:
        broker_id = self._find_broker_id(server, int(port or "1883"), user)
        if broker_id is None and server:
            broker_id = self.settings.add_broker(server, server, int(port or "1883"), user, self._secret_reference(pwd, name))
            self.mqttBrokersChanged.emit()
        self.settings.set_sensor_connection(
            name,
            broker_id,
            server,
            int(port or "1883"),
            topic or "spBv1.0/#",
            user,
            self._secret_reference(pwd, name),
        )
        if broker_id is not None:
            self.settings.replace_subscription(broker_id, topic or "spBv1.0/#", 0)
        self._refresh_sensor_mapping()
        self.sensorAdded.emit()
        self.daemon_controller.reloadSettings()

    @Slot(str, str, str, float, float, result=bool)
    def updateNodeRedSensorSettings(
        self,
        name: str,
        device_id: str,
        websocket_endpoint: str,
        lat: float,
        lon: float,
    ) -> bool:
        sensor = self.settings.get_sensor(name)
        if sensor is None:
            return False
        routes = {"": websocket_endpoint} if sensor.profile == "nemosense" else self.settings.get_sensor_streams(sensor)
        return self.updateProfileSensor(name, device_id, sensor.profile, [
            {"metric": metric, "path": path} for metric, path in routes.items()
        ], lat, lon)

    @Slot(str, str, str, "QVariantList", float, float, result=bool)
    @Slot(str, str, str, "QVariantList", float, float, str, result=bool)
    def updateProfileSensor(
        self, name: str, device_id: str, profile: str,
        streams: list[dict[str, str]], lat: float, lon: float, acquisition: str | None = None,
    ) -> bool:
        try:
            sensor = self.settings.get_sensor(name)
            if sensor is None:
                return False
            device_id = self.settings.validate_node_red_device_id(device_id)
            label = SENSOR_PROFILES[profile][0]
            if acquisition is None:
                acquisition = sensor_acquisition_mode(sensor.profile, sensor.trigger_mode) or "periodic"
            trigger_mode = self._bean_acquisition(profile, acquisition)
            if profile == "nemosense":
                trigger_mode = sensor.trigger_mode if sensor.profile == profile else "Continuous"
            success = self.settings.save_sensor(
                replace(sensor, device_id=device_id, device_type=label, mqtt_topic=f"nodered/{device_id}",
                        latitude=lat, longitude=lon,
                        sample_rate=sensor.sample_rate if profile == sensor.profile else (250 if profile == "nemosense" else 0),
                        trigger_mode=trigger_mode),
                old_name=name, profile=profile, routes=self._sensor_routes(streams),
            )
            if not success:
                return False
            if sensor.device_id != device_id:
                self._latest_values.pop(name, None)
            self._refresh_sensor_mapping()
            self.sensorAdded.emit()
            self.daemon_controller.reloadSettings()
            return True
        except Exception as exc:
            self.notificationRaised.emit("Sensor settings error", str(exc))
            return False

    @Slot(str, float, float, result=bool)
    def updateSensorGnss(self, name: str, lat: float, lon: float) -> bool:
        try:
            self.settings.set_sensor_gnss(name, lat, lon)
            self.sensorAdded.emit()
            return True
        except Exception as exc:
            self.notificationRaised.emit("GNSS error", str(exc))
            return False

    @Slot(str, result="QVariant")
    @Slot(str, bool, result="QVariant")
    def getSensorData(self, name: str, include_history: bool = True) -> dict[str, object]:
        sensor = self.settings.get_sensor(name)
        if sensor is None:
            return {}
        data: dict[str, object] = {
            "name": sensor.name,
            "description": sensor.description,
            "location_name": sensor.location_name,
            "mqtt_server": sensor.mqtt_server,
            "mqtt_port": str(sensor.mqtt_port),
            "mqtt_topic": sensor.mqtt_topic,
            "mqtt_user": sensor.mqtt_username,
            "mqtt_pwd": "",
            "device_id": sensor.device_id,
            "websocket_endpoint": sensor.websocket_endpoint,
            "device_type": sensor.device_type,
            "sample_rate": sensor.sample_rate,
            "trigger_mode": sensor.trigger_mode,
            "gnss_lat": sensor.latitude,
            "gnss_lon": sensor.longitude,
        }
        latest = self.telemetry_repository.latest_values(sensor.device_id, 500) if include_history else ()
        values = {point.metric_name: point.value for point in latest}
        values.update(self._latest_values.get(name, {}))
        data.update({metric: value for metric, value in values.items() if metric not in data})
        if "ACC/TEMPERATURE" in data:
            data["temp"] = data["ACC/TEMPERATURE"]
        if "BATTERY" in data:
            data["battery"] = data["BATTERY"]
        if "ACC/PITCH" in data:
            data["pitch"] = data["ACC/PITCH"]
        if "ACC/ROLL" in data:
            data["roll"] = data["ACC/ROLL"]
        data["active_metrics"] = list(self.telemetry_repository.list_metrics(sensor.device_id)) if include_history else []
        routes = self.settings.get_sensor_streams(sensor)
        streams = [
            {
                "metric": metric,
                "path": path,
                "connected": self.daemon_controller.isEndpointConnected(path),
                "value": values.get(metric),
            }
            for metric, path in routes.items()
        ]
        acquisition = sensor_acquisition_mode(sensor.profile, sensor.trigger_mode)
        data["acquisition"] = acquisition
        data["profile_metrics"] = (
            [*SENSOR_PROFILES[sensor.profile][1], *(metric for metric in routes if metric)]
            if acquisition == "streaming" else list(routes)
        )
        data["profile"] = sensor.profile
        data["streams"] = streams
        connected_count = sum(1 for stream in streams if stream["connected"])
        endpoint_connected = bool(streams) and connected_count == len(streams)
        stream_health = {
            "connected": endpoint_connected,
            "status": "RUNNING" if endpoint_connected else ("PARTIAL" if connected_count else "OFFLINE"),
            "endpoint": sensor.websocket_endpoint,
            "last_error": self.daemon_controller.lastError,
        }
        data["stream_health"] = stream_health
        data["mqtt_health"] = stream_health  # legacy QML compatibility
        return data

    @Slot(str)
    def deleteSensor(self, name: str) -> None:
        self.settings.delete_sensor(name)
        self._refresh_sensor_mapping()
        self.sensorAdded.emit()
        self.daemon_controller.reloadSettings()

    @Slot()
    def purgeOldData(self) -> None:
        try:
            retention_days = int(self.settings.get_setting("retention_days", "365"))
            if retention_days > 0:
                cutoff = time.time_ns() - retention_days * 86_400 * 1_000_000_000
                self.telemetry_repository.purge_before(cutoff)
        except Exception as exc:
            self.notificationRaised.emit("Retention error", str(exc))

    @Slot(str, float, float, result=bool)
    def exportData(self, filepath: str, start_time: float, end_time: float) -> bool:
        return self._export(filepath, None, start_time, end_time)

    @Slot(str, str, float, float, result=bool)
    @Slot(str, str, float, float, str, result=bool)
    def exportSensorData(
        self,
        filepath: str,
        sensor_name: str,
        start_time: float,
        end_time: float,
        file_format: str = "",
    ) -> bool:
        return self._export(
            filepath, self._sensor_to_device.get(sensor_name, sensor_name),
            start_time, end_time, file_format or "csv", include_end_second=bool(file_format),
        )

    @Slot(result="QVariant")
    def getMqttHealth(self) -> list[dict[str, object]]:
        return [
            {
                "connected": self.daemon_controller.mqttConnected,
                "status": self.daemon_controller.state,
                "last_error": self.daemon_controller.lastError,
                "sensors": [sensor.name for sensor in self.settings.list_sensors()],
            }
        ]

    @Slot(str, str, int, result="QVariant")
    def getDataLossAnalysis(
        self,
        sensor_name: str,
        metric: str = "ACC/X",
        days: int = 1,
    ) -> dict[str, object]:
        device_id = self._sensor_to_device.get(sensor_name, sensor_name)
        end_ns = time.time_ns()
        start_ns = end_ns - max(0, days) * 86_400 * 1_000_000_000 if days > 0 else 0
        page = self.telemetry_repository.query(
            HistoricalQuery(
                start_timestamp_ns=start_ns,
                end_timestamp_ns=end_ns if days > 0 else 0,
                device_id=device_id,
                metric_name=metric,
                limit=50_000,
                max_points=50_000,
            )
        )
        timestamps = [point.timestamp_ns for point in page.points]
        if len(timestamps) < 2:
            return {"samples": len(timestamps), "missing_samples": 0, "loss_percent": 0.0}
        intervals = [b - a for a, b in pairwise(timestamps) if b > a]
        expected_interval = int(median(intervals)) if intervals else 0
        if expected_interval <= 0:
            return {"samples": len(timestamps), "missing_samples": 0, "loss_percent": 0.0}
        expected = max(1, round((timestamps[-1] - timestamps[0]) / expected_interval) + 1)
        missing = max(0, expected - len(timestamps))
        return {
            "samples": len(timestamps),
            "expected_samples": expected,
            "missing_samples": missing,
            "loss_percent": round((missing / expected) * 100.0, 4),
            "expected_interval_seconds": expected_interval / 1_000_000_000,
        }

    @Slot(str, QXYSeries, QXYSeries, QXYSeries, QXYSeries, QXYSeries)
    def registerLiveCharts(
        self,
        sensor_name: str,
        series_x: QXYSeries | None,
        series_y: QXYSeries | None,
        series_z: QXYSeries | None,
        series_pitch: QXYSeries | None,
        series_roll: QXYSeries | None,
    ) -> None:
        for metric in _CHART_METRICS:
            self._render_keys.pop((sensor_name, metric), None)
        if not any((series_x, series_y, series_z, series_pitch, series_roll)):
            self._chart_series.pop(sensor_name, None)
            return
        self._chart_series[sensor_name] = {
            "ACC/X": series_x,
            "ACC/Y": series_y,
            "ACC/Z": series_z,
            "ACC/PITCH": series_pitch,
            "ACC/ROLL": series_roll,
        }
        self._render_charts()

    @Slot(bool)
    def setHistoryVisible(self, visible: bool) -> None:
        self._history_visible = visible
        if not visible:
            self._history_cancel.set()
            self._render_charts()

    @Slot(str, result=int)
    def requestHistoryMetrics(self, sensor_name: str) -> int:
        self._history_metrics_request += 1
        request = self._history_metrics_request
        if self._history_metrics_job is not None:
            self._history_metrics_job.cancel()
        device_id = self._sensor_to_device.get(sensor_name, sensor_name)
        self._history_metrics_job = self._history_executor.submit(
            lambda: list(self.telemetry_repository.list_metrics(device_id))
        )

        def finished(job: Future[list[str]]) -> None:
            if job.cancelled():
                return
            try:
                metrics = job.result()
            except Exception:
                LOGGER.exception("History metric lookup failed")
                return
            self._historyMetricsCompleted.emit(request, metrics)

        self._history_metrics_job.add_done_callback(finished)
        return request

    @Slot(str, str, int, result=int)
    def requestHistory(self, sensor_name: str, metrics: str, days: int) -> int:
        hours = days * 24
        return self.requestHistoryHours(sensor_name, metrics, hours)

    @Slot(str, str, int, result=int)
    def requestHistoryHours(self, sensor_name: str, metrics: str, hours: int) -> int:
        end_ns = time.time_ns()
        start_ns = end_ns - hours * 3600 * 1_000_000_000 if hours > 0 else 0
        return self._request_history(sensor_name, metrics, start_ns, end_ns if hours > 0 else 0)

    @Slot(str, str, float, float, result=int)
    def requestHistoryRange(self, sensor_name: str, metrics: str, start: float, end: float) -> int:
        return self._request_history(
            sensor_name, metrics, int(start) * 1_000_000_000, int(end) * 1_000_000_000 + 999_999_999
        )

    def _request_history(self, sensor_name: str, metrics: str, start_ns: int, end_ns: int) -> int:
        self._history_cancel.set()
        cancel = self._history_cancel = Event()
        self._history_request += 1
        request = self._history_request
        if self._history_job is not None:
            self._history_job.cancel()
        device_id = self._sensor_to_device.get(sensor_name, sensor_name)
        selected = metrics.split(",")[:3]
        def load() -> list[dict[str, object]]:
            reported = 0
            results = []
            for index, metric in enumerate(selected):
                def progress(percent: int) -> None:
                    nonlocal reported
                    overall = min(99, (index * 100 + percent) // len(selected))
                    if overall > reported and not cancel.is_set():
                        reported = overall
                        self._historyProgress.emit(request, overall)

                results.append(self._history_series(device_id, metric, start_ns, end_ns, cancel, progress))
                progress(100)
            return results

        self._history_job = self._history_executor.submit(load)

        def finished(job: Future[list[dict[str, object]]]) -> None:
            if job.cancelled():
                return
            try:
                result = job.result()
            except CancelledError:
                return
            except Exception:
                LOGGER.exception("History query failed")
                result = [{"empty": True, "error": True, "hint": "History could not be loaded."}]
            self._historyCompleted.emit(request, result)

        self._history_job.add_done_callback(finished)
        return request

    @Slot(QXYSeries, "QVariantList")
    def setHistoryPoints(self, series: QXYSeries, points: list[list[float]]) -> None:
        series.replace([QPointF(x, y) for x, y in points])

    def _history_series(
        self, device_id: str, metric: str, start_ns: int, end_ns: int, cancel: Event | None = None,
        progress: Callable[[int], None] | None = None,
    ) -> dict[str, object]:
        aliases = {
            "BATTERY": ("BATTERY", "BAT_FUEL_GAUGE_REPSOC"),
            "CELLULAR_RSSI": ("CELLULAR_RSSI", "SIGNAL", "RSSI"),
        }.get(metric, (metric,))
        points = []
        actual_metric = metric
        for candidate in aliases:
            query = HistoricalQuery(
                start_timestamp_ns=start_ns,
                end_timestamp_ns=end_ns,
                device_id=device_id,
                metric_name=candidate,
                max_points=_HISTORY_POINT_LIMIT,
            )
            points = self.telemetry_repository.sample_history(query, cancel, progress)
            if points:
                actual_metric = candidate
                break
        if not points:
            return {
                "count": 0,
                "metric": metric,
                "empty": True,
                "hint": f"No stored numeric points found for {metric}.",
            }
        qpoints = [(timestamp / 1_000_000, float(value)) for timestamp, value in points]
        values = [point[1] for point in qpoints]
        return {
            "count": len(qpoints),
            "metric": actual_metric,
            "requestedMetric": metric,
            "empty": False,
            "minX": qpoints[0][0],
            "maxX": qpoints[-1][0],
            "points": [list(point) for point in qpoints],
            "minY": min(values),
            "maxY": max(values),
        }

    @Slot("QVariant")
    def _on_telemetry_batch(self, payload: object) -> None:
        if not isinstance(payload, dict):
            return
        raw_points = payload.get("points")
        if not isinstance(raw_points, list):
            return
        indicator_batches: dict[str, dict[str, object]] = defaultdict(dict)
        seen_devices: set[str] = set()
        for raw in raw_points:
            if not isinstance(raw, dict):
                continue
            device_id = str(raw.get("device_id", ""))
            sensor_name = self._device_to_sensor.get(device_id, device_id)
            seen_devices.add(device_id)
            metric = str(raw.get("metric_name", ""))
            value = raw.get("value")
            timestamp_ns = int(raw.get("timestamp_ns", time.time_ns()))
            indicator_batches[sensor_name][metric] = value
            if metric in _CHART_METRICS and isinstance(value, (int, float)) and not isinstance(value, bool):
                buffers = self._buffers.get(sensor_name)
                if buffers is None:
                    buffers = {name: deque(maxlen=20_000) for name in _CHART_METRICS}
                    self._buffers[sensor_name] = buffers
                buffers[metric].append((timestamp_ns / 1_000_000_000, float(value)))
        now = time.monotonic()
        for sensor_name, indicators in indicator_batches.items():
            if self._sensor_to_device.get(sensor_name) in seen_devices:
                previous = self._sensor_activity.get(sensor_name)
                self._sensor_activity[sensor_name] = (now, True)
                if previous is not None and not previous[1]:
                    self.sensorConnectionChanged.emit(sensor_name, True)
            indicators["device_id"] = sensor_name
            self._decorate_indicators(indicators)
            self._latest_values[sensor_name].update(indicators)
            self._pending_indicators[sensor_name].update(indicators)

    @Slot()
    def _check_sensor_activity(self) -> None:
        now = time.monotonic()
        for name, (last_seen, online) in self._sensor_activity.items():
            if online and now - last_seen >= 15:
                self._sensor_activity[name] = (last_seen, False)
                self.sensorConnectionChanged.emit(name, False)

    @Slot()
    def _flush_indicators(self) -> None:
        pending, self._pending_indicators = self._pending_indicators, defaultdict(dict)
        for indicators in pending.values():
            self.indicatorsUpdated.emit(indicators)

    @Slot("QVariant")
    def _on_daemon_status(self, status: object) -> None:
        self.mqttHealthUpdated.emit([status] if isinstance(status, dict) else [])

    @Slot()
    def _render_charts(self) -> None:
        if self._charts_paused or self._history_visible:
            return
        now = time.time()
        for sensor_name, series_map in tuple(self._chart_series.items()):
            buffers = self._buffers.get(sensor_name)
            if not buffers:
                continue
            # A shared, stable origin keeps channels aligned even if one starts later.
            newest = max((buffer[-1][0] for buffer in buffers.values() if buffer), default=now)
            window_end = max(now, newest)
            origin = window_end - _LIVE_WINDOW_SECONDS
            for metric, series in series_map.items():
                if series is None:
                    continue
                key = (sensor_name, metric)
                buffer = buffers[metric]
                if not buffer:
                    if self._render_keys.pop(key, None) is not None:
                        series.clear()
                    continue
                signature = (*buffer[-1], len(buffer), origin)
                if self._render_keys.get(key) == signature:
                    continue
                self._render_keys[key] = signature
                points = [point for point in buffer if point[0] >= origin]
                if not points:
                    if series.count():
                        series.clear()
                    continue
                if any(left[0] > right[0] for left, right in pairwise(points)):
                    points.sort(key=lambda point: point[0])
                points = _live_plot_points(points)
                series.replace([QPointF(timestamp - origin, value) for timestamp, value in points])

    def _refresh_sensor_mapping(self) -> None:
        previous = self._sensor_to_device.copy()
        self._device_to_sensor.clear()
        self._sensor_to_device.clear()
        for sensor in self.settings.list_sensors():
            self._device_to_sensor[sensor.device_id] = sensor.name
            self._device_to_sensor[sensor.name] = sensor.name
            self._sensor_to_device[sensor.name] = sensor.device_id
        for name in tuple(self._sensor_activity):
            if self._sensor_to_device.get(name) != previous.get(name):
                del self._sensor_activity[name]

    def _find_broker_id(self, host: str, port: int, username: str) -> int | None:
        for broker in self.settings.list_brokers():
            if broker.host == host and broker.port == port and broker.username == username:
                return broker.broker_id
        return None

    def _broker_id_for_index(self, index: int) -> int | None:
        if not self._broker_ids:
            self.getMqttBrokers()
        return self._broker_ids[index] if 0 <= index < len(self._broker_ids) else None

    def _export(
        self, filepath: str, device_id: str | None, start_time: float, end_time: float,
        file_format: str = "csv", *, include_end_second: bool = False,
    ) -> bool:
        if self._stop_export.is_set() or self._export_job is not None or file_format not in {"csv", "xlsx"}:
            return False
        local_path = self._normalise_path(filepath)
        if not local_path or not Path(local_path).name:
            return False
        path = Path(local_path)
        suffix = "." + file_format
        if path.suffix.lower() != suffix:
            path = path.with_name(path.name + suffix)
        start_ns = int(start_time * 1_000_000_000) if start_time > 0 else 0
        end_ns = int(end_time * 1_000_000_000) if end_time > 0 else 0
        if include_end_second:
            start_ns = int(start_time) * 1_000_000_000
            end_ns = int(end_time) * 1_000_000_000 + 999_999_999
        query = HistoricalQuery(
            start_timestamp_ns=start_ns,
            end_timestamp_ns=end_ns,
            device_id=device_id,
        )
        self.csvExportStarted.emit()
        writer = self.query_service.export_xlsx if file_format == "xlsx" else self.query_service.export_csv
        self._export_job = self._export_executor.submit(writer, path, query, self._stop_export)
        self._export_job.add_done_callback(self._publish_export_result)
        return True

    def _publish_export_result(self, job: Future[int | None]) -> None:
        if self._stop_export.is_set():
            return
        try:
            job.result()
        except Exception as exc:
            self.csvExportFinished.emit(str(exc) or type(exc).__name__)
        else:
            self.csvExportFinished.emit("")

    @Slot(str)
    def _finish_export(self, _error: str) -> None:
        self._export_job = None

    @staticmethod
    def _decorate_indicators(indicators: dict[str, object]) -> None:
        rssi_metric = next(
            (key for key in ("CELLULAR_RSSI", "SIGNAL", "RSSI", "cellular_rssi") if key in indicators), None
        )
        if rssi_metric and not (indicators.get("SIGNAL_STRENGTH_LABEL") or indicators.get("signal_strength_label")):
            try:
                rssi = float(indicators[rssi_metric])
                indicators["SIGNAL_STRENGTH_LABEL"] = (
                    "excellent" if rssi >= -65 else "good" if rssi >= -75 else "fair" if rssi >= -85 else "bad"
                )
            except (TypeError, ValueError):
                indicators["SIGNAL_STRENGTH_LABEL"] = "lost"
        if "BAT_CHARGER_STATUS" in indicators:
            labels = {0: "Not Charged", 1: "Unknown (?)", 2: "Charged"}
            try:
                label = labels.get(int(indicators["BAT_CHARGER_STATUS"]), "unknown")
            except (TypeError, ValueError):
                label = "unknown"
            indicators["BAT_CHARGER_STATUS_LABEL"] = label
            indicators["BATTERY_CHARGER_LABEL"] = label
        for source, target in (
            ("MQTT_IS_CONNECTION_OK", "MQTT_DEVICE_STATUS"),
            ("NTP_IS_CONNECTION_OK", "NTP_STATUS"),
        ):
            if source in indicators:
                try:
                    indicators[target] = "ok" if int(indicators[source]) == 1 else "down"
                except (TypeError, ValueError):
                    indicators[target] = "unknown"
        indicators["DEVICE_DATA_AGE_SECONDS"] = 0.0
        try:
            if float(indicators.get("PWR_5V_POE_V", 0.0)) > 1.0:
                indicators["POWER_SOURCE_LABEL"] = "PoE"
            elif float(indicators.get("PWR_VBUS_V", 0.0)) > 1.0:
                indicators["POWER_SOURCE_LABEL"] = "VBUS / battery module"
        except (TypeError, ValueError):
            pass

    @staticmethod
    def _device_id_from_topic(topic: str, fallback_name: str) -> str:
        levels = [level for level in topic.split("/") if level and level not in {"#", "+"}]
        if topic.startswith("spBv1.0/") and len(levels) >= 5:
            return levels[-1]
        slug = re.sub(r"[^A-Za-z0-9_.:-]", "-", fallback_name.strip())
        return slug[:128] or "unknown-device"

    @staticmethod
    def _secret_reference(value: str, label: str) -> str:
        candidate = value.strip()
        if not candidate:
            return ""
        if candidate.startswith("env:"):
            return candidate[4:].strip()
        if re.fullmatch(r"[A-Z_][A-Z0-9_]{1,127}", candidate):
            return candidate
        safe = re.sub(r"[^A-Za-z0-9]", "_", label).upper().strip("_") or "BROKER"
        return f"KAI_MQTT_{safe}_PASSWORD"

    @staticmethod
    def _normalise_path(path: str) -> str:
        return QUrl(path).toLocalFile() if path.startswith("file:") else path
