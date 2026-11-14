"""Optional InfluxDB adapter boundary.

The base distribution intentionally does not import or require influxdb-client.
Deployments that need remote high-volume storage can implement this protocol
adapter behind the existing TelemetryRepository interface.
"""

from __future__ import annotations

from collections.abc import Iterator, Sequence

from kai_bridge_inspection.domain.errors import ConfigurationError
from kai_bridge_inspection.domain.models import HistoricalQuery, TelemetryPage, TelemetryPoint


class InfluxTelemetryRepository:
    def __init__(self, *_: object, **__: object) -> None:
        raise ConfigurationError(
            "InfluxDB support is optional and not enabled in the base installation; "
            "install the 'influx' extra and provide a deployment-specific adapter."
        )

    def write_batch(self, points: Sequence[TelemetryPoint]) -> int:
        raise NotImplementedError

    def query(self, query: HistoricalQuery) -> TelemetryPage:
        raise NotImplementedError

    def iter_points(self, query: HistoricalQuery) -> Iterator[TelemetryPoint]:
        raise NotImplementedError

    def latest_values(self, device_id: str, limit: int = 200) -> Sequence[TelemetryPoint]:
        raise NotImplementedError

    def list_devices(self) -> Sequence[str]:
        raise NotImplementedError

    def list_metrics(self, device_id: str) -> Sequence[str]:
        raise NotImplementedError

    def purge_before(self, timestamp_ns: int) -> int:
        raise NotImplementedError

    def close(self) -> None:
        return
