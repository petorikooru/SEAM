"""Historical telemetry query and export service."""

from __future__ import annotations

import csv
from collections.abc import Iterator
from concurrent.futures import CancelledError
from contextlib import contextmanager
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Event

from xlsxwriter import Workbook  # type: ignore[import-untyped]

from kai_bridge_inspection.domain.interfaces import TelemetryRepository
from kai_bridge_inspection.domain.models import HistoricalQuery, TelemetryPage

_EXPORT_COLUMNS = (
    "timestamp_ns",
    "received_timestamp_ns",
    "device_id",
    "metric_name",
    "value",
    "unit",
    "quality",
    "mqtt_topic",
    "mqtt_qos",
    "mqtt_retain",
    "protocol",
    "sparkplug_group_id",
    "sparkplug_edge_node_id",
    "sparkplug_device_id",
    "sparkplug_metric_alias",
    "sparkplug_sequence",
)
_XLSX_ROWS = 1_048_576


def _check_cancelled(stop: Event | None) -> None:
    if stop is not None and stop.is_set():
        raise CancelledError


@contextmanager
def _export_destination(path: Path, stop: Event | None) -> Iterator[Path]:
    _check_cancelled(stop)
    path.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix=".seam-export-", dir=path.parent) as directory:
        staged = Path(directory) / path.name
        yield staged
        _check_cancelled(stop)
        staged.replace(path)


class TelemetryQueryService:
    def __init__(self, repository: TelemetryRepository) -> None:
        self.repository = repository

    def query(self, query: HistoricalQuery) -> TelemetryPage:
        return self.repository.query(query)

    def export_csv(self, path: Path, query: HistoricalQuery, stop: Event | None = None) -> int:
        count = 0
        with _export_destination(path, stop) as staged, staged.open(
            "w", newline="", encoding="utf-8"
        ) as handle:
            writer = csv.writer(handle)
            writer.writerow(_EXPORT_COLUMNS)
            for row in self._export_rows(query, stop):
                writer.writerow(row)
                count += 1
        return count

    def export_xlsx(self, path: Path, query: HistoricalQuery, stop: Event | None = None) -> None:
        with _export_destination(path, stop) as staged:
            workbook = Workbook(staged, {
                "constant_memory": True,
                "strings_to_formulas": False,
                "strings_to_urls": False,
                "tmpdir": str(staged.parent),
            })
            try:
                sheet = workbook.add_worksheet()
                sheet.write_row(0, 0, _EXPORT_COLUMNS)
                row_number = 1
                for row in self._export_rows(query, stop):
                    if row_number == _XLSX_ROWS:
                        sheet = workbook.add_worksheet()
                        sheet.write_row(0, 0, _EXPORT_COLUMNS)
                        row_number = 1
                    # Excel numbers cannot preserve nanosecond timestamps.
                    values = [str(row[0]), str(row[1]), *row[2:]]
                    value = values[4]
                    if isinstance(value, bytes) or (type(value) is int and abs(value) >= 10**15):
                        values[4] = str(value)
                    sheet.write_row(row_number, 0, values)
                    row_number += 1

                _check_cancelled(stop)
                workbook.close()
            finally:
                # Close scratch streams even when finalizing the workbook was skipped.
                for worksheet in workbook.worksheets():
                    worksheet._opt_close()

    def _export_rows(self, query: HistoricalQuery, stop: Event | None) -> Iterator[tuple[object, ...]]:
        for point in self.repository.iter_points(query):
            _check_cancelled(stop)
            yield (
                point.timestamp_ns,
                point.received_timestamp_ns,
                point.device_id,
                point.metric_name,
                point.value,
                point.unit or "",
                point.quality or "",
                point.mqtt_topic,
                point.mqtt_qos,
                point.mqtt_retain,
                point.protocol,
                point.sparkplug_group_id or "",
                point.sparkplug_edge_node_id or "",
                point.sparkplug_device_id or "",
                point.sparkplug_metric_alias if point.sparkplug_metric_alias is not None else "",
                point.sparkplug_sequence if point.sparkplug_sequence is not None else "",
            )
