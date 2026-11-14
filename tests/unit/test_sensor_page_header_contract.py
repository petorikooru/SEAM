from pathlib import Path

import pytest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SOURCE_QML = PROJECT_ROOT / "src" / "kai_bridge_inspection" / "qml"
BUILD_QML = PROJECT_ROOT / "build" / "lib" / "kai_bridge_inspection" / "qml"


def test_sensor_page_keeps_identity_header_before_telemetry_charts() -> None:
    sensor_page = (SOURCE_QML / "pages" / "Sensor.qml").read_text(encoding="utf-8")

    header_position = sensor_page.index("SensorHeaderCard {")
    chart_position = sensor_page.index('objectName: "motionChartsGrid"')

    assert header_position < chart_position
    assert 'objectName: "sensorHeaderCardInstance"' in sensor_page


def test_sensor_header_exposes_identity_description_and_actions() -> None:
    header = (
        SOURCE_QML / "components" / "sensor" / "SensorHeaderCard.qml"
    ).read_text(encoding="utf-8")

    required_objects = {
        "sensorNameLabel",
        "sensorDescriptionLabel",
        "sensorEditButton",
        "sensorSettingsButton",
        "sensorHistoryButton",
        "sensorExportButton",
    }

    for object_name in required_objects:
        assert f'objectName: "{object_name}"' in header

    assert "card.sensorData.name || card.sensorName" in header
    assert "card.sensorData.description" in header


def test_sensor_identity_and_map_share_responsive_overview_grid() -> None:
    sensor_page = (SOURCE_QML / "pages" / "Sensor.qml").read_text(encoding="utf-8")

    grid_position = sensor_page.index('objectName: "sensorIdentityMapGrid"')
    header_position = sensor_page.index('objectName: "sensorHeaderCardInstance"')
    map_position = sensor_page.index('objectName: "sensorMapCardInstance"')
    metrics_position = sensor_page.index('objectName: "sensorMetricsGrid"')

    assert grid_position < header_position < map_position < metrics_position
    assert "columns: width >= 960 ? 2 : 1" in sensor_page
    assert sensor_page.count("Layout.minimumHeight: 320") >= 2


def test_sensor_qml_build_mirror_matches_source() -> None:
    if not BUILD_QML.is_dir():
        pytest.skip("clean source package has no generated build/lib mirror")

    relative_paths = (
        Path("pages/Sensor.qml"),
        Path("components/sensor/SensorHeaderCard.qml"),
    )

    for relative_path in relative_paths:
        assert (SOURCE_QML / relative_path).read_bytes() == (
            BUILD_QML / relative_path
        ).read_bytes()
