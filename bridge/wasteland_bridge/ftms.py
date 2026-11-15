"""Protokół Bluetooth FTMS (Fitness Machine Service, 0x1826) – czysta logika bez BLE.

Parsowanie charakterystyk (Indoor Bike Data, odpowiedzi Control Point, Fitness Machine Status,
Fitness Machine Feature, Supported Power Range) i kodowanie komend Control Point.
Wszystkie wartości wielobajtowe są little-endian (zgodnie ze specyfikacją FTMS v1.0).
"""

from __future__ import annotations

import enum
import struct
from dataclasses import dataclass


def uuid16(short: int) -> str:
    """Pełny 128-bitowy UUID dla 16-bitowego identyfikatora Bluetooth SIG."""
    return f"0000{short:04x}-0000-1000-8000-00805f9b34fb"


FTMS_SERVICE_UUID = uuid16(0x1826)
FEATURE_UUID = uuid16(0x2ACC)
INDOOR_BIKE_DATA_UUID = uuid16(0x2AD2)
TRAINING_STATUS_UUID = uuid16(0x2AD3)
SUPPORTED_RESISTANCE_RANGE_UUID = uuid16(0x2AD6)
SUPPORTED_POWER_RANGE_UUID = uuid16(0x2AD8)
CONTROL_POINT_UUID = uuid16(0x2AD9)
MACHINE_STATUS_UUID = uuid16(0x2ADA)

SINT16_MIN = -32768
SINT16_MAX = 32767


class FtmsParseError(ValueError):
    """Pakiet FTMS nie pasuje do specyfikacji (za krótki, zły kod operacji itp.)."""


class _Reader:
    """Kursor po bajtach pakietu, czyta pola little-endian i pilnuje długości."""

    def __init__(self, data: bytes | bytearray | memoryview) -> None:
        self._data = bytes(data)
        self._pos = 0

    @property
    def remaining(self) -> int:
        return len(self._data) - self._pos

    def rest(self) -> bytes:
        out = self._data[self._pos :]
        self._pos = len(self._data)
        return out

    def _take(self, size: int, field_name: str) -> bytes:
        if self._pos + size > len(self._data):
            raise FtmsParseError(
                f"pakiet za krótki: pole {field_name!r} wymaga {size} B od bajtu {self._pos}, "
                f"a pakiet ma {len(self._data)} B ({self._data.hex(' ')})"
            )
        out = self._data[self._pos : self._pos + size]
        self._pos += size
        return out

    def uint8(self, field_name: str) -> int:
        return self._take(1, field_name)[0]

    def uint16(self, field_name: str) -> int:
        return int.from_bytes(self._take(2, field_name), "little", signed=False)

    def sint16(self, field_name: str) -> int:
        return int.from_bytes(self._take(2, field_name), "little", signed=True)

    def uint24(self, field_name: str) -> int:
        return int.from_bytes(self._take(3, field_name), "little", signed=False)

    def uint32(self, field_name: str) -> int:
        return int.from_bytes(self._take(4, field_name), "little", signed=False)


# --- Indoor Bike Data (0x2AD2) -------------------------------------------------------


class IndoorBikeDataFlags(enum.IntFlag):
    """Bity pola Flags w Indoor Bike Data.

    Uwaga na bit 0: „More Data” = 1 oznacza, że w TYM pakiecie NIE ma prędkości chwilowej
    (dalsze pola przyjdą w kolejnym pakiecie). Prędkość chwilowa jest obecna, gdy bit 0 = 0.
    Pozostałe bity = 1 oznaczają obecność danego pola.
    """

    MORE_DATA = 1 << 0
    AVERAGE_SPEED = 1 << 1
    INSTANTANEOUS_CADENCE = 1 << 2
    AVERAGE_CADENCE = 1 << 3
    TOTAL_DISTANCE = 1 << 4
    RESISTANCE_LEVEL = 1 << 5
    INSTANTANEOUS_POWER = 1 << 6
    AVERAGE_POWER = 1 << 7
    EXPENDED_ENERGY = 1 << 8
    HEART_RATE = 1 << 9
    METABOLIC_EQUIVALENT = 1 << 10
    ELAPSED_TIME = 1 << 11
    REMAINING_TIME = 1 << 12


#: Wartości „brak danych” dla pól energii (specyfikacja FTMS).
ENERGY_UINT16_NOT_AVAILABLE = 0xFFFF
ENERGY_UINT8_NOT_AVAILABLE = 0xFF


