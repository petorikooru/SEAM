"""Compatibility alias definitions discovered in the supplied NemoSense backend."""

from __future__ import annotations

NEMOSENSE_DEFAULT_ALIASES: dict[int, str] = {
    1: "ACC/TEMPERATURE",
    2: "ACC/ROLL",
    3: "ACC/PITCH",
    4: "VAR/DOUBLE",
    5: "VAR/STRING",
    16: "ACC/X",
    17: "ACC/Y",
    18: "ACC/Z",
}
