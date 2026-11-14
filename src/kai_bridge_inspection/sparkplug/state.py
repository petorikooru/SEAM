"""Sparkplug node/device lifecycle, sequence, and metric-alias registry."""

from __future__ import annotations

from dataclasses import dataclass

from kai_bridge_inspection.domain.errors import SparkplugStateError

from .models import (
    SparkplugEntityState,
    SparkplugMessageType,
    SparkplugMetric,
    SparkplugPayload,
    SparkplugTopic,
)


@dataclass(frozen=True, slots=True)
class StateUpdate:
    birth: bool = False
    death: bool = False
    sequence_valid: bool = True
    rebirth_required: bool = False
    unknown_aliases: int = 0


class SparkplugStateRegistry:
    """Maintains session-local aliases and online state for each entity."""

    def __init__(self) -> None:
        self._entities: dict[tuple[str, str, str | None], SparkplugEntityState] = {}

    def reset(self) -> None:
        self._entities.clear()

    def apply(self, topic: SparkplugTopic, payload: SparkplugPayload) -> StateUpdate:
        state = self._entities.setdefault(topic.state_key, SparkplugEntityState())
        birth = topic.message_type in {SparkplugMessageType.NBIRTH, SparkplugMessageType.DBIRTH}
        death = topic.message_type in {SparkplugMessageType.NDEATH, SparkplugMessageType.DDEATH}
        sequence_valid = self._validate_sequence(state, payload.sequence, birth)
        unknown_aliases = 0
        if birth:
            state.online = True
            state.aliases.clear()
            for metric in payload.metrics:
                if metric.alias is not None and metric.name:
                    state.aliases[metric.alias] = metric.name
            state.birth_sequence = payload.sequence
        elif death:
            state.online = False
        else:
            for metric in payload.metrics:
                if not metric.name and metric.alias is not None and metric.alias not in state.aliases:
                    unknown_aliases += 1
        state.last_sequence = payload.sequence if payload.sequence is not None else state.last_sequence
        state.last_timestamp_ns = payload.timestamp_ns or state.last_timestamp_ns
        return StateUpdate(
            birth=birth,
            death=death,
            sequence_valid=sequence_valid,
            rebirth_required=unknown_aliases > 0 or not sequence_valid,
            unknown_aliases=unknown_aliases,
        )

    def resolve_metric_name(self, topic: SparkplugTopic, metric: SparkplugMetric) -> str:
        if metric.name:
            return metric.name
        if metric.alias is None:
            raise SparkplugStateError("Sparkplug metric has neither name nor alias")
        state = self._entities.get(topic.state_key)
        if state is None or metric.alias not in state.aliases:
            raise SparkplugStateError(
                f"unknown Sparkplug metric alias {metric.alias} for {topic.state_key}"
            )
        return state.aliases[metric.alias]

    def entity_state(self, topic: SparkplugTopic) -> SparkplugEntityState | None:
        return self._entities.get(topic.state_key)

    def snapshot(self) -> dict[str, object]:
        return {
            "/".join(filter(None, key)): {
                "online": state.online,
                "aliases": dict(state.aliases),
                "last_sequence": state.last_sequence,
                "birth_sequence": state.birth_sequence,
                "last_timestamp_ns": state.last_timestamp_ns,
            }
            for key, state in self._entities.items()
        }

    @staticmethod
    def _validate_sequence(
        state: SparkplugEntityState,
        sequence: int | None,
        birth: bool,
    ) -> bool:
        if sequence is None or birth or state.last_sequence is None:
            return True
        return sequence == ((state.last_sequence + 1) % 256)