@dataclass(frozen=True, slots=True)
class IndoorBikeData:
    """Jeden pakiet Indoor Bike Data. Pole = None, gdy nie było go w pakiecie."""

    flags: int
    instantaneous_speed_kmh: float | None = None
    average_speed_kmh: float | None = None
    instantaneous_cadence_rpm: float | None = None
    average_cadence_rpm: float | None = None
    total_distance_m: int | None = None
    resistance_level: int | None = None
    instantaneous_power_w: int | None = None
    average_power_w: int | None = None
    total_energy_kcal: int | None = None
    energy_per_hour_kcal: int | None = None
    energy_per_minute_kcal: int | None = None
    heart_rate_bpm: int | None = None
    metabolic_equivalent: float | None = None
    elapsed_time_s: int | None = None
    remaining_time_s: int | None = None

    @property
    def more_data(self) -> bool:
        """True = to nie ostatni fragment rekordu (brak prędkości chwilowej w tym pakiecie)."""
        return bool(self.flags & IndoorBikeDataFlags.MORE_DATA)


def parse_indoor_bike_data(data: bytes | bytearray | memoryview) -> IndoorBikeData:
    """Parsuje pakiet Indoor Bike Data wg flag. Rzuca FtmsParseError dla za krótkiego pakietu.

    Bity zarezerwowane (13–15) i nadmiarowe bajty na końcu są ignorowane – leżą za wszystkimi
    znanymi polami, więc nie przesuwają ich położenia.
    """
    r = _Reader(data)
    flags = r.uint16("Flags")
    f = IndoorBikeDataFlags
    values: dict[str, int | float | None] = {}
    if not flags & f.MORE_DATA:
        values["instantaneous_speed_kmh"] = r.uint16("Instantaneous Speed") / 100.0
    if flags & f.AVERAGE_SPEED:
        values["average_speed_kmh"] = r.uint16("Average Speed") / 100.0
    if flags & f.INSTANTANEOUS_CADENCE:
        values["instantaneous_cadence_rpm"] = r.uint16("Instantaneous Cadence") / 2.0
    if flags & f.AVERAGE_CADENCE:
        values["average_cadence_rpm"] = r.uint16("Average Cadence") / 2.0
    if flags & f.TOTAL_DISTANCE:
        values["total_distance_m"] = r.uint24("Total Distance")
    if flags & f.RESISTANCE_LEVEL:
        values["resistance_level"] = r.sint16("Resistance Level")
    if flags & f.INSTANTANEOUS_POWER:
        values["instantaneous_power_w"] = r.sint16("Instantaneous Power")
    if flags & f.AVERAGE_POWER:
        values["average_power_w"] = r.sint16("Average Power")
    if flags & f.EXPENDED_ENERGY:
        total = r.uint16("Total Energy")
        per_hour = r.uint16("Energy Per Hour")
        per_minute = r.uint8("Energy Per Minute")
        values["total_energy_kcal"] = None if total == ENERGY_UINT16_NOT_AVAILABLE else total
        values["energy_per_hour_kcal"] = None if per_hour == ENERGY_UINT16_NOT_AVAILABLE else per_hour
        values["energy_per_minute_kcal"] = None if per_minute == ENERGY_UINT8_NOT_AVAILABLE else per_minute
    if flags & f.HEART_RATE:
        values["heart_rate_bpm"] = r.uint8("Heart Rate")
    if flags & f.METABOLIC_EQUIVALENT:
        values["metabolic_equivalent"] = r.uint8("Metabolic Equivalent") / 10.0
    if flags & f.ELAPSED_TIME:
        values["elapsed_time_s"] = r.uint16("Elapsed Time")
    if flags & f.REMAINING_TIME:
        values["remaining_time_s"] = r.uint16("Remaining Time")
    return IndoorBikeData(flags=flags, **values)  # type: ignore[arg-type]


