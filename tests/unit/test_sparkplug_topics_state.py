from __future__ import annotations

import pytest

from kai_bridge_inspection.domain.errors import SparkplugStateError
from kai_bridge_inspection.sparkplug.models import SparkplugMetric, SparkplugPayload
from kai_bridge_inspection.sparkplug.state import SparkplugStateRegistry
from kai_bridge_inspection.sparkplug.topics import parse_sparkplug_topic


def test_topic_validation() -> None:
    topic = parse_sparkplug_topic("spBv1.0/group/DDATA/node/device")
    assert topic.device_id == "device"
    with pytest.raises(SparkplugStateError):
        parse_sparkplug_topic("spBv1.0/group/DDATA/node")


def test_birth_registers_alias_and_sequence() -> None:
    registry = SparkplugStateRegistry()
    birth_topic = parse_sparkplug_topic("spBv1.0/group/DBIRTH/node/device")
    data_topic = parse_sparkplug_topic("spBv1.0/group/DDATA/node/device")
    birth = SparkplugPayload(
        1_000_000_000,
        10,
        (SparkplugMetric("temperature", 1, None, 10, 21.0),),
    )
    update = registry.apply(birth_topic, birth)
    assert update.birth
    alias_metric = SparkplugMetric(None, 1, None, 10, 22.0)
    assert registry.resolve_metric_name(data_topic, alias_metric) == "temperature"
    assert registry.apply(data_topic, SparkplugPayload(None, 11, (alias_metric,))).sequence_valid
    assert not registry.apply(data_topic, SparkplugPayload(None, 13, (alias_metric,))).sequence_valid
