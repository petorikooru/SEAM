"""Historical telemetry query and export service."""

from __future__ import annotations

import csv
from pathlib import Path

from kai_bridge_inspection.domain.interfaces import TelemetryRepository
from kai_bridge_inspection.domain.models import HistoricalQuery, TelemetryPage


class TelemetryQueryService:
    def __init__(self, repository: TelemetryRepository) -> None:
        self.repository = repository

    def query(self, query: HistoricalQuery) -> TelemetryPage:
        return self.repository.query(query)

    def export_csv(self, path: Path, query: HistoricalQuery) -> int:
        page = self.repository.query(
            HistoricalQuery(
                start_timestamp_ns=query.start_timestamp_ns,
                end_timestamp_ns=query.end_timestamp_ns,
                device_id=query.device_id,
                metric_name=query.metric_name,
                mqtt_topic=query.mqtt_topic,
                protocol=query.protocol,
                limit=50_000,
                max_points=50_000,
            )
        )
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.writer(handle)
            writer.writerow(
                [
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
                ]
            )
            for point in page.points:
                writer.writerow(
                    [
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
                    ]
                )
        return len(page.points)