def encode_indoor_bike_data(
    *,
    speed_kmh: float | None = None,
    cadence_rpm: float | None = None,
    power_w: int | None = None,
    heart_rate_bpm: int | None = None,
) -> bytes:
    """Buduje pakiet Indoor Bike Data (podzbiór pól) – do testów i symulatora.

    Bez prędkości ustawia bit „More Data” (tak jak robią to trenażery dzielące rekord).
    """
    f = IndoorBikeDataFlags
    flags = 0
    body = b""
    if speed_kmh is None:
        flags |= f.MORE_DATA
    else:
        body += struct.pack("<H", _clamp(round(speed_kmh * 100), 0, 0xFFFF))
    if cadence_rpm is not None:
        flags |= f.INSTANTANEOUS_CADENCE
        body += struct.pack("<H", _clamp(round(cadence_rpm * 2), 0, 0xFFFF))
    if power_w is not None:
        flags |= f.INSTANTANEOUS_POWER
        body += struct.pack("<h", _clamp(round(power_w), SINT16_MIN, SINT16_MAX))
    if heart_rate_bpm is not None:
        flags |= f.HEART_RATE
        body += struct.pack("<B", _clamp(round(heart_rate_bpm), 0, 0xFF))
    return struct.pack("<H", flags) + body


# --- Control Point (0x2AD9) ----------------------------------------------------------


class ControlOpCode(enum.IntEnum):
    REQUEST_CONTROL = 0x00
    RESET = 0x01
    SET_TARGET_SPEED = 0x02
    SET_TARGET_INCLINATION = 0x03
    SET_TARGET_RESISTANCE_LEVEL = 0x04
    SET_TARGET_POWER = 0x05
    SET_TARGET_HEART_RATE = 0x06
    START_OR_RESUME = 0x07
    STOP_OR_PAUSE = 0x08
    SET_INDOOR_BIKE_SIMULATION = 0x11
    SET_WHEEL_CIRCUMFERENCE = 0x12
    SPIN_DOWN_CONTROL = 0x13
    SET_TARGETED_CADENCE = 0x14
    RESPONSE_CODE = 0x80


class ResultCode(enum.IntEnum):
    SUCCESS = 0x01
    OP_CODE_NOT_SUPPORTED = 0x02
    INVALID_PARAMETER = 0x03
    OPERATION_FAILED = 0x04
    CONTROL_NOT_PERMITTED = 0x05


_RESULT_TEXT = {
    ResultCode.SUCCESS: "OK",
    ResultCode.OP_CODE_NOT_SUPPORTED: "komenda nieobsługiwana",
    ResultCode.INVALID_PARAMETER: "niepoprawny parametr",
    ResultCode.OPERATION_FAILED: "operacja nieudana",
    ResultCode.CONTROL_NOT_PERMITTED: "brak uprawnień do sterowania (Request Control?)",
}

#: Domyślne parametry symulacji (jak w popularnych aplikacjach): Crr 0,004, Cw 0,51 kg/m.
DEFAULT_CRR = 0.004
DEFAULT_CW_KG_PER_M = 0.51


def _clamp(value: int, low: int, high: int) -> int:
    return max(low, min(high, int(value)))


def opcode_name(opcode: int) -> str:
    try:
        return ControlOpCode(opcode).name
    except ValueError:
        return f"0x{opcode:02X}"


def encode_request_control() -> bytes:
    return bytes([ControlOpCode.REQUEST_CONTROL])


def encode_reset() -> bytes:
    return bytes([ControlOpCode.RESET])


def encode_start_or_resume() -> bytes:
    return bytes([ControlOpCode.START_OR_RESUME])


def encode_stop_or_pause(pause: bool = False) -> bytes:
    """0x08 z parametrem 0x01 = stop, 0x02 = pauza."""
    return bytes([ControlOpCode.STOP_OR_PAUSE, 0x02 if pause else 0x01])


def encode_set_target_power(watts: float) -> bytes:
    """Set Target Power (tryb ERG): sint16, rozdzielczość 1 W."""
    return struct.pack("<Bh", ControlOpCode.SET_TARGET_POWER, _clamp(round(watts), SINT16_MIN, SINT16_MAX))


def encode_set_indoor_bike_simulation(
    grade_percent: float,
    *,
    wind_speed_mps: float = 0.0,
    crr: float = DEFAULT_CRR,
    cw_kg_per_m: float = DEFAULT_CW_KG_PER_M,
) -> bytes:
    """Set Indoor Bike Simulation Parameters (0x11).

    Wiatr sint16 (0,001 m/s), nachylenie sint16 (0,01 %), Crr uint8 (0,0001), Cw uint8 (0,01 kg/m).
    """
    return struct.pack(
        "<BhhBB",
        ControlOpCode.SET_INDOOR_BIKE_SIMULATION,
        _clamp(round(wind_speed_mps * 1000), SINT16_MIN, SINT16_MAX),
        _clamp(round(grade_percent * 100), SINT16_MIN, SINT16_MAX),
        _clamp(round(crr * 10000), 0, 0xFF),
        _clamp(round(cw_kg_per_m * 100), 0, 0xFF),
    )


