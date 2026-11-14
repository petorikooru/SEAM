"""Secret-provider implementations."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True, slots=True)
class EnvironmentSecretProvider:
    """Resolve secrets from environment variables or an optional env file."""

    env_file: Path | None = None

    def get_secret(self, reference: str) -> str | None:
        key = reference.strip()
        if not key:
            return None
        direct = os.getenv(key)
        if direct is not None:
            return direct
        if self.env_file is None or not self.env_file.exists():
            return None
        for raw_line in self.env_file.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            name, value = line.split("=", 1)
            if name.strip() == key:
                return value.strip().strip('"').strip("'")
        return None
