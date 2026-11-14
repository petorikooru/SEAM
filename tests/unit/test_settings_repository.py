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


def test_metric_routes_migrate_and_update_atomically(tmp_path: Path) -> None:
    import sqlite3
    from dataclasses import replace

    path = tmp_path / "settings.db"
    repository = SettingsRepository(path)
    repository.save_location(LocationRecord("Bridge", "", 0, 0))
    legacy = SensorRecord(
        "Legacy", "", "Bridge", None, "", 1883, "nodered/NEMO", "", "",
        "NEMO", "Dewesoft Nemosense", 250, "Continuous", 0, 0, "bridge/nemo",
    )
    repository.save_sensor(legacy)
    with sqlite3.connect(path) as connection:
        connection.execute("DROP TABLE sensor_metric_endpoints")
        connection.execute("ALTER TABLE sensors DROP COLUMN profile")
        connection.execute("PRAGMA user_version = 3")

    repository = SettingsRepository(path)
    assert repository.get_sensor("Legacy") == legacy
    assert repository.list_node_red_sensor_streams() == {"bridge/nemo": ("NEMO", frozenset())}

    bean = replace(legacy, name="Bean", device_id="BEAN", websocket_endpoint="")
    routes = {"ACC/ROLL": "bridge/roll", "ACC/PITCH": "bridge/pitch"}
    repository.save_sensor(bean, profile="beandevice_inclinometer", routes=routes)
    with pytest.raises(ConfigurationError, match="already assigned"):
        repository.save_sensor(
            bean, profile="beandevice_inclinometer",
            routes={**routes, "ACC/PITCH": "/bridge/nemo/"},
        )
    with pytest.raises(ConfigurationError, match="required WebSocket paths"):
        repository.save_sensor(bean, profile="beandevice_combo", routes=routes)

    assert repository.list_node_red_sensor_streams() == {
        "bridge/nemo": ("NEMO", frozenset()),
        "bridge/roll": ("BEAN", frozenset({"ACC/ROLL"})),
        "bridge/pitch": ("BEAN", frozenset({"ACC/PITCH"})),
    }

    repository.save_sensor(replace(bean, name="Renamed"), old_name="Bean")
    renamed = repository.get_sensor("Renamed")
    assert renamed is not None
    assert repository.get_sensor_streams(renamed) == routes
    streaming = replace(renamed, trigger_mode="streaming")
    with pytest.raises(ConfigurationError, match="required WebSocket paths"):
        repository.save_sensor(streaming, profile="beandevice_combo", routes=routes)
    repository.save_sensor(streaming, profile="beandevice_combo", routes={"": "BEAN/STREAMING"})
    saved_streaming = repository.get_sensor("Renamed")
    assert saved_streaming is not None
    assert saved_streaming.trigger_mode == "streaming"
    assert repository.get_sensor_streams(saved_streaming) == {"": "BEAN/STREAMING"}
    assert repository.list_node_red_sensor_streams() == {
        "bridge/nemo": ("NEMO", frozenset()),
        "BEAN/STREAMING": ("BEAN", frozenset({"ACC/X", "ACC/Y", "ACC/Z", "ACC/ROLL", "ACC/PITCH"})),
    }
    repository.save_sensor(replace(saved_streaming, trigger_mode="periodic"),
                           profile="beandevice_inclinometer", routes=routes)
    assert "BEAN/STREAMING" not in repository.list_node_red_sensor_streams()

    repository.delete_sensor("Renamed")
    assert repository.list_node_red_sensor_streams() == {"bridge/nemo": ("NEMO", frozenset())}
