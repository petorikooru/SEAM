from __future__ import annotations

import pytest

pytest.importorskip("PySide6")

from kai_bridge_inspection.daemon.service import _RejectionLogLimiter


def test_rejection_log_limiter_suppresses_repeated_topic_family() -> None:
    limiter = _RejectionLogLimiter(interval_seconds=60.0)
    first, suppressed = limiter.check(
        "spBv1.0/group/DDATA/node/device-1", ValueError("bad payload")
    )
    second, current_suppressed = limiter.check(
        "spBv1.0/group/DDATA/node/device-2", ValueError("another bad payload")
    )

    assert first
    assert suppressed == 0
    assert not second
    assert current_suppressed == 1
