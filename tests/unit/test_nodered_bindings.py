from __future__ import annotations

from pathlib import Path

import pytest

from kai_bridge_inspection.domain.errors import ConfigurationError
from kai_bridge_inspection.settings.repository import SettingsRepository


def test_default_node_red_bindings_and_update(tmp_path: Path) -> None:
    repository = SettingsRepository(tmp_path / "settings.db")
    assert repository.get_node_red_bindings() == {
        "accelerometer": "kai/accelerometer",
        "inclinometer": "kai/inclinometer",
        "indicators": "kai/indicators",
        "location": "kai/location",
    }
    repository.set_node_red_binding("accelerometer", "/custom/accel/")
    assert repository.get_node_red_bindings()["accelerometer"] == "custom/accel"


def test_rejects_unknown_binding(tmp_path: Path) -> None:
    repository = SettingsRepository(tmp_path / "settings.db")
    with pytest.raises(ConfigurationError):
        repository.set_node_red_binding("unknown-widget", "kai/unknown")


def test_bulk_binding_update_is_normalized(tmp_path: Path) -> None:
    repository = SettingsRepository(tmp_path / "settings.db")
    repository.set_node_red_bindings(
        {
            "accelerometer": "/bridge/a/",
            "inclinometer": "bridge/i",
            "indicators": "bridge/status",
            "location": "/bridge/location",
        }
    )
    assert repository.get_node_red_bindings() == {
        "accelerometer": "bridge/a",
        "inclinometer": "bridge/i",
        "indicators": "bridge/status",
        "location": "bridge/location",
    }


def test_bulk_binding_update_is_atomic_on_validation_failure(tmp_path: Path) -> None:
    repository = SettingsRepository(tmp_path / "settings.db")
    before = repository.get_node_red_bindings()
    with pytest.raises(ConfigurationError):
        repository.set_node_red_bindings(
            {
                "accelerometer": "custom/a",
                "inclinometer": "contains spaces",
                "indicators": "custom/status",
                "location": "custom/location",
            }
        )
    assert repository.get_node_red_bindings() == before