@dataclass(frozen=True, slots=True)
class ControlPointResponse:
    """Wskazanie (indication) Control Point z kodem 0x80: na którą komendę i z jakim wynikiem."""

    request_opcode: int
    result: int
    parameter: bytes = b""

    @property
    def ok(self) -> bool:
        return self.result == ResultCode.SUCCESS

    def describe(self) -> str:
        try:
            text = _RESULT_TEXT[ResultCode(self.result)]
        except ValueError:
            text = f"nieznany wynik 0x{self.result:02X}"
        return f"{opcode_name(self.request_opcode)}: {text}"


def parse_control_point_response(data: bytes | bytearray | memoryview) -> ControlPointResponse:
    r = _Reader(data)
    code = r.uint8("Op Code")
    if code != ControlOpCode.RESPONSE_CODE:
        raise FtmsParseError(f"to nie odpowiedź Control Point (kod 0x{code:02X}, oczekiwano 0x80)")
    request = r.uint8("Request Op Code")
    result = r.uint8("Result Code")
    return ControlPointResponse(request_opcode=request, result=result, parameter=r.rest())


# --- Fitness Machine Status (0x2ADA) ---------------------------------------------------


class MachineStatusOpCode(enum.IntEnum):
    RESET = 0x01
    STOPPED_OR_PAUSED_BY_USER = 0x02
    STOPPED_BY_SAFETY_KEY = 0x03
    STARTED_OR_RESUMED_BY_USER = 0x04
    TARGET_SPEED_CHANGED = 0x05
    TARGET_INCLINE_CHANGED = 0x06
    TARGET_RESISTANCE_LEVEL_CHANGED = 0x07
    TARGET_POWER_CHANGED = 0x08
    TARGET_HEART_RATE_CHANGED = 0x09
    TARGETED_EXPENDED_ENERGY_CHANGED = 0x0A
    TARGETED_STEPS_CHANGED = 0x0B
    TARGETED_STRIDES_CHANGED = 0x0C
    TARGETED_DISTANCE_CHANGED = 0x0D
    TARGETED_TRAINING_TIME_CHANGED = 0x0E
    TARGETED_TIME_IN_TWO_HR_ZONES_CHANGED = 0x0F
    TARGETED_TIME_IN_THREE_HR_ZONES_CHANGED = 0x10
    TARGETED_TIME_IN_FIVE_HR_ZONES_CHANGED = 0x11
    INDOOR_BIKE_SIMULATION_CHANGED = 0x12
    WHEEL_CIRCUMFERENCE_CHANGED = 0x13
    SPIN_DOWN_STATUS = 0x14
    TARGETED_CADENCE_CHANGED = 0x15
    CONTROL_PERMISSION_LOST = 0xFF


@dataclass(frozen=True, slots=True)
class MachineStatus:
    """Zdarzenie Fitness Machine Status. Pola szczegółowe wypełnione dla znanych kodów."""

    opcode: int
    parameter: bytes = b""
    target_power_w: int | None = None
    target_incline_percent: float | None = None
    target_resistance_level: float | None = None
    grade_percent: float | None = None
    wind_speed_mps: float | None = None
    crr: float | None = None
    cw_kg_per_m: float | None = None
    stopped: bool | None = None  # True = stop, False = pauza (dla 0x02)

    @property
    def name(self) -> str:
        try:
            return MachineStatusOpCode(self.opcode).name
        except ValueError:
            return f"0x{self.opcode:02X}"

    @property
    def control_lost(self) -> bool:
        return self.opcode == MachineStatusOpCode.CONTROL_PERMISSION_LOST


