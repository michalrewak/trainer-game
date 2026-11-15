"""Parser Indoor Bike Data (0x2AD2) – różne kombinacje flag, bajty jak z prawdziwych trenażerów."""

import pytest

from wasteland_bridge import ftms
from wasteland_bridge.state import BridgeState


def parse(hex_bytes: str) -> ftms.IndoorBikeData:
    return ftms.parse_indoor_bike_data(bytes.fromhex(hex_bytes))


def test_typical_speed_cadence_power_packet():
    # Flags 0x0044: kadencja + moc, bit 0 = 0 -> jest prędkość chwilowa.
    d = parse("4400 100e b400 c800")
    assert d.flags == 0x0044
    assert not d.more_data
    assert d.instantaneous_speed_kmh == pytest.approx(36.0)
    assert d.instantaneous_cadence_rpm == pytest.approx(90.0)
    assert d.instantaneous_power_w == 200
    assert d.average_speed_kmh is None
    assert d.total_distance_m is None
    assert d.heart_rate_bpm is None


def test_more_data_bit_means_no_instantaneous_speed():
    # Flags 0x0045: bit 0 = 1 ("More Data") -> pierwsze pole to już kadencja.
    d = parse("4500 b400 c800")
    assert d.more_data
    assert d.instantaneous_speed_kmh is None
    assert d.instantaneous_cadence_rpm == pytest.approx(90.0)
    assert d.instantaneous_power_w == 200


def test_distance_uint24_and_resistance_level():
    # Flags 0x0074: kadencja, dystans (uint24), poziom oporu (sint16), moc.
    d = parse("7400 9c0b a600 393000 0f00 f100")
    assert d.instantaneous_speed_kmh == pytest.approx(29.72)
    assert d.instantaneous_cadence_rpm == pytest.approx(83.0)
    assert d.total_distance_m == 12345
    assert d.resistance_level == 15
    assert d.instantaneous_power_w == 241


def test_all_fields_present():
    d = parse(
        "fe1f"  # flags: bity 1..12, bit 0 = 0
        "540d"  # prędkość 34,12 km/h
        "cd0b"  # średnia prędkość 30,21 km/h
        "b600"  # kadencja 91 obr/min
        "aa00"  # średnia kadencja 85 obr/min
        "31d400"  # dystans 54321 m
        "fbff"  # opór -5
        "0001"  # moc 256 W
        "e600"  # średnia moc 230 W
        "5901"  # energia 345 kcal
        "8403"  # 900 kcal/h
        "0f"  # 15 kcal/min
        "8e"  # tętno 142
        "57"  # MET 8,7
        "8d0e"  # czas 3725 s
        "b004"  # pozostało 1200 s
    )
    assert d.instantaneous_speed_kmh == pytest.approx(34.12)
    assert d.average_speed_kmh == pytest.approx(30.21)
    assert d.instantaneous_cadence_rpm == pytest.approx(91.0)
    assert d.average_cadence_rpm == pytest.approx(85.0)
    assert d.total_distance_m == 54321
    assert d.resistance_level == -5
    assert d.instantaneous_power_w == 256
    assert d.average_power_w == 230
    assert d.total_energy_kcal == 345
    assert d.energy_per_hour_kcal == 900
    assert d.energy_per_minute_kcal == 15
    assert d.heart_rate_bpm == 142
    assert d.metabolic_equivalent == pytest.approx(8.7)
    assert d.elapsed_time_s == 3725
    assert d.remaining_time_s == 1200


def test_power_is_signed():
    d = parse("4000 0000 f4ff")
    assert d.instantaneous_speed_kmh == 0.0
    assert d.instantaneous_power_w == -12


def test_half_rpm_cadence_resolution():
    d = parse("0500 a701")  # More Data + kadencja 423 * 0,5
    assert d.instantaneous_cadence_rpm == pytest.approx(211.5)


def test_energy_not_available_values_become_none():
    d = parse("0101 ffff ffff ff")
    assert d.total_energy_kcal is None
    assert d.energy_per_hour_kcal is None
    assert d.energy_per_minute_kcal is None


def test_reserved_bits_and_trailing_bytes_are_ignored():
    d = parse("4420 100e b400 c800 dead")
    assert d.instantaneous_power_w == 200
    assert d.instantaneous_cadence_rpm == pytest.approx(90.0)


@pytest.mark.parametrize("hex_bytes", ["", "44", "4400 100e b4", "4000 0000 f4", "1000 0000 3930"])
def test_truncated_packets_raise(hex_bytes):
    with pytest.raises(ftms.FtmsParseError):
        parse(hex_bytes)


def test_encoder_roundtrip():
    raw = ftms.encode_indoor_bike_data(speed_kmh=31.4, cadence_rpm=87.5, power_w=212, heart_rate_bpm=131)
    d = ftms.parse_indoor_bike_data(raw)
    assert d.instantaneous_speed_kmh == pytest.approx(31.4)
    assert d.instantaneous_cadence_rpm == pytest.approx(87.5)
    assert d.instantaneous_power_w == 212
    assert d.heart_rate_bpm == 131
    no_speed = ftms.parse_indoor_bike_data(ftms.encode_indoor_bike_data(power_w=150))
    assert no_speed.more_data and no_speed.instantaneous_speed_kmh is None


def test_split_record_is_merged_into_state():
    """Trenażer dzieli rekord: najpierw kadencja + moc (More Data), potem sama prędkość."""
    state = BridgeState(clock=lambda: 100.0)
    state.apply_bike_data(parse("4500 b400 c800"))
    state.apply_bike_data(parse("0000 100e"))
    m = state.measurement
    assert m.power_w == 200
    assert m.cadence_rpm == pytest.approx(90.0)
    assert m.speed_kmh == pytest.approx(36.0)
    assert state.packets == 2


def test_negative_power_is_clamped_in_state():
    state = BridgeState(clock=lambda: 1.0)
    state.apply_bike_data(parse("4000 0000 f4ff"))
    assert state.measurement.power_w == 0
