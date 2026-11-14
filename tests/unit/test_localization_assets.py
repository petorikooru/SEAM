from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
I18N_DIR = ROOT / "src" / "kai_bridge_inspection" / "qml" / "i18n"


def _flatten_keys(value: dict[str, object], prefix: str = "") -> set[str]:
    keys: set[str] = set()
    for key, item in value.items():
        qualified = f"{prefix}.{key}" if prefix else key
        if isinstance(item, dict):
            keys.update(_flatten_keys(item, qualified))
        else:
            keys.add(qualified)
    return keys


def _expected_js(value: dict[str, object]) -> str:
    return f'.pragma library\n\nvar strings = {json.dumps(value, ensure_ascii=False, indent=2)};\n'


def test_translation_files_have_matching_keys_and_generated_runtime_assets() -> None:
    english = json.loads((I18N_DIR / "en.json").read_text(encoding="utf-8"))
    indonesian = json.loads((I18N_DIR / "id.json").read_text(encoding="utf-8"))

    assert _flatten_keys(english) == _flatten_keys(indonesian)
    assert (I18N_DIR / "en.js").read_text(encoding="utf-8") == _expected_js(english)
    assert (I18N_DIR / "id.js").read_text(encoding="utf-8") == _expected_js(indonesian)


def test_sensor_page_declares_accelerometer_and_inclinometer_columns() -> None:
    qml_root = I18N_DIR.parent
    sensor_qml = (qml_root / "pages" / "Sensor.qml").read_text(encoding="utf-8")
    assert 'objectName: "motionChartsGrid"' in sensor_qml
    assert "columns: width >= 980 ? 2 : 1" in sensor_qml
    assert "id: accelPanel" in sensor_qml
    assert "id: inclinoPanel" in sensor_qml
    assert sensor_qml.count("onHistoryRequested: historyChartDialog.openMotion") == 2
    assert (qml_root / "components" / "sensor" / "MotionChart.qml").is_file()
    assert (qml_root / "components" / "sensor" / "MotionChartPanel.qml").is_file()


def test_node_red_settings_replace_desktop_broker_controls() -> None:
    qml_root = I18N_DIR.parent
    settings = (qml_root / "pages" / "Settings.qml").read_text(encoding="utf-8")
    add_sensor = (qml_root / "dialogs" / "AddSensor.qml").read_text(encoding="utf-8")
    sensor_settings = (qml_root / "dialogs" / "SensorSettings.qml").read_text(encoding="utf-8")

    assert "MQTT ownership" in settings
    assert "saveProfileSensor" in add_sensor
    assert "updateProfileSensor" in sensor_settings
    assert "BrokerComboBox" not in sensor_settings
    assert "updateSensorSettings" not in sensor_settings


def test_motion_panel_header_and_toolbar_structure() -> None:
    qml_root = I18N_DIR.parent
    panel = (qml_root / "components" / "sensor" / "MotionChartPanel.qml").read_text(encoding="utf-8")
    visible_series = panel.index('I18n.t("common.visibleSeries"')
    toolbar = panel.index('I18n.t("common.freeze"')
    chart_host = panel.index('id: chartHost')
    assert visible_series < toolbar < chart_host
    assert "Layout.alignment: Qt.AlignRight | Qt.AlignVCenter" in panel


def test_icon_scale_and_shared_component_extraction() -> None:
    qml_root = I18N_DIR.parent
    theme = (qml_root / "Theme.qml").read_text(encoding="utf-8")
    assert "iconSizeSmall: 12" in theme
    assert "iconSize: 14" in theme
    assert "iconSizeLarge: 16" in theme
    for filename in ("ActionButton.qml", "MetricBox.qml", "StepBadge.qml"):
        assert (qml_root / "common" / filename).is_file()


def test_sidebar_catalog_refresh_forces_existing_location_delegates_to_reload() -> None:
    qml_root = I18N_DIR.parent
    main = (qml_root / "Main.qml").read_text(encoding="utf-8")
    sidebar = (qml_root / "Sidebar.qml").read_text(encoding="utf-8")

    assert "property int sidebarDataRevision" in main
    assert "sidebarDataRevision += 1" in main
    assert "dataRevision: root.sidebarDataRevision" in main
    assert "property int dataRevision" in sidebar
    assert "const revision = sidebarRoot.dataRevision" in sidebar
    assert "getLocationData(locationKey)" in sidebar


def test_location_page_reuses_sensor_motion_chart_components() -> None:
    qml_root = I18N_DIR.parent
    location = (qml_root / "pages" / "Location.qml").read_text(encoding="utf-8")

    assert 'import "../components/sensor"' in location
    assert location.count("MotionChartPanel {") == 2
    assert location.count("MotionChart {") == 2
    assert "id: accelChart" in location
    assert "id: inclinoChart" in location
