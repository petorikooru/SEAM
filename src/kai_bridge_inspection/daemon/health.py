"""Mutable daemon statistics container guarded by a lock."""

from __future__ import annotations

import threading
import time
from dataclasses import asdict, dataclass


@dataclass(slots=True)
class MutableIngestionStatistics:
    started_timestamp_ns: int
    messages_received: int = 0
    messages_parsed: int = 0
    messages_rejected: int = 0
    messages_ignored: int = 0
    telemetry_points_created: int = 0
    telemetry_points_written: int = 0
    write_failures: int = 0
    messages_dropped: int = 0
    reconnect_count: int = 0
    sparkplug_payloads_decoded: int = 0
    sparkplug_decode_failures: int = 0
    birth_messages_received: int = 0
    death_messages_received: int = 0
    unknown_metric_aliases: int = 0
    last_successful_write_timestamp_ns: int = 0


class StatisticsTracker:
    def __init__(self) -> None:
        self._stats = MutableIngestionStatistics(started_timestamp_ns=time.time_ns())
        self._lock = threading.Lock()

    def increment(self, field: str, amount: int = 1) -> None:
        with self._lock:
            current = getattr(self._stats, field)
            setattr(self._stats, field, int(current) + amount)

    def set_value(self, field: str, value: int) -> None:
        with self._lock:
            setattr(self._stats, field, value)

    def snapshot(self) -> dict[str, object]:
        with self._lock:
            return dict(asdict(self._stats))
