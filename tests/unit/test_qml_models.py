from __future__ import annotations

import pytest

pytest.importorskip("PySide6")

from kai_bridge_inspection.models.device_list_model import DeviceListModel, DeviceRow


def test_device_model_roles_and_count() -> None:
    model = DeviceListModel()
    model.replace([DeviceRow("d1", "Device 1", True, 3)])
    assert model.rowCount() == 1
    assert bytes(model.roleNames()[model.DeviceIdRole]) == b"deviceId"
