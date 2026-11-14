"""SQLite application settings and inspection catalogue persistence.

Legacy MQTT tables remain readable for schema compatibility, but the v5 desktop
runtime does not consume broker profiles or subscriptions.
"""

from __future__ import annotations

import re
import sqlite3
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import replace
from pathlib import Path

from kai_bridge_inspection.domain.errors import ConfigurationError
from kai_bridge_inspection.domain.models import (
    LocationRecord,
    MqttBrokerProfile,
    MqttSubscription,
    SensorRecord,
)

_SCHEMA_VERSION = 4
_IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9 ._():-]{1,128}$")
_TELEMETRY_ID_RE = re.compile(r"^[A-Za-z0-9_.:/-]{1,192}$")
_WEBSOCKET_ENDPOINT_RE = re.compile(r"^[A-Za-z0-9_.:/-]{1,255}$")


SENSOR_PROFILES = {
    "nemosense": ("Dewesoft Nemosense", ("",)),
    "beandevice_accelerometer": ("BeanDevice Accelerometer", ("ACC/X", "ACC/Y", "ACC/Z")),
    "beandevice_inclinometer": ("BeanDevice Inclinometer", ("ACC/ROLL", "ACC/PITCH")),
    "beandevice_combo": (
        "BeanDevice Combo", ("ACC/X", "ACC/Y", "ACC/Z", "ACC/ROLL", "ACC/PITCH")
    ),
    "custom": ("Custom", ()),
}


def sensor_acquisition_mode(profile: str, trigger_mode: str) -> str:
    if not profile.startswith("beandevice_"):
        return ""
    return "streaming" if trigger_mode == "streaming" else "periodic"


