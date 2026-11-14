from __future__ import annotations

import pytest

from kai_bridge_inspection.daemon.lifecycle import DaemonLifecycle
from kai_bridge_inspection.domain.enums import DaemonState
from kai_bridge_inspection.domain.errors import DaemonLifecycleError


def test_valid_lifecycle_path() -> None:
    lifecycle = DaemonLifecycle()
    lifecycle.transition(DaemonState.STARTING)
    lifecycle.transition(DaemonState.IDLE)
    lifecycle.transition(DaemonState.CONNECTING)
    lifecycle.transition(DaemonState.RUNNING)
    lifecycle.transition(DaemonState.PAUSED)
    assert lifecycle.state is DaemonState.PAUSED


def test_invalid_transition_is_rejected() -> None:
    lifecycle = DaemonLifecycle()
    with pytest.raises(DaemonLifecycleError):
        lifecycle.transition(DaemonState.RUNNING)
