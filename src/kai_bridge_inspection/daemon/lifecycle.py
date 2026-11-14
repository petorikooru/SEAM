"""Explicit daemon lifecycle state machine."""

from __future__ import annotations

import threading
from collections.abc import Callable

from kai_bridge_inspection.domain.enums import DaemonState
from kai_bridge_inspection.domain.errors import DaemonLifecycleError

_ALLOWED_TRANSITIONS: dict[DaemonState, frozenset[DaemonState]] = {
    DaemonState.STOPPED: frozenset({DaemonState.STARTING}),
    DaemonState.STARTING: frozenset({DaemonState.IDLE, DaemonState.CONNECTING, DaemonState.FAILED, DaemonState.STOPPING}),
    DaemonState.IDLE: frozenset({DaemonState.CONNECTING, DaemonState.STOPPING, DaemonState.FAILED}),
    DaemonState.CONNECTING: frozenset({DaemonState.RUNNING, DaemonState.RECONNECTING, DaemonState.PAUSED, DaemonState.FAILED, DaemonState.STOPPING}),
    DaemonState.RUNNING: frozenset({DaemonState.PAUSED, DaemonState.RECONNECTING, DaemonState.STOPPING, DaemonState.FAILED}),
    DaemonState.PAUSED: frozenset({DaemonState.CONNECTING, DaemonState.IDLE, DaemonState.STOPPING, DaemonState.FAILED}),
    DaemonState.RECONNECTING: frozenset({DaemonState.RUNNING, DaemonState.PAUSED, DaemonState.STOPPING, DaemonState.FAILED}),
    DaemonState.STOPPING: frozenset({DaemonState.STOPPED, DaemonState.FAILED}),
    DaemonState.FAILED: frozenset({DaemonState.STARTING, DaemonState.STOPPING, DaemonState.STOPPED}),
}


class DaemonLifecycle:
    """Thread-safe state transition validator."""

    def __init__(
        self,
        initial_state: DaemonState = DaemonState.STOPPED,
        on_change: Callable[[DaemonState], None] | None = None,
    ) -> None:
        self._state = initial_state
        self._on_change = on_change
        self._lock = threading.Lock()

    @property
    def state(self) -> DaemonState:
        with self._lock:
            return self._state

    def transition(self, target: DaemonState) -> DaemonState:
        with self._lock:
            if target == self._state:
                return self._state
            if target not in _ALLOWED_TRANSITIONS[self._state]:
                raise DaemonLifecycleError(f"invalid daemon transition {self._state} -> {target}")
            self._state = target
        if self._on_change is not None:
            self._on_change(target)
        return target
