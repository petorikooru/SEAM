from __future__ import annotations

from pathlib import Path

from kai_bridge_inspection.domain.models import TelemetryPoint
from kai_bridge_inspection.telemetry.batch_writer import TelemetryBatchWriter
from kai_bridge_inspection.telemetry.sqlite_repository import SQLiteTelemetryRepository


def test_writer_flushes_pending_points(tmp_path: Path) -> None:
    repository = SQLiteTelemetryRepository(tmp_path / "telemetry.db")
    writer = TelemetryBatchWriter(repository, batch_size=2, flush_interval_seconds=0.05)
    point = TelemetryPoint(
        1, 1, "d", "m", 1.0, None, "good", {}, "t", 0, False, "json"
    )
    assert writer.submit([point, point])
    assert writer.flush(2.0)
    writer.stop(2.0)
    assert writer.snapshot().points_written == 2
