"""SQLite telemetry repository with WAL, migrations, typed values, and bounded queries."""

from __future__ import annotations

import json
import sqlite3
from collections.abc import Iterator, Sequence
from contextlib import contextmanager
from pathlib import Path
from typing import Final

from kai_bridge_inspection.domain.errors import TelemetryStorageError
from kai_bridge_inspection.domain.models import HistoricalQuery, TelemetryPage, TelemetryPoint

_SCHEMA_VERSION: Final[int] = 1
_MAX_QUERY_LIMIT: Final[int] = 50_000


class SQLiteTelemetryRepository:
    """Thread-safe-by-construction repository using one connection per operation."""

    def __init__(self, database_path: Path) -> None:
        self.database_path = database_path
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self.migrate()

    @contextmanager
    def _connection(self, timeout: float = 15.0) -> Iterator[sqlite3.Connection]:
        connection = sqlite3.connect(self.database_path, timeout=timeout)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA synchronous = NORMAL")
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA busy_timeout = 15000")
        try:
            yield connection
        finally:
            connection.close()

    def migrate(self) -> None:
        with self._connection() as connection:
            version = int(connection.execute("PRAGMA user_version").fetchone()[0])
            if version > _SCHEMA_VERSION:
                raise TelemetryStorageError(
                    f"telemetry.db schema {version} is newer than supported {_SCHEMA_VERSION}"
                )
            if version < 1:
                connection.executescript(
                    """
                    BEGIN IMMEDIATE;
                    CREATE TABLE telemetry_points (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        timestamp_ns INTEGER NOT NULL,
                        received_timestamp_ns INTEGER NOT NULL,
                        device_id TEXT NOT NULL,
                        metric_name TEXT NOT NULL,
                        numeric_value REAL,
                        integer_value INTEGER,
                        text_value TEXT,
                        boolean_value INTEGER,
                        bytes_value BLOB,
                        unit TEXT,
                        data_type TEXT NOT NULL,
                        quality TEXT,
                        tags_json TEXT NOT NULL DEFAULT '{}',
                        mqtt_topic TEXT NOT NULL,
                        mqtt_qos INTEGER NOT NULL,
                        mqtt_retain INTEGER NOT NULL,
                        protocol TEXT NOT NULL,
                        sparkplug_group_id TEXT,
                        sparkplug_edge_node_id TEXT,
                        sparkplug_device_id TEXT,
                        sparkplug_metric_alias INTEGER,
                        sparkplug_sequence INTEGER
                    );
                    CREATE INDEX idx_telemetry_device_metric_time
                        ON telemetry_points(device_id, metric_name, timestamp_ns);
                    CREATE INDEX idx_telemetry_time ON telemetry_points(timestamp_ns);
                    CREATE INDEX idx_telemetry_topic_time ON telemetry_points(mqtt_topic, timestamp_ns);
                    CREATE INDEX idx_telemetry_protocol_time ON telemetry_points(protocol, timestamp_ns);
                    CREATE INDEX idx_telemetry_sparkplug_identity_time
                        ON telemetry_points(sparkplug_group_id, sparkplug_edge_node_id, sparkplug_device_id, timestamp_ns);
                    CREATE TABLE rejected_messages (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        received_timestamp_ns INTEGER NOT NULL,
                        mqtt_topic TEXT NOT NULL,
                        reason TEXT NOT NULL,
                        payload_size INTEGER NOT NULL
                    );
                    PRAGMA user_version = 1;
                    COMMIT;
                    """
                )

    def write_batch(self, points: Sequence[TelemetryPoint]) -> int:
        if not points:
            return 0
        rows = [self._point_to_row(point) for point in points]
        sql = """
            INSERT INTO telemetry_points (
                timestamp_ns, received_timestamp_ns, device_id, metric_name,
                numeric_value, integer_value, text_value, boolean_value, bytes_value,
                unit, data_type, quality, tags_json, mqtt_topic, mqtt_qos, mqtt_retain,
                protocol, sparkplug_group_id, sparkplug_edge_node_id, sparkplug_device_id,
                sparkplug_metric_alias, sparkplug_sequence
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        try:
            with self._connection() as connection:
                connection.execute("BEGIN IMMEDIATE")
                connection.executemany(sql, rows)
                connection.commit()
        except sqlite3.Error as exc:
            raise TelemetryStorageError(f"failed to write telemetry batch: {exc}") from exc
        return len(rows)

    def query(self, query: HistoricalQuery) -> TelemetryPage:
        limit = max(1, min(query.limit, _MAX_QUERY_LIMIT))
        offset = max(0, query.offset)
        clauses: list[str] = []
        parameters: list[object] = []
        if query.start_timestamp_ns > 0:
            clauses.append("timestamp_ns >= ?")
            parameters.append(query.start_timestamp_ns)
        if query.end_timestamp_ns > 0:
            clauses.append("timestamp_ns <= ?")
            parameters.append(query.end_timestamp_ns)
        if query.device_id:
            clauses.append("device_id = ?")
            parameters.append(query.device_id)
        if query.metric_name:
            clauses.append("metric_name = ?")
            parameters.append(query.metric_name)
        if query.mqtt_topic:
            clauses.append("mqtt_topic = ?")
            parameters.append(query.mqtt_topic)
        if query.protocol:
            clauses.append("protocol = ?")
            parameters.append(query.protocol)
        where = " WHERE " + " AND ".join(clauses) if clauses else ""
        try:
            with self._connection() as connection:
                total = int(
                    connection.execute(
                        f"SELECT COUNT(*) FROM telemetry_points{where}", tuple(parameters)
                    ).fetchone()[0]
                )
                rows = connection.execute(
                    f"SELECT * FROM telemetry_points{where} ORDER BY timestamp_ns ASC LIMIT ? OFFSET ?",
                    (*parameters, limit, offset),
                ).fetchall()
        except sqlite3.Error as exc:
            raise TelemetryStorageError(f"telemetry query failed: {exc}") from exc
        points = [self._row_to_point(row) for row in rows]
        max_points = max(1, min(query.max_points, limit))
        if len(points) > max_points:
            points = self._downsample(points, max_points)
        return TelemetryPage(points=tuple(points), total_count=total, limit=limit, offset=offset)

    def latest_values(self, device_id: str, limit: int = 200) -> Sequence[TelemetryPoint]:
        bounded_limit = max(1, min(limit, 2_000))
        sql = """
            SELECT p.* FROM telemetry_points p
            JOIN (
                SELECT metric_name, MAX(timestamp_ns) AS max_timestamp
                FROM telemetry_points WHERE device_id = ? GROUP BY metric_name
            ) latest ON latest.metric_name = p.metric_name AND latest.max_timestamp = p.timestamp_ns
            WHERE p.device_id = ? ORDER BY p.metric_name LIMIT ?
        """
        with self._connection() as connection:
            rows = connection.execute(sql, (device_id, device_id, bounded_limit)).fetchall()
        return tuple(self._row_to_point(row) for row in rows)

    def list_devices(self) -> Sequence[str]:
        with self._connection() as connection:
            rows = connection.execute(
                "SELECT DISTINCT device_id FROM telemetry_points ORDER BY device_id"
            ).fetchall()
        return tuple(str(row[0]) for row in rows)

    def list_metrics(self, device_id: str) -> Sequence[str]:
        with self._connection() as connection:
            rows = connection.execute(
                "SELECT DISTINCT metric_name FROM telemetry_points WHERE device_id = ? ORDER BY metric_name",
                (device_id,),
            ).fetchall()
        return tuple(str(row[0]) for row in rows)

    def purge_before(self, timestamp_ns: int) -> int:
        if timestamp_ns <= 0:
            return 0
        with self._connection() as connection:
            connection.execute("BEGIN IMMEDIATE")
            cursor = connection.execute(
                "DELETE FROM telemetry_points WHERE timestamp_ns < ?", (timestamp_ns,)
            )
            count = int(cursor.rowcount)
            connection.commit()
            connection.execute("PRAGMA wal_checkpoint(PASSIVE)")
        return count

    def record_rejection(self, received_timestamp_ns: int, topic: str, reason: str, payload_size: int) -> None:
        with self._connection() as connection:
            connection.execute(
                "INSERT INTO rejected_messages(received_timestamp_ns, mqtt_topic, reason, payload_size) VALUES (?, ?, ?, ?)",
                (received_timestamp_ns, topic, reason[:1_000], max(0, payload_size)),
            )
            connection.commit()

    def integrity_check(self) -> str:
        with self._connection() as connection:
            row = connection.execute("PRAGMA quick_check").fetchone()
        return str(row[0]) if row else "unknown"

    def database_size_bytes(self) -> int:
        total = 0
        for suffix in ("", "-wal", "-shm"):
            path = Path(f"{self.database_path}{suffix}")
            if path.exists():
                total += path.stat().st_size
        return total

    def checkpoint(self, truncate: bool = False) -> None:
        mode = "TRUNCATE" if truncate else "PASSIVE"
        with self._connection() as connection:
            connection.execute(f"PRAGMA wal_checkpoint({mode})")

    def close(self) -> None:
        """Connections are operation-scoped, so there is no persistent handle to close."""

    @staticmethod
    def _point_to_row(point: TelemetryPoint) -> tuple[object, ...]:
        numeric_value: float | None = None
        integer_value: int | None = None
        text_value: str | None = None
        boolean_value: int | None = None
        bytes_value: bytes | None = None
        value = point.value
        if isinstance(value, bool):
            data_type = "boolean"
            boolean_value = int(value)
        elif isinstance(value, int):
            data_type = "integer"
            integer_value = value
        elif isinstance(value, float):
            data_type = "numeric"
            numeric_value = value
        elif isinstance(value, str):
            data_type = "text"
            text_value = value
        elif isinstance(value, bytes):
            data_type = "bytes"
            bytes_value = value
        else:
            data_type = "null"
        quality = str(point.quality) if point.quality is not None else None
        protocol = str(point.protocol)
        return (
            point.timestamp_ns,
            point.received_timestamp_ns,
            point.device_id,
            point.metric_name,
            numeric_value,
            integer_value,
            text_value,
            boolean_value,
            bytes_value,
            point.unit,
            data_type,
            quality,
            json.dumps(dict(point.tags), separators=(",", ":"), sort_keys=True),
            point.mqtt_topic,
            point.mqtt_qos,
            int(point.mqtt_retain),
            protocol,
            point.sparkplug_group_id,
            point.sparkplug_edge_node_id,
            point.sparkplug_device_id,
            point.sparkplug_metric_alias,
            point.sparkplug_sequence,
        )

    @staticmethod
    def _row_to_point(row: sqlite3.Row) -> TelemetryPoint:
        data_type = str(row["data_type"])
        value: object
        if data_type == "boolean":
            value = bool(row["boolean_value"])
        elif data_type == "integer":
            value = int(row["integer_value"])
        elif data_type == "numeric":
            value = float(row["numeric_value"])
        elif data_type == "text":
            value = str(row["text_value"])
        elif data_type == "bytes":
            value = bytes(row["bytes_value"])
        else:
            value = None
        try:
            tags = json.loads(str(row["tags_json"]))
            if not isinstance(tags, dict):
                tags = {}
        except json.JSONDecodeError:
            tags = {}
        return TelemetryPoint(
            timestamp_ns=int(row["timestamp_ns"]),
            received_timestamp_ns=int(row["received_timestamp_ns"]),
            device_id=str(row["device_id"]),
            metric_name=str(row["metric_name"]),
            value=value if isinstance(value, (float, int, str, bool, bytes)) or value is None else None,
            unit=str(row["unit"]) if row["unit"] is not None else None,
            quality=str(row["quality"]) if row["quality"] is not None else None,
            tags={str(key): str(item) for key, item in tags.items()},
            mqtt_topic=str(row["mqtt_topic"]),
            mqtt_qos=int(row["mqtt_qos"]),
            mqtt_retain=bool(row["mqtt_retain"]),
            protocol=str(row["protocol"]),
            sparkplug_group_id=str(row["sparkplug_group_id"]) if row["sparkplug_group_id"] is not None else None,
            sparkplug_edge_node_id=str(row["sparkplug_edge_node_id"]) if row["sparkplug_edge_node_id"] is not None else None,
            sparkplug_device_id=str(row["sparkplug_device_id"]) if row["sparkplug_device_id"] is not None else None,
            sparkplug_metric_alias=int(row["sparkplug_metric_alias"]) if row["sparkplug_metric_alias"] is not None else None,
            sparkplug_sequence=int(row["sparkplug_sequence"]) if row["sparkplug_sequence"] is not None else None,
        )

    @staticmethod
    def _downsample(points: Sequence[TelemetryPoint], max_points: int) -> list[TelemetryPoint]:
        if len(points) <= max_points:
            return list(points)
        if max_points <= 2:
            return [points[0], points[-1]][:max_points]
        step = (len(points) - 1) / (max_points - 1)
        indexes = {round(index * step) for index in range(max_points)}
        return [points[index] for index in sorted(indexes)]
