from __future__ import annotations

from kai_bridge_inspection.domain.models import IncomingMqttMessage, MqttMessageMetadata
from kai_bridge_inspection.sparkplug import sparkplug_b_pb2
from kai_bridge_inspection.sparkplug.codec import ProtobufSparkplugCodec
from kai_bridge_inspection.sparkplug.parser import SparkplugTelemetryParser


def payload_bytes(name: str | None, alias: int, value: float, sequence: int) -> bytes:
    payload = sparkplug_b_pb2.Payload()
    payload.timestamp = 1_700_000_000_000
    payload.seq = sequence
    metric = payload.metrics.add()
    if name is not None:
        metric.name = name
    metric.alias = alias
    metric.datatype = 10
    metric.double_value = value
    return bytes(payload.SerializeToString())


def test_codec_decodes_scalar_metric() -> None:
    decoded = ProtobufSparkplugCodec().decode(payload_bytes("temperature", 1, 24.5, 1))
    assert decoded.sequence == 1
    assert decoded.metrics[0].name == "temperature"
    assert decoded.metrics[0].value == 24.5


def test_parser_resolves_birth_alias_for_data() -> None:
    parser = SparkplugTelemetryParser()
    birth = IncomingMqttMessage(
        MqttMessageMetadata("spBv1.0/g/DBIRTH/n/d", 0, False, 1, 1),
        payload_bytes("temperature", 1, 24.5, 1),
    )
    data = IncomingMqttMessage(
        MqttMessageMetadata("spBv1.0/g/DDATA/n/d", 0, False, 2, 1),
        payload_bytes(None, 1, 25.0, 2),
    )
    parser.parse(birth)
    points = parser.parse(data)
    assert points[0].metric_name == "TEMPERATURE"
    assert points[0].value == 25.0


def test_parser_ignores_command_traffic() -> None:
    parser = SparkplugTelemetryParser()
    command = IncomingMqttMessage(
        MqttMessageMetadata("spBv1.0/g/DCMD/n/d", 0, False, 3, 1),
        payload_bytes("reboot", 99, 1.0, 3),
    )
    assert parser.parse(command) == []
    assert parser.last_message_ignored


def test_parser_ignores_zero_length_retained_cleanup() -> None:
    parser = SparkplugTelemetryParser()
    cleanup = IncomingMqttMessage(
        MqttMessageMetadata("spBv1.0/g/DDATA/n/d", 0, True, 4, 1),
        b"",
    )
    assert parser.parse(cleanup) == []
    assert parser.last_message_ignored


def test_parser_skips_unknown_alias_until_birth_arrives() -> None:
    parser = SparkplugTelemetryParser()
    data = IncomingMqttMessage(
        MqttMessageMetadata("spBv1.0/g/DDATA/n/d", 0, False, 5, 1),
        payload_bytes(None, 999, 25.0, 5),
    )
    assert parser.parse(data) == []
    assert parser.last_state_update is not None
    assert parser.last_state_update.unknown_aliases == 1
