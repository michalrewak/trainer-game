"""Protokół v1 mostek <-> gra: parsowanie komend i budowa wiadomości."""

import json

import pytest

from wasteland_bridge import protocol
from wasteland_bridge.protocol import ErgCommand, LinkState, PingCommand, ProtocolError, SlopeCommand, parse_command


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ('{"cmd":"erg","watts":200}', ErgCommand(200)),
        ('{"cmd":"erg","watts":199.6}', ErgCommand(200)),
        ('{"cmd":"erg","watts":0}', ErgCommand(None)),
        ('{"cmd":"erg","watts":-50}', ErgCommand(None)),
        ('{"cmd":"erg","watts":0.4}', ErgCommand(None)),
        ('{"cmd":"slope","grade":4.5}', SlopeCommand(4.5)),
        ('{"cmd":"slope","grade":-2}', SlopeCommand(-2.0)),
        ('{"cmd":"slope","grade":35}', SlopeCommand(20.0)),
        ('{"cmd":"slope","grade":-31.5}', SlopeCommand(-20.0)),
        ('{"cmd":"slope","grade":1.23456}', SlopeCommand(1.23)),
        ('{"cmd":"ping"}', PingCommand()),
        ('{"cmd":"ping","id":7,"extra":[1,2]}', PingCommand()),
        ('  {"watts": 120, "cmd": "erg"}  ', ErgCommand(120)),
    ],
)
def test_valid_commands(raw, expected):
    assert parse_command(raw) == expected


@pytest.mark.parametrize(
    ("raw", "fragment"),
    [
        ("", "JSON"),
        ("{nie json", "JSON"),
        ("[1,2,3]", "obiektu"),
        ('"ping"', "obiektu"),
        ("{}", "cmd"),
        ('{"cmd":5}', "cmd"),
        ('{"cmd":"boost"}', "nieznana"),
        ('{"cmd":"erg"}', "watts"),
        ('{"cmd":"erg","watts":"200"}', "liczbą"),
        ('{"cmd":"erg","watts":true}', "liczbą"),
        ('{"cmd":"erg","watts":null}', "liczbą"),
        ('{"cmd":"erg","watts":NaN}', "skończoną"),
        ('{"cmd":"erg","watts":Infinity}', "skończoną"),
        ('{"cmd":"erg","watts":1e999}', "skończoną"),
        ('{"cmd":"erg","watts":2500}', "zakresem"),
        ('{"cmd":"slope","grade":[4]}', "liczbą"),
        ("[" * 2000 + "]" * 2000, "JSON"),
    ],
)
def test_invalid_commands_raise_protocol_error(raw, fragment):
    with pytest.raises(ProtocolError) as info:
        parse_command(raw)
    assert fragment in str(info.value)


def test_binary_and_too_long_frames_are_rejected():
    with pytest.raises(ProtocolError, match="tekstowej"):
        parse_command(b'{"cmd":"ping"}')
    with pytest.raises(ProtocolError, match="za długa"):
        parse_command('{"cmd":"ping","pad":"' + "x" * 5000 + '"}')


def test_data_message_types_and_rounding():
    msg = json.loads(protocol.data_message(212.6, 87.46, 33.456, 1763236800.12345))
    assert msg == {"type": "data", "power": 213, "cadence": 87.5, "speed": 33.46, "timestamp": 1763236800.123}
    assert isinstance(msg["power"], int)
    assert isinstance(msg["cadence"], float)


def test_data_message_never_contains_nan_or_negatives():
    raw = protocol.data_message(float("nan"), -3.0, float("inf"), 5.0)
    msg = json.loads(raw)
    assert msg["power"] == 0 and msg["cadence"] == 0.0 and msg["speed"] == 0.0
    assert "NaN" not in raw and "Infinity" not in raw


def test_status_message_with_nulls_and_values():
    msg = json.loads(protocol.status_message(LinkState.SEARCHING, None, None, None))
    assert msg == {"type": "status", "state": "searching", "device": None, "erg": None, "grade": None}
    msg = json.loads(protocol.status_message(LinkState.CONNECTED, "SUITO 1234", 250, 3.456))
    assert msg == {"type": "status", "state": "connected", "device": "SUITO 1234", "erg": 250, "grade": 3.46}


def test_pong_and_error_messages():
    assert json.loads(protocol.pong_message()) == {"type": "pong"}
    raw = protocol.error_message("zła komenda – spróbuj „ping”")
    assert "zła" in raw  # UTF-8 bez \u-ucieczek
    assert json.loads(raw) == {"type": "error", "message": "zła komenda – spróbuj „ping”"}


def test_link_state_values():
    assert [s.value for s in LinkState] == ["searching", "connecting", "connected", "disconnected", "sim"]
    assert LinkState.CONNECTED.delivers_data and LinkState.SIM.delivers_data
    assert not LinkState.DISCONNECTED.delivers_data
