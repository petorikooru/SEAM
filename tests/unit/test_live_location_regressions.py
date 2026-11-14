from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
QML = PROJECT_ROOT / "src" / "kai_bridge_inspection" / "qml"
BACKEND = PROJECT_ROOT / "src" / "kai_bridge_inspection" / "controllers" / "backend_controller.py"


def test_location_preserves_metrics_from_partial_telemetry_batches() -> None:
    source = (QML / "pages" / "Location.qml").read_text(encoding="utf-8")
    assert "page.updateLiveMetrics(data, false)" in source
    assert "updateLiveMetrics(selectedSensorData, true)" in source
    assert "BAT_FUEL_GAUGE_REPSOC" in source
    assert "selectedSensorData[key] = data[key]" in source


def test_location_sensor_charts_are_content_sized_and_can_shrink() -> None:
    location = (QML / "pages" / "Location.qml").read_text(encoding="utf-8")
    panel = (QML / "components" / "sensor" / "MotionChartPanel.qml").read_text(encoding="utf-8")
    assert "sensorSectionContent.implicitHeight + 32" in location
    assert "sensorDetailPane.implicitHeight" in location
    assert "Layout.minimumWidth: 0" in panel
    assert "Flow {" in panel


def test_live_chart_pages_release_global_pause_and_use_sixty_second_window() -> None:
    location = (QML / "pages" / "Location.qml").read_text(encoding="utf-8")
    sensor = (QML / "pages" / "Sensor.qml").read_text(encoding="utf-8")
    assert location.count("setLiveChartsPaused(false)") >= 2
    assert sensor.count("setLiveChartsPaused(false)") >= 2
    assert "initialXMax: 1" not in sensor
    assert sensor.count("initialXMax: 60") >= 2


def test_missing_telemetry_is_not_fabricated_as_zero() -> None:
    backend = BACKEND.read_text(encoding="utf-8")
    sensor_data_block = backend[backend.index("def getSensorData"):backend.index("def deleteSensor")]
    assert '"temp": 0.0' not in sensor_data_block
    assert '"battery": 0.0' not in sensor_data_block


def test_pause_controller_renders_before_freeze_and_after_resume() -> None:
    backend = BACKEND.read_text(encoding="utf-8")
    block = backend[backend.index("def setLiveChartsPaused"):backend.index("@Property(str, notify=nodeRedConfigChanged)")]
    assert block.index("self._render_charts()") < block.index("self._charts_paused = paused")
    assert "if not paused:" in block
