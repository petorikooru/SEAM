from __future__ import annotations

import pytest

from kai_bridge_inspection.domain.errors import IpcProtocolError
from kai_bridge_inspection.ipc.protocol import decode_line, encode_message, new_request, validate_request


def test_ipc_round_trip() -> None:
    request = new_request("get_status")
    encoded = encode_message(request)
    decoded = validate_request(decode_line(encoded.rstrip(b"\n")))
    assert decoded["command"] == "get_status"
    assert decoded["request_id"] == request["request_id"]


def test_ipc_rejects_unknown_command() -> None:
    with pytest.raises(IpcProtocolError):
        new_request("execute_python")
