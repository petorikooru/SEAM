"""Small typed paho-mqtt adapter with lightweight callbacks."""

from __future__ import annotations

import ssl
import time
import uuid
from collections.abc import Callable
from typing import Final

from kai_bridge_inspection.domain.errors import MqttConnectionError
from kai_bridge_inspection.domain.interfaces import MessageHandler, StateHandler
from kai_bridge_inspection.domain.models import (
    IncomingMqttMessage,
    MqttBrokerProfile,
    MqttMessageMetadata,
    OutboundMqttMessage,
)
from kai_bridge_inspection.settings.secrets import EnvironmentSecretProvider

from .configuration import validate_profile

_MAX_MQTT_PAYLOAD_BYTES: Final[int] = 8 * 1024 * 1024


class PahoMqttClientService:
    """Isolate paho's untyped API and convert callbacks immediately."""

    def __init__(
        self,
        message_handler: MessageHandler,
        state_handler: StateHandler,
        secret_provider: EnvironmentSecretProvider,
    ) -> None:
        self._message_handler = message_handler
        self._state_handler = state_handler
        self._secret_provider = secret_provider
        self._client: object | None = None
        self._profile: MqttBrokerProfile | None = None
        self._connected = False

    def connect(self, profile: MqttBrokerProfile) -> None:
        validate_profile(profile)
        try:
            import paho.mqtt.client as mqtt
        except ImportError as exc:
            raise MqttConnectionError(
                "paho-mqtt is not installed; install the project runtime dependencies"
            ) from exc
        client_id = profile.client_id or f"kai-bridge-{uuid.uuid4().hex[:12]}"
        try:
            client = mqtt.Client(
                callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
                client_id=client_id,
                protocol=mqtt.MQTTv5,
            )
        except (AttributeError, TypeError):
            client = mqtt.Client(client_id=client_id, clean_session=profile.clean_session)
        if profile.username:
            password = self._secret_provider.get_secret(profile.password_env) or ""
            client.username_pw_set(profile.username, password)
        if profile.tls_enabled:
            client.tls_set(
                ca_certs=profile.ca_certificate_path or None,
                certfile=profile.client_certificate_path or None,
                keyfile=profile.client_key_path or None,
                cert_reqs=ssl.CERT_NONE if profile.allow_insecure_tls else ssl.CERT_REQUIRED,
            )
            client.tls_insecure_set(profile.allow_insecure_tls)
        client.reconnect_delay_set(min_delay=1, max_delay=30)
        client.max_inflight_messages_set(20)
        client.on_connect = self._on_connect
        client.on_disconnect = self._on_disconnect
        client.on_message = self._on_message
        self._client = client
        self._profile = profile
        self._state_handler(False, "connecting")
        try:
            client.connect_async(profile.host, profile.port, profile.keepalive_seconds)
            client.loop_start()
        except Exception as exc:
            self._client = None
            self._profile = None
            raise MqttConnectionError(f"failed to initiate MQTT connection: {exc}") from exc

    def disconnect(self) -> None:
        client = self._client
        self._client = None
        if client is not None:
            try:
                client.disconnect()  # type: ignore[attr-defined]
            finally:
                client.loop_stop()  # type: ignore[attr-defined]
        self._connected = False
        self._state_handler(False, "disconnected")

    def publish(self, message: OutboundMqttMessage) -> None:
        if self._client is None or not self._connected:
            raise MqttConnectionError("MQTT client is not connected")
        if not message.topic or any(token in message.topic for token in ("#", "+", "\x00")):
            raise MqttConnectionError("publish topic must be a concrete valid MQTT topic")
        info = self._client.publish(  # type: ignore[attr-defined]
            message.topic, message.payload, qos=message.qos, retain=message.retain
        )
        if getattr(info, "rc", 0) != 0:
            raise MqttConnectionError(f"MQTT publish failed with code {getattr(info, 'rc', -1)}")

    def is_connected(self) -> bool:
        return self._connected

    def _on_connect(self, client: object, _userdata: object, _flags: object, reason_code: object, _properties: object = None) -> None:
        raw_reason = getattr(reason_code, "value", reason_code)
        try:
            success = int(raw_reason) == 0
        except (TypeError, ValueError):
            success = str(reason_code).lower() in {"success", "normal disconnection"}
        self._connected = success
        if not success:
            self._state_handler(False, f"connect rejected: {reason_code}")
            return
        profile = self._profile
        if profile is not None:
            for subscription in profile.subscriptions:
                result, _mid = client.subscribe(subscription.topic, qos=subscription.qos)  # type: ignore[attr-defined]
                if int(result) != 0:
                    self._state_handler(False, f"subscription failed: {subscription.topic}")
                    return
        self._state_handler(True, "connected")

    def _on_disconnect(self, _client: object, _userdata: object, *args: object) -> None:
        self._connected = False
        reason = args[-2] if len(args) >= 2 else (args[-1] if args else "unknown")
        self._state_handler(False, f"disconnected: {reason}")

    def _on_message(self, _client: object, _userdata: object, mqtt_message: object) -> None:
        payload = bytes(getattr(mqtt_message, "payload", b""))
        if len(payload) > _MAX_MQTT_PAYLOAD_BYTES:
            return
        profile = self._profile
        broker_id = profile.broker_id if profile is not None else 0
        message = IncomingMqttMessage(
            metadata=MqttMessageMetadata(
                topic=str(getattr(mqtt_message, "topic", "")),
                qos=int(getattr(mqtt_message, "qos", 0)),
                retain=bool(getattr(mqtt_message, "retain", False)),
                received_timestamp_ns=time.time_ns(),
                broker_id=broker_id,
            ),
            payload=payload,
        )
        self._message_handler(message)