class SettingsRepository:
    """Owns the settings database and applies versioned migrations."""

    def __init__(self, database_path: Path) -> None:
        self.database_path = database_path
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self.migrate()

    @contextmanager
    def _connection(self) -> Iterator[sqlite3.Connection]:
        connection = sqlite3.connect(self.database_path, timeout=10.0)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA synchronous = NORMAL")
        try:
            yield connection
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()

    def migrate(self) -> None:
        with self._connection() as connection:
            version = int(connection.execute("PRAGMA user_version").fetchone()[0])
            if version > _SCHEMA_VERSION:
                raise ConfigurationError(
                    f"settings.db schema {version} is newer than supported {_SCHEMA_VERSION}"
                )
            if version < 1:
                connection.executescript(
                    """
                    CREATE TABLE settings (
                        key TEXT PRIMARY KEY,
                        value TEXT NOT NULL
                    );
                    CREATE TABLE mqtt_brokers (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        name TEXT NOT NULL,
                        host TEXT NOT NULL,
                        port INTEGER NOT NULL DEFAULT 1883,
                        client_id TEXT NOT NULL DEFAULT '',
                        username TEXT NOT NULL DEFAULT '',
                        password_env TEXT NOT NULL DEFAULT '',
                        keepalive_seconds INTEGER NOT NULL DEFAULT 60,
                        clean_session INTEGER NOT NULL DEFAULT 1,
                        tls_enabled INTEGER NOT NULL DEFAULT 0,
                        ca_certificate_path TEXT NOT NULL DEFAULT '',
                        client_certificate_path TEXT NOT NULL DEFAULT '',
                        client_key_path TEXT NOT NULL DEFAULT '',
                        allow_insecure_tls INTEGER NOT NULL DEFAULT 0,
                        enabled INTEGER NOT NULL DEFAULT 1
                    );
                    CREATE TABLE mqtt_subscriptions (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        broker_id INTEGER NOT NULL REFERENCES mqtt_brokers(id) ON DELETE CASCADE,
                        topic TEXT NOT NULL,
                        qos INTEGER NOT NULL DEFAULT 0,
                        enabled INTEGER NOT NULL DEFAULT 1,
                        UNIQUE(broker_id, topic)
                    );
                    CREATE TABLE locations (
                        name TEXT PRIMARY KEY,
                        description TEXT NOT NULL DEFAULT '',
                        latitude REAL NOT NULL DEFAULT 0,
                        longitude REAL NOT NULL DEFAULT 0
                    );
                    CREATE TABLE sensors (
                        name TEXT PRIMARY KEY,
                        description TEXT NOT NULL DEFAULT '',
                        location_name TEXT NOT NULL REFERENCES locations(name) ON UPDATE CASCADE ON DELETE CASCADE,
                        broker_id INTEGER REFERENCES mqtt_brokers(id) ON DELETE SET NULL,
                        mqtt_server TEXT NOT NULL DEFAULT '',
                        mqtt_port INTEGER NOT NULL DEFAULT 1883,
                        mqtt_topic TEXT NOT NULL DEFAULT '',
                        mqtt_username TEXT NOT NULL DEFAULT '',
                        password_env TEXT NOT NULL DEFAULT '',
                        device_id TEXT NOT NULL DEFAULT '',
                        device_type TEXT NOT NULL DEFAULT 'Dewesoft Nemosense',
                        sample_rate INTEGER NOT NULL DEFAULT 250,
                        trigger_mode TEXT NOT NULL DEFAULT 'Continuous',
                        latitude REAL NOT NULL DEFAULT -6.917464,
                        longitude REAL NOT NULL DEFAULT 107.619123
                    );
                    CREATE INDEX idx_sensors_location ON sensors(location_name);
                    CREATE INDEX idx_subscriptions_broker ON mqtt_subscriptions(broker_id);
                    """
                )
                defaults = {
                    "theme": "dark",
                    "debug_print": "false",
                    "data_gathering": "true",
                    "retention_days": "365",
                    "nr_address": "127.0.0.1",
                    "nr_port": "1880",
                    "daemon_autostart": "true",
                    "daemon_stop_with_app": "false",
                    "ui_refresh_ms": "100",
                    "telemetry_backend": "sqlite",
                    "sparkplug_namespace": "spBv1.0",
                }
                connection.executemany(
                    "INSERT INTO settings(key, value) VALUES (?, ?)", defaults.items()
                )
                connection.execute("PRAGMA user_version = 1")
                version = 1
            if version < 2:
                connection.executescript(
                    """
                    CREATE TABLE node_red_bindings (
                        widget_key TEXT PRIMARY KEY,
                        endpoint_name TEXT NOT NULL
                    );
                    """
                )
                connection.executemany(
                    "INSERT INTO node_red_bindings(widget_key, endpoint_name) VALUES (?, ?)",
                    (
                        ("accelerometer", "kai/accelerometer"),
                        ("inclinometer", "kai/inclinometer"),
                        ("indicators", "kai/indicators"),
                        ("location", "kai/location"),
                    ),
                )
                connection.execute("PRAGMA user_version = 2")
                version = 2
            if version < 3:
                connection.executescript(
                    """
                    ALTER TABLE sensors ADD COLUMN websocket_endpoint TEXT NOT NULL DEFAULT '';
                    UPDATE sensors
                    SET websocket_endpoint = 'kai/sensors/' || device_id
                    WHERE websocket_endpoint = '' AND device_id <> '';
                    """
                )
                connection.execute("PRAGMA user_version = 3")
                connection.commit()

            if version < 4:
                connection.execute("BEGIN IMMEDIATE")
                connection.execute("ALTER TABLE sensors ADD COLUMN profile TEXT NOT NULL DEFAULT 'nemosense'")
                connection.execute(
                    """CREATE TABLE sensor_metric_endpoints (
                        sensor_name TEXT NOT NULL REFERENCES sensors(name) ON UPDATE CASCADE ON DELETE CASCADE,
                        metric_name TEXT NOT NULL,
                        endpoint TEXT NOT NULL UNIQUE,
                        PRIMARY KEY (sensor_name, metric_name)
                    )"""
                )
                connection.execute("PRAGMA user_version = 4")

    def get_setting(self, key: str, default: str = "") -> str:
        with self._connection() as connection:
            row = connection.execute("SELECT value FROM settings WHERE key = ?", (key,)).fetchone()
        return str(row["value"]) if row is not None else default

    def set_setting(self, key: str, value: str) -> None:
        if not key or len(key) > 128:
            raise ConfigurationError("invalid setting key")
        with self._connection() as connection:
            connection.execute(
                "INSERT INTO settings(key, value) VALUES (?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                (key, value),
            )


    def get_node_red_bindings(self) -> dict[str, str]:
        """Return the widget-to-WebSocket endpoint contract used by the desktop."""
        with self._connection() as connection:
            rows = connection.execute(
                "SELECT widget_key, endpoint_name FROM node_red_bindings ORDER BY widget_key"
            ).fetchall()
        return {str(row["widget_key"]): str(row["endpoint_name"]) for row in rows}

    def set_node_red_binding(self, widget_key: str, endpoint_name: str) -> None:
        key, endpoint = self._normalize_node_red_binding(widget_key, endpoint_name)
        with self._connection() as connection:
            connection.execute(
                "INSERT INTO node_red_bindings(widget_key, endpoint_name) VALUES (?, ?) "
                "ON CONFLICT(widget_key) DO UPDATE SET endpoint_name = excluded.endpoint_name",
                (key, endpoint),
            )

    def set_node_red_bindings(self, bindings: dict[str, str]) -> None:
        """Replace a widget-binding set in one transaction."""
        normalized = [
            self._normalize_node_red_binding(widget_key, endpoint_name)
            for widget_key, endpoint_name in bindings.items()
        ]
        with self._connection() as connection:
            connection.executemany(
                "INSERT INTO node_red_bindings(widget_key, endpoint_name) VALUES (?, ?) "
                "ON CONFLICT(widget_key) DO UPDATE SET endpoint_name = excluded.endpoint_name",
                normalized,
            )

    @staticmethod
    def _normalize_node_red_binding(widget_key: str, endpoint_name: str) -> tuple[str, str]:
        key = widget_key.strip().lower()
        endpoint = endpoint_name.strip().strip("/")
        if key not in {"accelerometer", "inclinometer", "indicators", "location"}:
            raise ConfigurationError(f"unsupported Node-RED widget binding: {widget_key!r}")
        if not endpoint or len(endpoint) > 255 or any(ch.isspace() for ch in endpoint):
            raise ConfigurationError("Node-RED endpoint must be a non-empty path without spaces")
        return key, endpoint

    def list_brokers(self, enabled_only: bool = False) -> list[MqttBrokerProfile]:
        where = "WHERE enabled = 1" if enabled_only else ""
        with self._connection() as connection:
            rows = connection.execute(f"SELECT * FROM mqtt_brokers {where} ORDER BY id").fetchall()
            profiles: list[MqttBrokerProfile] = []
            for row in rows:
                subscriptions = connection.execute(
                    "SELECT topic, qos FROM mqtt_subscriptions "
                    "WHERE broker_id = ? AND enabled = 1 ORDER BY id",
                    (int(row["id"]),),
                ).fetchall()
                profiles.append(
                    MqttBrokerProfile(
                        broker_id=int(row["id"]),
                        name=str(row["name"]),
                        host=str(row["host"]),
                        port=int(row["port"]),
                        client_id=str(row["client_id"]),
                        username=str(row["username"]),
                        password_env=str(row["password_env"]),
                        keepalive_seconds=int(row["keepalive_seconds"]),
                        clean_session=bool(row["clean_session"]),
                        tls_enabled=bool(row["tls_enabled"]),
                        ca_certificate_path=str(row["ca_certificate_path"]),
                        client_certificate_path=str(row["client_certificate_path"]),
                        client_key_path=str(row["client_key_path"]),
                        allow_insecure_tls=bool(row["allow_insecure_tls"]),
                        enabled=bool(row["enabled"]),
                        subscriptions=tuple(
                            MqttSubscription(topic=str(item["topic"]), qos=int(item["qos"]))
                            for item in subscriptions
                        ),
                    )
                )
        return profiles

    def add_broker(
        self,
        name: str,
        host: str,
        port: int,
        username: str = "",
        password_env: str = "",
    ) -> int:
        self._validate_broker(host, port)
        with self._connection() as connection:
            cursor = connection.execute(
                "INSERT INTO mqtt_brokers(name, host, port, username, password_env) VALUES (?, ?, ?, ?, ?)",
                (name.strip() or host.strip(), host.strip(), port, username.strip(), password_env.strip()),
            )
            return int(cursor.lastrowid)

    def update_broker(
        self,
        broker_id: int,
        name: str,
        host: str,
        port: int,
        username: str = "",
        password_env: str = "",
    ) -> None:
        self._validate_broker(host, port)
        with self._connection() as connection:
            connection.execute(
                "UPDATE mqtt_brokers SET name = ?, host = ?, port = ?, username = ?, password_env = ? WHERE id = ?",
                (name.strip() or host.strip(), host.strip(), port, username.strip(), password_env.strip(), broker_id),
            )

    def sensor_names_for_broker(self, broker_id: int) -> list[str]:
        """Return sensors that still reference a broker profile."""
        with self._connection() as connection:
            rows = connection.execute(
                "SELECT name FROM sensors WHERE broker_id = ? ORDER BY name",
                (broker_id,),
            ).fetchall()
        return [str(row["name"]) for row in rows]

    def delete_broker(self, broker_id: int) -> None:
        """Delete an unused broker and reject destructive orphaning."""
        sensor_names = self.sensor_names_for_broker(broker_id)
        if sensor_names:
            joined = ", ".join(sensor_names)
            raise ConfigurationError(
                f"MQTT broker is still used by {len(sensor_names)} sensor(s): {joined}"
            )
        with self._connection() as connection:
            connection.execute("DELETE FROM mqtt_brokers WHERE id = ?", (broker_id,))

    def replace_subscription(self, broker_id: int, topic: str, qos: int = 0) -> None:
        if not self.is_valid_topic_filter(topic):
            raise ConfigurationError(f"invalid MQTT topic filter: {topic!r}")
        if qos not in (0, 1, 2):
            raise ConfigurationError("MQTT QoS must be 0, 1, or 2")
        with self._connection() as connection:
            connection.execute(
                "INSERT INTO mqtt_subscriptions(broker_id, topic, qos) VALUES (?, ?, ?) "
                "ON CONFLICT(broker_id, topic) DO UPDATE SET qos = excluded.qos, enabled = 1",
                (broker_id, topic, qos),
            )

    def list_locations(self) -> list[LocationRecord]:
        with self._connection() as connection:
            rows = connection.execute("SELECT * FROM locations ORDER BY name").fetchall()
        return [
            LocationRecord(str(row["name"]), str(row["description"]), float(row["latitude"]), float(row["longitude"]))
            for row in rows
        ]

    def get_location(self, name: str) -> LocationRecord | None:
        with self._connection() as connection:
            row = connection.execute("SELECT * FROM locations WHERE name = ?", (name,)).fetchone()
        if row is None:
            return None
        return LocationRecord(str(row["name"]), str(row["description"]), float(row["latitude"]), float(row["longitude"]))

    def save_location(self, record: LocationRecord, old_name: str | None = None) -> None:
        self._validate_identifier(record.name, "location name")
        with self._connection() as connection:
            if old_name and old_name != record.name:
                connection.execute(
                    "UPDATE locations SET name = ?, description = ?, latitude = ?, longitude = ? WHERE name = ?",
                    (record.name, record.description, record.latitude, record.longitude, old_name),
                )
            else:
                connection.execute(
                    "INSERT INTO locations(name, description, latitude, longitude) VALUES (?, ?, ?, ?) "
                    "ON CONFLICT(name) DO UPDATE SET description = excluded.description, latitude = excluded.latitude, longitude = excluded.longitude",
                    (record.name, record.description, record.latitude, record.longitude),
                )

    def delete_location(self, name: str) -> None:
        with self._connection() as connection:
            connection.execute("DELETE FROM locations WHERE name = ?", (name,))

    def list_sensors(self, location_name: str | None = None) -> list[SensorRecord]:
        query = "SELECT * FROM sensors"
        params: tuple[object, ...] = ()
        if location_name is not None:
            query += " WHERE location_name = ?"
            params = (location_name,)
        query += " ORDER BY name"
        with self._connection() as connection:
            rows = connection.execute(query, params).fetchall()
        return [self._sensor_from_row(row) for row in rows]

    def get_sensor(self, name: str) -> SensorRecord | None:
        with self._connection() as connection:
            row = connection.execute("SELECT * FROM sensors WHERE name = ?", (name,)).fetchone()
        return self._sensor_from_row(row) if row is not None else None

    def save_sensor(
        self, record: SensorRecord, old_name: str | None = None, *,
        profile: str | None = None, routes: dict[str, str] | None = None, create_only: bool = False,
    ) -> bool:
        self._validate_identifier(record.name, "sensor name")
        if record.device_id and not _TELEMETRY_ID_RE.fullmatch(record.device_id.strip()):
            raise ConfigurationError(
                "Node-RED device_id must use 1-192 letters, digits, dot, underscore, colon, slash, or dash"
            )
        if not self.is_valid_topic_filter(record.mqtt_topic):
            raise ConfigurationError(f"invalid MQTT topic filter: {record.mqtt_topic!r}")
        with self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            current = connection.execute(
                "SELECT profile, device_id FROM sensors WHERE name = ?", (old_name or record.name,)
            ).fetchone()
            if create_only and current is not None:
                raise ConfigurationError(f"Sensor name is already in use: {record.name!r}")
            if old_name is not None and current is None:
                return False
            if profile is None:
                profile = str(current["profile"]) if current is not None else "nemosense"
            acquisition = sensor_acquisition_mode(profile, record.trigger_mode)
            routes_explicit = routes is not None
            if routes is None:
                routes = (
                    {"": record.websocket_endpoint or f"kai/sensors/{record.device_id}"}
                    if profile == "nemosense"
                    else self._read_metric_endpoints(connection, old_name or record.name)
                )
                if acquisition == "streaming":
                    routes[""] = record.websocket_endpoint or f"kai/sensors/{record.device_id}"
            if (create_only or routes_explicit) and record.device_id and (current is None or current["device_id"] != record.device_id):
                owner = connection.execute(
                    "SELECT name FROM sensors WHERE device_id = ? AND name <> ?",
                    (record.device_id, old_name or record.name),
                ).fetchone()
                if owner is not None:
                    raise ConfigurationError(f"Device ID is already assigned to sensor {owner[0]!r}")
            normalized = self._validate_routes(connection, old_name or record.name, profile, routes, acquisition)
            endpoint = normalized.get("", "")
            if old_name and old_name != record.name:
                clash = connection.execute("SELECT 1 FROM sensors WHERE name = ?", (record.name,)).fetchone()
                if clash is not None:
                    return False
                connection.execute(
                    "UPDATE sensors SET name = ?, description = ? WHERE name = ?",
                    (record.name, record.description, old_name),
                )
                return True
            existing = connection.execute("SELECT 1 FROM sensors WHERE name = ?", (record.name,)).fetchone()
            if existing is not None:
                connection.execute(
                    """UPDATE sensors SET description=?, location_name=?, broker_id=?, mqtt_server=?, mqtt_port=?,
                    mqtt_topic=?, mqtt_username=?, password_env=?, device_id=?, device_type=?, sample_rate=?, trigger_mode=?,
                    latitude=?, longitude=?, websocket_endpoint=?, profile=? WHERE name=?""",
                    (
                        record.description, record.location_name, record.broker_id, record.mqtt_server, record.mqtt_port,
                        record.mqtt_topic, record.mqtt_username, record.password_env, record.device_id, record.device_type,
                        record.sample_rate, record.trigger_mode, record.latitude, record.longitude, endpoint, profile, record.name,
                    ),
                )
            else:
                connection.execute(
                    """INSERT INTO sensors(name, description, location_name, broker_id, mqtt_server, mqtt_port,
                    mqtt_topic, mqtt_username, password_env, device_id, device_type, sample_rate, trigger_mode, latitude, longitude,
                    websocket_endpoint, profile)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                    (
                        record.name, record.description, record.location_name, record.broker_id, record.mqtt_server,
                        record.mqtt_port, record.mqtt_topic, record.mqtt_username, record.password_env, record.device_id,
                        record.device_type, record.sample_rate, record.trigger_mode, record.latitude, record.longitude, endpoint, profile,
                    ),
                )
            connection.execute("DELETE FROM sensor_metric_endpoints WHERE sensor_name = ?", (record.name,))
            connection.executemany(
                "INSERT INTO sensor_metric_endpoints(sensor_name, metric_name, endpoint) VALUES (?, ?, ?)",
                [(record.name, metric, path) for metric, path in normalized.items() if metric],
            )
            return True

    def delete_sensor(self, name: str) -> None:
        with self._connection() as connection:
            connection.execute("DELETE FROM sensors WHERE name = ?", (name,))

    def set_sensor_connection(
        self,
        name: str,
        broker_id: int | None,
        server: str,
        port: int,
        topic: str,
        username: str,
        password_env: str,
    ) -> None:
        if not self.is_valid_topic_filter(topic):
            raise ConfigurationError(f"invalid MQTT topic filter: {topic!r}")
        with self._connection() as connection:
            connection.execute(
                "UPDATE sensors SET broker_id=?, mqtt_server=?, mqtt_port=?, mqtt_topic=?, mqtt_username=?, password_env=? WHERE name=?",
                (broker_id, server, port, topic, username, password_env, name),
            )

    def set_sensor_gnss(self, name: str, latitude: float, longitude: float) -> None:
        with self._connection() as connection:
            connection.execute(
                "UPDATE sensors SET latitude = ?, longitude = ? WHERE name = ?",
                (latitude, longitude, name),
            )

    def set_sensor_device_id(self, name: str, device_id: str) -> None:
        """Compatibility wrapper that preserves the existing WebSocket endpoint."""
        sensor = self.get_sensor(name)
        if sensor is None:
            raise ConfigurationError(f"sensor not found: {name!r}")
        self.set_sensor_node_red_mapping(name, device_id, sensor.websocket_endpoint)

    def set_sensor_node_red_mapping(
        self, name: str, device_id: str, websocket_endpoint: str
    ) -> None:
        sensor = self.get_sensor(name)
        if sensor is None:
            raise ConfigurationError(f"sensor not found: {name!r}")
        normalized_device = self.validate_node_red_device_id(device_id)
        self.save_sensor(
            replace(sensor, device_id=normalized_device, mqtt_topic=f"nodered/{normalized_device}",
                    websocket_endpoint=websocket_endpoint)
        )

    @staticmethod
    def validate_node_red_device_id(device_id: str) -> str:
        normalized = device_id.strip()
        if not _TELEMETRY_ID_RE.fullmatch(normalized):
            raise ConfigurationError("Invalid Node-RED device_id. Use 1-192 letters, digits, or ._:/-")
        return normalized

    @staticmethod
    def _read_metric_endpoints(connection: sqlite3.Connection, name: str) -> dict[str, str]:
        return dict(connection.execute(
            "SELECT metric_name, endpoint FROM sensor_metric_endpoints WHERE sensor_name = ? ORDER BY metric_name",
            (name,),
        ).fetchall())

    def get_sensor_streams(self, sensor: SensorRecord) -> dict[str, str]:
        if sensor.profile == "nemosense":
            return {"": sensor.websocket_endpoint}
        with self._connection() as connection:
            routes = self._read_metric_endpoints(connection, sensor.name)
        if sensor_acquisition_mode(sensor.profile, sensor.trigger_mode) == "streaming":
            return {"": sensor.websocket_endpoint, **routes}
        return routes

    def _validate_routes(
        self, connection: sqlite3.Connection, name: str, profile: str, routes: dict[str, str], acquisition: str
    ) -> dict[str, str]:
        if profile not in SENSOR_PROFILES:
            raise ConfigurationError("Choose a supported sensor profile")
        required = ("",) if acquisition == "streaming" else SENSOR_PROFILES[profile][1]
        auxiliary = set(routes).difference(required)
        if not routes or not set(required).issubset(routes) or (profile == "nemosense" and auxiliary):
            raise ConfigurationError("Enter the required WebSocket paths for the selected profile and acquisition mode")
        if acquisition and auxiliary.intersection(SENSOR_PROFILES["beandevice_combo"][1]):
            raise ConfigurationError("Motion metrics must use the paths for the selected BeanDevice channels and mode")
        if any(not _TELEMETRY_ID_RE.fullmatch(metric) for metric in auxiliary):
            raise ConfigurationError("Invalid metric name. Use 1-192 letters, digits, or ._:/-")
        normalized = {metric: self.normalize_websocket_endpoint(path) for metric, path in routes.items()}
        if len(set(normalized.values())) != len(normalized):
            raise ConfigurationError("Each metric needs a different WebSocket path")
        for path in normalized.values():
            owner = connection.execute(
                """SELECT name FROM sensors WHERE websocket_endpoint = ? AND name <> ?
                   UNION ALL
                   SELECT sensor_name FROM sensor_metric_endpoints WHERE endpoint = ? AND sensor_name <> ?""",
                (path, name, path, name),
            ).fetchone()
            if owner is not None:
                raise ConfigurationError(f"WebSocket endpoint is already assigned to sensor {owner[0]!r}: {path!r}")
        return normalized

    def list_node_red_sensor_streams(self) -> dict[str, tuple[str, frozenset[str]]]:
        """Return the device and allowed metrics for each path; empty allows all metrics."""
        with self._connection() as connection:
            rows = connection.execute(
                """SELECT websocket_endpoint, device_id, '', profile, trigger_mode
                   FROM sensors WHERE websocket_endpoint <> ''
                   UNION ALL
                   SELECT endpoint, device_id, metric_name, profile, trigger_mode
                   FROM sensor_metric_endpoints JOIN sensors ON sensor_name = name"""
            ).fetchall()
        streams: dict[str, tuple[str, frozenset[str]]] = {}
        for path, device, metric, profile, trigger_mode in rows:
            if metric:
                metrics = (metric,)
            elif sensor_acquisition_mode(profile, trigger_mode) == "streaming":
                metrics = SENSOR_PROFILES[profile][1]
            else:
                metrics = ()
            streams[path] = (device, frozenset(metrics))
        return streams

    def list_node_red_sensor_endpoints(self) -> dict[str, str]:
        return {path: device for path, (device, _) in self.list_node_red_sensor_streams().items()}

    @staticmethod
    def normalize_websocket_endpoint(value: str) -> str:
        endpoint = value.strip().strip("/")
        if not _WEBSOCKET_ENDPOINT_RE.fullmatch(endpoint):
            raise ConfigurationError(
                "WebSocket endpoint must use 1-255 letters, digits, dot, underscore, colon, slash, or dash"
            )
        return endpoint

    def ensure_sensor_subscriptions(self) -> None:
        """Mirror enabled sensor topics into broker subscriptions."""
        with self._connection() as connection:
            rows = connection.execute(
                "SELECT broker_id, mqtt_topic FROM sensors WHERE broker_id IS NOT NULL AND mqtt_topic <> ''"
            ).fetchall()
            connection.executemany(
                "INSERT OR IGNORE INTO mqtt_subscriptions(broker_id, topic, qos) VALUES (?, ?, 0)",
                [(int(row["broker_id"]), str(row["mqtt_topic"])) for row in rows],
            )

    @staticmethod
    def is_valid_topic_filter(topic: str) -> bool:
        if not topic or len(topic.encode("utf-8")) > 65_535 or "\x00" in topic:
            return False
        levels = topic.split("/")
        for index, level in enumerate(levels):
            if "#" in level and (level != "#" or index != len(levels) - 1):
                return False
            if "+" in level and level != "+":
                return False
        return True

    @staticmethod
    def _validate_broker(host: str, port: int) -> None:
        if not host.strip() or len(host) > 255:
            raise ConfigurationError("broker host is required")
        if not 1 <= port <= 65_535:
            raise ConfigurationError("broker port is outside 1..65535")

    @staticmethod
    def _validate_identifier(value: str, label: str) -> None:
        if not _IDENTIFIER_RE.fullmatch(value.strip()):
            raise ConfigurationError(f"{label} must use 1-128 letters, digits, dot, underscore, colon, or dash")

    @staticmethod
    def _sensor_from_row(row: sqlite3.Row) -> SensorRecord:
        return SensorRecord(
            name=str(row["name"]),
            description=str(row["description"]),
            location_name=str(row["location_name"]),
            broker_id=int(row["broker_id"]) if row["broker_id"] is not None else None,
            mqtt_server=str(row["mqtt_server"]),
            mqtt_port=int(row["mqtt_port"]),
            mqtt_topic=str(row["mqtt_topic"]),
            mqtt_username=str(row["mqtt_username"]),
            password_env=str(row["password_env"]),
            device_id=str(row["device_id"]),
            device_type=str(row["device_type"]),
            sample_rate=int(row["sample_rate"]),
            trigger_mode=str(row["trigger_mode"]),
            latitude=float(row["latitude"]),
            longitude=float(row["longitude"]),
            websocket_endpoint=str(row["websocket_endpoint"]),
            profile=str(row["profile"]),
        )
