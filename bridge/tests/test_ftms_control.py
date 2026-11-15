"""Kodowanie komend Control Point oraz parsowanie odpowiedzi, statusu i możliwości trenażera."""

import pytest

from wasteland_bridge import ftms


def test_simple_opcodes():
    assert ftms.encode_request_control() == b"\x00"
    assert ftms.encode_reset() == b"\x01"
    assert ftms.encode_start_or_resume() == b"\x07"
    assert ftms.encode_stop_or_pause() == b"\x08\x01"
    assert ftms.encode_stop_or_pause(pause=True) == b"\x08\x02"


@pytest.mark.parametrize(
    ("watts", "expected"),
    [
        (200, "05c800"),
        (1500, "05dc05"),
        (199.6, "05c800"),
        (-10, "05f6ff"),
        (99999, "05ff7f"),
    ],
)
def test_set_target_power(watts, expected):
    assert ftms.encode_set_target_power(watts).hex() == expected


def test_set_simulation_parameters_layout():
    # 0x11 | wiatr sint16 0,001 m/s | nachylenie sint16 0,01 % | Crr uint8 0,0001 | Cw uint8 0,01 kg/m
    assert ftms.encode_set_indoor_bike_simulation(4.5).hex() == "110000c2012833"
    assert ftms.encode_set_indoor_bike_simulation(-3.25).hex() == "110000bbfe2833"
    raw = ftms.encode_set_indoor_bike_simulation(0.0, wind_speed_mps=1.5, crr=0.005, cw_kg_per_m=0.6)
    assert raw.hex() == "11" + "dc05" + "0000" + "32" + "3c"


def test_set_simulation_clamps_out_of_range_values():
    raw = ftms.encode_set_indoor_bike_simulation(400.0, crr=0.03, cw_kg_per_m=-1.0)
    assert raw.hex() == "110000ff7fff00"


def test_parse_success_response():
    r = ftms.parse_control_point_response(bytes.fromhex("800501"))
    assert r.request_opcode == ftms.ControlOpCode.SET_TARGET_POWER
    assert r.ok
    assert r.parameter == b""
    assert "SET_TARGET_POWER" in r.describe()


@pytest.mark.parametrize(
    ("hex_bytes", "result"),
    [
        ("800005", ftms.ResultCode.CONTROL_NOT_PERMITTED),
        ("801103", ftms.ResultCode.INVALID_PARAMETER),
        ("800702", ftms.ResultCode.OP_CODE_NOT_SUPPORTED),
        ("800504", ftms.ResultCode.OPERATION_FAILED),
    ],
)
def test_parse_failure_responses(hex_bytes, result):
    r = ftms.parse_control_point_response(bytes.fromhex(hex_bytes))
    assert r.result == result
    assert not r.ok


def test_response_parameter_and_unknown_result():
    r = ftms.parse_control_point_response(bytes.fromhex("8005 01 aa"))
    assert r.parameter == b"\xaa"
    odd = ftms.parse_control_point_response(bytes.fromhex("803309"))
    assert not odd.ok
    assert "0x33" in odd.describe() and "0x09" in odd.describe()


@pytest.mark.parametrize("hex_bytes", ["", "80", "8005", "05c800"])
def test_bad_responses_raise(hex_bytes):
    with pytest.raises(ftms.FtmsParseError):
        ftms.parse_control_point_response(bytes.fromhex(hex_bytes))


def test_machine_status_target_power_changed():
    s = ftms.parse_machine_status(bytes.fromhex("08c800"))
    assert s.name == "TARGET_POWER_CHANGED"
    assert s.target_power_w == 200


def test_machine_status_simulation_changed():
    s = ftms.parse_machine_status(bytes.fromhex("120000c2012833"))
    assert s.grade_percent == pytest.approx(4.5)
    assert s.wind_speed_mps == pytest.approx(0.0)
    assert s.crr == pytest.approx(0.004)
    assert s.cw_kg_per_m == pytest.approx(0.51)


def test_machine_status_misc():
    assert ftms.parse_machine_status(b"\xff").control_lost
    assert ftms.parse_machine_status(bytes.fromhex("0202")).stopped is False
    assert ftms.parse_machine_status(bytes.fromhex("0201")).stopped is True
    assert ftms.parse_machine_status(bytes.fromhex("04")).name == "STARTED_OR_RESUMED_BY_USER"
    assert ftms.parse_machine_status(bytes.fromhex("062d00")).target_incline_percent == pytest.approx(4.5)
    unknown = ftms.parse_machine_status(bytes.fromhex("99 0102"))
    assert unknown.name == "0x99"
    assert unknown.parameter == b"\x01\x02"
    with pytest.raises(ftms.FtmsParseError):
        ftms.parse_machine_status(bytes.fromhex("08c8"))


def test_features_of_a_smart_trainer():
    # Kadencja (bit 1), tętno (bit 10), pomiar mocy (bit 14); cele: moc (bit 3), symulacja (bit 13).
    f = ftms.parse_features(bytes.fromhex("02440000 08200000"))
    assert f.cadence and f.power_measurement
    assert f.power_target and f.simulation
    assert "ERG: tak" in f.describe()
    basic = ftms.parse_features(bytes(8))
    assert not basic.power_target and not basic.simulation


def test_supported_power_range_clamp():
    r = ftms.parse_supported_power_range(bytes.fromhex("0000 6c07 0100"))
    assert (r.minimum_w, r.maximum_w, r.increment_w) == (0, 1900, 1)
    assert r.clamp(2500) == 1900
    assert r.clamp(-5) == 0
    assert r.clamp(250) == 250


def test_uuids():
    assert ftms.FTMS_SERVICE_UUID == "00001826-0000-1000-8000-00805f9b34fb"
    assert ftms.INDOOR_BIKE_DATA_UUID.startswith("00002ad2")
    assert ftms.CONTROL_POINT_UUID.startswith("00002ad9")
    assert ftms.MACHINE_STATUS_UUID.startswith("00002ada")
