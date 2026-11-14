from __future__ import annotations

import csv
from dataclasses import replace
from pathlib import Path

from kai_bridge_inspection.domain.models import HistoricalQuery, TelemetryPoint
from kai_bridge_inspection.telemetry.query_service import TelemetryQueryService
from kai_bridge_inspection.telemetry.sqlite_repository import SQLiteTelemetryRepository


def point(timestamp_ns: int, metric: str, value: object) -> TelemetryPoint:
    return TelemetryPoint(
        timestamp_ns=timestamp_ns,
        received_timestamp_ns=timestamp_ns + 10,
        device_id="sensor-01",
        metric_name=metric,
        value=value,  # type: ignore[arg-type]
        unit=None,
        quality="good",
        tags={"site": "north"},
        mqtt_topic="factory/sensor-01",
        mqtt_qos=1,
        mqtt_retain=False,
        protocol="json",
    )


def test_write_query_latest_and_retention(tmp_path: Path) -> None:
    repository = SQLiteTelemetryRepository(tmp_path / "telemetry.db")
    assert repository.write_batch(
        [
            point(100, "temperature", 20.0),
            point(200, "temperature", 21.0),
            point(200, "online", True),
            point(300, "label", "ok"),
        ]
    ) == 4
    page = repository.query(
        HistoricalQuery(device_id="sensor-01", metric_name="temperature", limit=10)
    )
    assert [item.value for item in page.points] == [20.0, 21.0]
    latest = {item.metric_name: item.value for item in repository.latest_values("sensor-01")}
    assert latest["temperature"] == 21.0
    assert latest["online"] is True
    assert repository.purge_before(250) == 3
    assert repository.integrity_check() == "ok"


def test_csv_exports_all_sensor_metrics_beyond_history_limit(tmp_path: Path) -> None:
    repository = SQLiteTelemetryRepository(tmp_path / "telemetry.db")
    motion = point(100, "ACC/X", 1.0)
    auxiliary = point(100, "TEMPERATURE", 23.5)
    repository.write_batch([motion] * 50_000 + [
        auxiliary,
        replace(auxiliary, device_id="sensor-02"),
        replace(auxiliary, timestamp_ns=101),
    ])

    path = tmp_path / "sensor.csv"
    query = HistoricalQuery(device_id="sensor-01", end_timestamp_ns=100)
    assert TelemetryQueryService(repository).export_csv(path, query) == 50_001
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    assert len(rows) == 50_001
    assert rows[0]["metric_name"] == "ACC/X"
    assert rows[-1]["metric_name"] == "TEMPERATURE"
    assert rows[-1]["value"] == "23.5"
