"""Compatibility QML controller backed by modular settings, daemon, and query services.

The supplied QML calls this stable facade. Node-RED owns MQTT, Sparkplug B
parsing, alias/state handling, normalization, and routing. This class performs
catalog operations, endpoint binding, read-only queries, and chart rendering.
"""

from __future__ import annotations

import logging
import re
import time
from collections import defaultdict, deque
from itertools import pairwise
from pathlib import Path
from statistics import median
from typing import Final

from PySide6.QtCharts import QXYSeries
from PySide6.QtCore import Property, QObject, QPointF, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QDesktopServices

from kai_bridge_inspection.application.paths import ApplicationPaths
from kai_bridge_inspection.domain.models import HistoricalQuery, LocationRecord, SensorRecord
from kai_bridge_inspection.settings.repository import SettingsRepository
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


class BackendController(QObject):
    """Stable bridge for the supplied QML while core services remain replaceable."""

    nodeRedConfigChanged = Signal()
    nodeRedBindingsChanged = Signal()
    mqttConfigChanged = Signal()
    mqttBrokersChanged = Signal()
    locationAdded = Signal()
    sensorAdded = Signal()
    indicatorsUpdated = Signal("QVariant")
    mqttHealthUpdated = Signal("QVariant")
    notificationRaised = Signal(str, str)

    def __init__(
        self,
        paths: ApplicationPaths,
        settings: SettingsRepository,
        daemon_controller: DaemonController,
        parent: QObject | None = None,
    ) -> None:
        super().__init__(parent)
        self.paths = paths
        self.settings = settings
        self.daemon_controller = daemon_controller
        self.telemetry_repository = SQLiteTelemetryRepository(paths.telemetry_db)
        self.query_service = TelemetryQueryService(self.telemetry_repository)
        self._broker_ids: list[int] = []
        self._charts_paused = False
        self._chart_series: dict[str, dict[str, QXYSeries | None]] = {}
        self._buffers: dict[str, dict[str, deque[tuple[float, float]]]] = {}
        self._latest_values: dict[str, dict[str, object]] = defaultdict(dict)
        self._device_to_sensor: dict[str, str] = {}
        self._sensor_to_device: dict[str, str] = {}
        self._refresh_sensor_mapping()
        self.daemon_controller.telemetryBatch.connect(self._on_telemetry_batch)
        self.daemon_controller.statusChanged.connect(self._on_daemon_status)
        self._render_timer = QTimer(self)
        self._render_timer.setInterval(max(50, int(self.settings.get_setting("ui_refresh_ms", "100"))))
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
        """Register a sensor with a dedicated Node-RED WebSocket stream."""
        try:
            if self.settings.get_sensor(name) is not None:
                return False
            normalized_device = re.sub(r"[^A-Za-z0-9_.:-]", "-", device_id.strip())[:128]
            if not normalized_device:
                return False
            endpoint = self.settings.normalize_websocket_endpoint(websocket_endpoint)
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
                device_type="Dewesoft Nemosense",
                sample_rate=250,
                trigger_mode="Continuous",
                latitude=_DEFAULT_LAT,
                longitude=_DEFAULT_LON,
                websocket_endpoint=endpoint,
            )
            success = self.settings.save_sensor(record)
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
        """Update the Node-RED identity, dedicated WebSocket path, and coordinates."""
        try:
            self.settings.set_sensor_node_red_mapping(name, device_id, websocket_endpoint)
            self.settings.set_sensor_gnss(name, lat, lon)
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
    def getSensorData(self, name: str) -> dict[str, object]:
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
        latest = self.telemetry_repository.latest_values(sensor.device_id, 500)
        for point in latest:
            data[point.metric_name] = point.value
        data.update(self._latest_values.get(name, {}))
        if "ACC/TEMPERATURE" in data:
            data["temp"] = data["ACC/TEMPERATURE"]
        if "BATTERY" in data:
            data["battery"] = data["BATTERY"]
        if "ACC/PITCH" in data:
            data["pitch"] = data["ACC/PITCH"]
        if "ACC/ROLL" in data:
            data["roll"] = data["ACC/ROLL"]
        data["active_metrics"] = list(self.telemetry_repository.list_metrics(sensor.device_id))
        endpoint_connected = self.daemon_controller.isEndpointConnected(sensor.websocket_endpoint)
        stream_health = {
            "connected": endpoint_connected,
            "status": "RUNNING" if endpoint_connected else self.daemon_controller.state,
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
    def exportSensorData(
        self,
        filepath: str,
        sensor_name: str,
        start_time: float,
        end_time: float,
    ) -> bool:
        return self._export(filepath, self._sensor_to_device.get(sensor_name, sensor_name), start_time, end_time)

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
        buffers = self._buffers.setdefault(
            sensor_name, {metric: deque(maxlen=20_000) for metric in _CHART_METRICS}
        )
        device_id = self._sensor_to_device.get(sensor_name, sensor_name)
        for metric in _CHART_METRICS:
            count_probe = self.telemetry_repository.query(
                HistoricalQuery(
                    device_id=device_id,
                    metric_name=metric,
                    limit=1,
                    offset=0,
                    max_points=1,
                )
            )
            page = self.telemetry_repository.query(
                HistoricalQuery(
                    device_id=device_id,
                    metric_name=metric,
                    limit=2_000,
                    offset=max(0, count_probe.total_count - 2_000),
                    max_points=2_000,
                )
            )
            buffers[metric].clear()
            for point in page.points:
                if isinstance(point.value, (int, float)) and not isinstance(point.value, bool):
                    buffers[metric].append((point.timestamp_ns / 1_000_000_000, float(point.value)))
        self._render_charts()

    @Slot(str, str, int, QXYSeries, result="QVariant")
    def loadHistorySeries(
        self,
        sensor_name: str,
        metric: str,
        days: int,
        series: QXYSeries,
    ) -> dict[str, object]:
        device_id = self._sensor_to_device.get(sensor_name, sensor_name)
        end_ns = time.time_ns()
        start_ns = end_ns - days * 86_400 * 1_000_000_000 if days > 0 else 0
        aliases = {
            "BATTERY": ("BATTERY", "BAT_FUEL_GAUGE_REPSOC"),
            "CELLULAR_RSSI": ("CELLULAR_RSSI", "SIGNAL", "RSSI"),
        }.get(metric, (metric,))
        points = []
        actual_metric = metric
        for candidate in aliases:
            page = self.telemetry_repository.query(
                HistoricalQuery(
                    start_timestamp_ns=start_ns,
                    end_timestamp_ns=end_ns if days > 0 else 0,
                    device_id=device_id,
                    metric_name=candidate,
                    limit=50_000,
                    max_points=_HISTORY_POINT_LIMIT,
                )
            )
            numeric = [
                point
                for point in page.points
                if isinstance(point.value, (int, float)) and not isinstance(point.value, bool)
            ]
            if numeric:
                points = numeric
                actual_metric = candidate
                break
        if not points:
            series.clear()
            return {
                "count": 0,
                "metric": metric,
                "empty": True,
                "hint": f"No stored numeric points found for {metric}.",
            }
        first_ns = points[0].timestamp_ns
        duration_seconds = max(1.0, (points[-1].timestamp_ns - first_ns) / 1_000_000_000)
        scale_seconds = 86_400.0 if duration_seconds > 172_800 else 3_600.0
        unit = "days" if scale_seconds == 86_400.0 else "hours"
        qpoints = [
            QPointF(
                ((point.timestamp_ns - first_ns) / 1_000_000_000) / scale_seconds,
                float(point.value),
            )
            for point in points
        ]
        series.replace(qpoints)
        values = [point.y() for point in qpoints]
        return {
            "count": len(qpoints),
            "metric": actual_metric,
            "requestedMetric": metric,
            "empty": False,
            "minX": 0.0,
            "maxX": qpoints[-1].x(),
            "minY": min(values),
            "maxY": max(values),
            "xTitle": f"Time ({unit})",
            "startLabel": time.strftime("%Y-%m-%d %H:%M", time.localtime(first_ns / 1_000_000_000)),
            "endLabel": time.strftime("%Y-%m-%d %H:%M", time.localtime(points[-1].timestamp_ns / 1_000_000_000)),
        }

    @Slot("QVariant")
    def _on_telemetry_batch(self, payload: object) -> None:
        if not isinstance(payload, dict):
            return
        raw_points = payload.get("points")
        if not isinstance(raw_points, list):
            return
        indicator_batches: dict[str, dict[str, object]] = defaultdict(dict)
        for raw in raw_points:
            if not isinstance(raw, dict):
                continue
            device_id = str(raw.get("device_id", ""))
            sensor_name = self._device_to_sensor.get(device_id, device_id)
            metric = str(raw.get("metric_name", ""))
            value = raw.get("value")
            timestamp_ns = int(raw.get("timestamp_ns", time.time_ns()))
            indicator_batches[sensor_name][metric] = value
            if metric in _CHART_METRICS and isinstance(value, (int, float)) and not isinstance(value, bool):
                buffers = self._buffers.setdefault(
                    sensor_name, {name: deque(maxlen=20_000) for name in _CHART_METRICS}
                )
                buffers[metric].append((timestamp_ns / 1_000_000_000, float(value)))
        for sensor_name, indicators in indicator_batches.items():
            indicators["device_id"] = sensor_name
            self._decorate_indicators(indicators)
            self._latest_values[sensor_name].update(indicators)
            self.indicatorsUpdated.emit(indicators)

    @Slot("QVariant")
    def _on_daemon_status(self, status: object) -> None:
        self.mqttHealthUpdated.emit([status] if isinstance(status, dict) else [])

    @Slot()
    def _render_charts(self) -> None:
        if self._charts_paused:
            return
        for sensor_name, series_map in tuple(self._chart_series.items()):
            buffers = self._buffers.get(sensor_name)
            if not buffers:
                continue
            for metric, series in series_map.items():
                if series is None:
                    continue
                points = list(buffers[metric])
                if not points:
                    series.clear()
                    continue
                latest_timestamp = points[-1][0]
                cutoff = latest_timestamp - _LIVE_WINDOW_SECONDS
                points = [point for point in points if point[0] >= cutoff]
                if len(points) > _LIVE_POINT_LIMIT:
                    stride = max(1, len(points) // _LIVE_POINT_LIMIT)
                    points = points[::stride]
                    if points[-1] != buffers[metric][-1]:
                        points.append(buffers[metric][-1])
                first_timestamp = points[0][0]
                series.replace([QPointF(timestamp - first_timestamp, value) for timestamp, value in points])

    def _refresh_sensor_mapping(self) -> None:
        self._device_to_sensor.clear()
        self._sensor_to_device.clear()
        for sensor in self.settings.list_sensors():
            self._device_to_sensor[sensor.device_id] = sensor.name
            self._device_to_sensor[sensor.name] = sensor.name
            self._sensor_to_device[sensor.name] = sensor.device_id

    def _find_broker_id(self, host: str, port: int, username: str) -> int | None:
        for broker in self.settings.list_brokers():
            if broker.host == host and broker.port == port and broker.username == username:
                return broker.broker_id
        return None

    def _broker_id_for_index(self, index: int) -> int | None:
        if not self._broker_ids:
            self.getMqttBrokers()
        return self._broker_ids[index] if 0 <= index < len(self._broker_ids) else None

    def _export(self, filepath: str, device_id: str | None, start_time: float, end_time: float) -> bool:
        try:
            self.query_service.export_csv(
                Path(self._normalise_path(filepath)),
                HistoricalQuery(
                    start_timestamp_ns=int(start_time * 1_000_000_000) if start_time > 0 else 0,
                    end_timestamp_ns=int(end_time * 1_000_000_000) if end_time > 0 else 0,
                    device_id=device_id,
                    limit=50_000,
                    max_points=50_000,
                ),
            )
            return True
        except Exception as exc:
            self.notificationRaised.emit("Export error", str(exc))
            return False

    @staticmethod
    def _decorate_indicators(indicators: dict[str, object]) -> None:
        if "CELLULAR_RSSI" in indicators:
            try:
                rssi = float(indicators["CELLULAR_RSSI"])
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
        indicators["DATA_LATENCY_SECONDS"] = 0.0
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
