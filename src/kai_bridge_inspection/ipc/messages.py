"""Typed IPC request, response, event, and error structures."""

from __future__ import annotations

from dataclasses import dataclass
from typing import NotRequired, TypedDict


class IpcRequestDict(TypedDict):
    protocol_version: int
    request_id: str
    command: str
    payload: dict[str, object]


class IpcErrorDict(TypedDict):
    code: str
    message: str
    details: NotRequired[dict[str, object]]


class IpcResponseDict(TypedDict):
    protocol_version: int
    request_id: str
    ok: bool
    result: dict[str, object] | None
    error: IpcErrorDict | None


class IpcEventDict(TypedDict):
    protocol_version: int
    event: str
    payload: dict[str, object]


@dataclass(frozen=True, slots=True)
class IpcCommandResult:
    ok: bool
    result: dict[str, object] | None = None
    error_code: str = ""
    error_message: str = ""
