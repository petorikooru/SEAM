from __future__ import annotations

from pathlib import Path

import pytest

from kai_bridge_inspection.domain.errors import ConfigurationError
from kai_bridge_inspection.domain.models import LocationRecord, SensorRecord
from kai_bridge_inspection.settings.repository import SettingsRepository


def test_migration_and_catalog_round_trip(tmp_path: Path) -> None:
    repository = SettingsRepository(tmp_path / "settings.db")
    assert repository.get_setting("theme") == "dark"

    broker_id = repository.add_broker(
        "Local", "127.0.0.1", 1883, username="operator", password_env="MQTT_PASSWORD"
    )
    repository.replace_subscription(broker_id, "factory/+/telemetry", qos=1)
    brokers = repository.list_brokers()
    assert brokers[0].subscriptions[0].topic == "factory/+/telemetry"
    assert brokers[0].password_env == "MQTT_PASSWORD"

    repository.save_location(LocationRecord("Bridge-01", "North span", -6.9, 107.6))
    saved = repository.save_sensor(
        SensorRecord(
            name="Sensor-01",
            description="Pier accelerometer",
            location_name="Bridge-01",
            broker_id=broker_id,
            mqtt_server="127.0.0.1",
            mqtt_port=1883,
            mqtt_topic="factory/bridge-01/telemetry",
            mqtt_username="operator",
            password_env="MQTT_PASSWORD",
            device_id="sensor-01",
            device_type="test",
            sample_rate=250,
            trigger_mode="Continuous",
            latitude=-6.9,
            longitude=107.6,
        )
    )
    assert saved
    sensor = repository.get_sensor("Sensor-01")
    assert sensor is not None
    assert sensor.device_id == "sensor-01"
    assert sensor.websocket_endpoint == "kai/sensors/sensor-01"
    assert repository.list_node_red_sensor_endpoints() == {
        "kai/sensors/sensor-01": "sensor-01"
    }
    assert repository.list_sensors("Bridge-01")[0].name == "Sensor-01"


def test_topic_filter_validation() -> None:
    assert SettingsRepository.is_valid_topic_filter("a/+/c")
    assert SettingsRepository.is_valid_topic_filter("spBv1.0/#")
    assert not SettingsRepository.is_valid_topic_filter("a/#/c")
    assert not SettingsRepository.is_valid_topic_filter("a+b")


def test_broker_delete_is_blocked_while_sensors_use_it(tmp_path: Path) -> None:
    repository = SettingsRepository(tmp_path / "settings.db")
    broker_id = repository.add_broker("Local", "127.0.0.1", 1883)
    repository.save_location(LocationRecord("Guarded-Bridge", "", 0.0, 0.0))
    repository.save_sensor(
        SensorRecord(
            name="Sensor-Guarded",
            description="",
            location_name="Guarded-Bridge",
            broker_id=broker_id,
            mqtt_server="127.0.0.1",
            mqtt_port=1883,
            mqtt_topic="spBv1.0/#",
            mqtt_username="",
            password_env="",
            device_id="sensor-guarded",
            device_type="test",
            sample_rate=250,
            trigger_mode="Continuous",
            latitude=0.0,
            longitude=0.0,
        )
    )

    assert repository.sensor_names_for_broker(broker_id) == ["Sensor-Guarded"]
    with pytest.raises(ConfigurationError, match="Sensor-Guarded"):
        repository.delete_broker(broker_id)
    assert repository.list_brokers()[0].broker_id == broker_id

    repository.delete_sensor("Sensor-Guarded")
    repository.delete_broker(broker_id)
    assert repository.list_brokers() == []


def test_each_sensor_requires_a_unique_websocket_endpoint(tmp_path: Path) -> None:
    repository = SettingsRepository(tmp_path / "settings.db")
    repository.save_location(LocationRecord("Bridge-WS", "", 0.0, 0.0))

    def record(name: str, device_id: str) -> SensorRecord:
        return SensorRecord(
            name=name,
            description="",
            location_name="Bridge-WS",
            broker_id=None,
            mqtt_server="",
            mqtt_port=1883,
            mqtt_topic=f"nodered/{device_id}",
            mqtt_username="",
            password_env="",
            device_id=device_id,
            device_type="test",
            sample_rate=250,
            trigger_mode="Continuous",
            latitude=0.0,
            longitude=0.0,
            websocket_endpoint="kai/sensors/shared",
        )

    repository.save_sensor(record("Sensor-A", "sensor-a"))
    with pytest.raises(ConfigurationError, match="already assigned"):
        repository.save_sensor(record("Sensor-B", "sensor-b"))
