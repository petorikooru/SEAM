from __future__ import annotations

from pathlib import Path

from kai_bridge_inspection.domain.models import HistoricalQuery, TelemetryPoint
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