def parse_machine_status(data: bytes | bytearray | memoryview) -> MachineStatus:
    r = _Reader(data)
    code = r.uint8("Op Code")
    s = MachineStatusOpCode
    if code == s.TARGET_POWER_CHANGED:
        return MachineStatus(code, target_power_w=r.sint16("Target Power"))
    if code == s.TARGET_INCLINE_CHANGED:
        return MachineStatus(code, target_incline_percent=r.sint16("Target Incline") / 10.0)
    if code == s.TARGET_RESISTANCE_LEVEL_CHANGED:
        return MachineStatus(code, target_resistance_level=r.uint8("Target Resistance Level") / 10.0)
    if code == s.INDOOR_BIKE_SIMULATION_CHANGED:
        wind = r.sint16("Wind Speed") / 1000.0
        grade = r.sint16("Grade") / 100.0
        crr = r.uint8("Crr") / 10000.0
        cw = r.uint8("Cw") / 100.0
        return MachineStatus(code, wind_speed_mps=wind, grade_percent=grade, crr=crr, cw_kg_per_m=cw)
    if code == s.STOPPED_OR_PAUSED_BY_USER:
        value = r.uint8("Control Information") if r.remaining else 0x01
        return MachineStatus(code, parameter=bytes([value]), stopped=value != 0x02)
    return MachineStatus(code, parameter=r.rest())


# --- Fitness Machine Feature (0x2ACC) i Supported Power Range (0x2AD8) ---------------------


class MachineFeature(enum.IntFlag):
    AVERAGE_SPEED = 1 << 0
    CADENCE = 1 << 1
    TOTAL_DISTANCE = 1 << 2
    INCLINATION = 1 << 3
    ELEVATION_GAIN = 1 << 4
    PACE = 1 << 5
    STEP_COUNT = 1 << 6
    RESISTANCE_LEVEL = 1 << 7
    STRIDE_COUNT = 1 << 8
    EXPENDED_ENERGY = 1 << 9
    HEART_RATE = 1 << 10
    METABOLIC_EQUIVALENT = 1 << 11
    ELAPSED_TIME = 1 << 12
    REMAINING_TIME = 1 << 13
    POWER_MEASUREMENT = 1 << 14
    FORCE_ON_BELT_AND_POWER_OUTPUT = 1 << 15
    USER_DATA_RETENTION = 1 << 16


class TargetSettingFeature(enum.IntFlag):
    SPEED = 1 << 0
    INCLINATION = 1 << 1
    RESISTANCE = 1 << 2
    POWER = 1 << 3
    HEART_RATE = 1 << 4
    EXPENDED_ENERGY = 1 << 5
    STEP_NUMBER = 1 << 6
    STRIDE_NUMBER = 1 << 7
    DISTANCE = 1 << 8
    TRAINING_TIME = 1 << 9
    TIME_IN_TWO_HR_ZONES = 1 << 10
    TIME_IN_THREE_HR_ZONES = 1 << 11
    TIME_IN_FIVE_HR_ZONES = 1 << 12
    INDOOR_BIKE_SIMULATION = 1 << 13
    WHEEL_CIRCUMFERENCE = 1 << 14
    SPIN_DOWN = 1 << 15
    CADENCE = 1 << 16


@dataclass(frozen=True, slots=True)
class FitnessMachineFeatures:
    machine: int
    target: int

    @property
    def power_measurement(self) -> bool:
        return bool(self.machine & MachineFeature.POWER_MEASUREMENT)

    @property
    def cadence(self) -> bool:
        return bool(self.machine & MachineFeature.CADENCE)

    @property
    def power_target(self) -> bool:
        return bool(self.target & TargetSettingFeature.POWER)

    @property
    def simulation(self) -> bool:
        return bool(self.target & TargetSettingFeature.INDOOR_BIKE_SIMULATION)

    def describe(self) -> str:
        def mark(ok: bool) -> str:
            return "tak" if ok else "nie"

        return (
            f"pomiar mocy: {mark(self.power_measurement)}, kadencja: {mark(self.cadence)}, "
            f"ERG: {mark(self.power_target)}, symulacja nachylenia: {mark(self.simulation)}"
        )


def parse_features(data: bytes | bytearray | memoryview) -> FitnessMachineFeatures:
    r = _Reader(data)
    return FitnessMachineFeatures(machine=r.uint32("Fitness Machine Features"), target=r.uint32("Target Setting Features"))


@dataclass(frozen=True, slots=True)
class PowerRange:
    minimum_w: int
    maximum_w: int
    increment_w: int

    def clamp(self, watts: int) -> int:
        if self.maximum_w < self.minimum_w:
            return watts
        return max(self.minimum_w, min(self.maximum_w, watts))


def parse_supported_power_range(data: bytes | bytearray | memoryview) -> PowerRange:
    r = _Reader(data)
    return PowerRange(r.sint16("Minimum Power"), r.sint16("Maximum Power"), r.uint16("Minimum Increment"))
