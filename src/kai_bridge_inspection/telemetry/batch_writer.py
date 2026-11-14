"""Bounded single-writer telemetry batching worker."""

from __future__ import annotations

import queue
import threading
import time
from collections.abc import Callable, Sequence
from dataclasses import dataclass

from kai_bridge_inspection.domain.enums import DropPolicy
from kai_bridge_inspection.domain.interfaces import TelemetryRepository
from kai_bridge_inspection.domain.models import TelemetryPoint


@dataclass(frozen=True, slots=True)
class WriterSnapshot:
    queue_depth: int
    queue_capacity: int
    points_accepted: int
    points_written: int
    points_dropped: int
    write_failures: int
    last_successful_write_timestamp_ns: int
    healthy: bool


class TelemetryBatchWriter:
    """Owns the only telemetry write path used by the daemon."""

    _SENTINEL = object()

    def __init__(
        self,
        repository: TelemetryRepository,
        *,
        queue_capacity: int = 2_048,
        batch_size: int = 1_000,
        flush_interval_seconds: float = 0.5,
        drop_policy: DropPolicy = DropPolicy.DROP_NEWEST,
        on_batch_written: Callable[[Sequence[TelemetryPoint]], None] | None = None,
    ) -> None:
        self._repository = repository
        self._queue: queue.Queue[Sequence[TelemetryPoint] | object] = queue.Queue(
            maxsize=max(8, queue_capacity)
        )
        self._batch_size = max(1, batch_size)
        self._flush_interval_seconds = max(0.05, flush_interval_seconds)
        self._drop_policy = drop_policy
        self._on_batch_written = on_batch_written
        self._stop_event = threading.Event()
        self._thread = threading.Thread(target=self._run, name="TelemetryDbWriter", daemon=True)
        self._lock = threading.Lock()
        self._accepted = 0
        self._written = 0
        self._dropped = 0
        self._failures = 0
        self._last_write_ns = 0
        self._healthy = True
        self._thread.start()

    def submit(self, points: Sequence[TelemetryPoint], timeout_seconds: float = 0.05) -> bool:
        batch = tuple(points)
        if not batch or self._stop_event.is_set():
            return False
        try:
            self._queue.put(batch, timeout=max(0.0, timeout_seconds))
            with self._lock:
                self._accepted += len(batch)
            return True
        except queue.Full:
            if self._drop_policy == DropPolicy.DROP_OLDEST:
                try:
                    oldest = self._queue.get_nowait()
                    self._queue.task_done()
                    if oldest is not self._SENTINEL:
                        with self._lock:
                            self._dropped += len(oldest)  # type: ignore[arg-type]
                    self._queue.put_nowait(batch)
                    with self._lock:
                        self._accepted += len(batch)
                    return True
                except queue.Empty:
                    pass
            with self._lock:
                self._dropped += len(batch)
            return False

    def flush(self, timeout_seconds: float = 10.0) -> bool:
        deadline = time.monotonic() + max(0.0, timeout_seconds)
        while time.monotonic() < deadline:
            if self._queue.unfinished_tasks == 0:
                return True
            time.sleep(0.02)
        return self._queue.unfinished_tasks == 0

    def stop(self, timeout_seconds: float = 10.0) -> None:
        if self._stop_event.is_set():
            return
        self._stop_event.set()
        try:
            self._queue.put(self._SENTINEL, timeout=0.5)
        except queue.Full:
            pass
        self._thread.join(timeout=max(0.1, timeout_seconds))

    def snapshot(self) -> WriterSnapshot:
        with self._lock:
            return WriterSnapshot(
                queue_depth=self._queue.qsize(),
                queue_capacity=self._queue.maxsize,
                points_accepted=self._accepted,
                points_written=self._written,
                points_dropped=self._dropped,
                write_failures=self._failures,
                last_successful_write_timestamp_ns=self._last_write_ns,
                healthy=self._healthy and self._thread.is_alive(),
            )

    def _run(self) -> None:
        pending: list[TelemetryPoint] = []
        pending_queue_items = 0
        deadline = time.monotonic() + self._flush_interval_seconds
        while True:
            timeout = max(0.0, deadline - time.monotonic())
            item: Sequence[TelemetryPoint] | object | None = None
            try:
                item = self._queue.get(timeout=timeout)
            except queue.Empty:
                pass
            if item is self._SENTINEL:
                self._queue.task_done()
                self._flush_pending(pending)
                for _ in range(pending_queue_items):
                    self._queue.task_done()
                return
            if item is not None:
                pending.extend(item)  # type: ignore[arg-type]
                pending_queue_items += 1
            if len(pending) >= self._batch_size or time.monotonic() >= deadline:
                self._flush_pending(pending)
                pending.clear()
                for _ in range(pending_queue_items):
                    self._queue.task_done()
                pending_queue_items = 0
                deadline = time.monotonic() + self._flush_interval_seconds
            if self._stop_event.is_set() and self._queue.empty():
                self._flush_pending(pending)
                for _ in range(pending_queue_items):
                    self._queue.task_done()
                return

    def _flush_pending(self, pending: Sequence[TelemetryPoint]) -> None:
        if not pending:
            return
        try:
            written = self._repository.write_batch(pending)
            with self._lock:
                self._written += written
                self._last_write_ns = time.time_ns()
                self._healthy = True
            if self._on_batch_written is not None:
                self._on_batch_written(tuple(pending))
        except Exception:
            with self._lock:
                self._failures += 1
                self._healthy = False
