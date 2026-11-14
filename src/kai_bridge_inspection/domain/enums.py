"""Domain enumerations shared by the desktop and daemon processes."""

from __future__ import annotations

from enum import StrEnum


class DaemonState(StrEnum):
    STOPPED = "STOPPED"
    STARTING = "STARTING"
    IDLE = "IDLE"
    CONNECTING = "CONNECTING"
    RUNNING = "RUNNING"
    PAUSED = "PAUSED"
    RECONNECTING = "RECONNECTING"
    STOPPING = "STOPPING"
    FAILED = "FAILED"


class ProtocolName(StrEnum):
    JSON = "json"
    SPARKPLUG_B = "sparkplug_b"
    NODE_RED = "node_red"


class Quality(StrEnum):
    GOOD = "good"
    UNCERTAIN = "uncertain"
    BAD = "bad"


class DropPolicy(StrEnum):
    DROP_NEWEST = "drop_newest"
    DROP_OLDEST = "drop_oldest"
