"""Protokół v1 między mostkiem a grą: JSON w ramkach tekstowych WebSocket.

Mostek -> gra:
  {"type":"data","power":<int W>,"cadence":<float obr/min>,"speed":<float km/h>,"timestamp":<float unix s>}
      co 250 ms, tylko gdy trenażer jest połączony (albo działa symulator),
  {"type":"status","state":"searching|connecting|connected|disconnected|sim","device":<nazwa|null>,
   "erg":<W|null>,"grade":<%|null>}
      po połączeniu klienta i przy każdej zmianie,
  {"type":"pong"} w odpowiedzi na ping, {"type":"error","message":...} dla błędnych komend.

Gra -> mostek:
  {"cmd":"erg","watts":N}    N <= 0 wyłącza ERG,
  {"cmd":"slope","grade":G}  nachylenie w procentach (przycinane do ±20 %),
  {"cmd":"ping"}.
Nieznane pola są ignorowane (zgodność w przód).
"""

from __future__ import annotations

import enum
import json
import math
from dataclasses import dataclass
from typing import Any

#: Maksymalny cel ERG przyjmowany od gry – większe wartości to raczej błąd planu niż zamiar.
MAX_ERG_WATTS = 2000
#: Zakres nachylenia przekazywany do trenażera (Suito ma maks. 15 %).
GRADE_LIMIT_PERCENT = 20.0
#: Komendy są krótkie; dłuższe ramki odrzucamy bez parsowania.
MAX_COMMAND_CHARS = 4096


class LinkState(enum.StrEnum):
    """Stan łącza mostek <-> trenażer, wysyłany w polu "state"."""

    SEARCHING = "searching"
    CONNECTING = "connecting"
    CONNECTED = "connected"
    DISCONNECTED = "disconnected"
    SIM = "sim"

    @property
    def delivers_data(self) -> bool:
        return self in (LinkState.CONNECTED, LinkState.SIM)


class ProtocolError(ValueError):
    """Niepoprawna komenda od klienta. Treść trafia do {"type":"error"}."""


@dataclass(frozen=True, slots=True)
class ErgCommand:
    watts: int | None  # None = ERG wyłączony


@dataclass(frozen=True, slots=True)
class SlopeCommand:
    grade_percent: float


@dataclass(frozen=True, slots=True)
class PingCommand:
    pass


Command = ErgCommand | SlopeCommand | PingCommand


def parse_command(raw: str | bytes | bytearray | memoryview) -> Command:
    """Zamienia ramkę od gry na komendę. Rzuca ProtocolError z opisem po polsku."""
    if not isinstance(raw, str):
        raise ProtocolError("oczekiwano ramki tekstowej z JSON (nie binarnej)")
    if len(raw) > MAX_COMMAND_CHARS:
        raise ProtocolError(f"komenda za długa ({len(raw)} znaków, maks. {MAX_COMMAND_CHARS})")
    try:
        obj = json.loads(raw)
    except (json.JSONDecodeError, RecursionError) as exc:
        message = exc.msg if isinstance(exc, json.JSONDecodeError) else "za głębokie zagnieżdżenie"
        raise ProtocolError(f"niepoprawny JSON: {message}") from None
    if not isinstance(obj, dict):
        raise ProtocolError("oczekiwano obiektu JSON, np. {\"cmd\":\"ping\"}")
    cmd = obj.get("cmd")
    if not isinstance(cmd, str):
        raise ProtocolError("brak pola \"cmd\" (tekst)")
    if cmd == "erg":
        watts = _number(obj, "watts")
        if watts > MAX_ERG_WATTS:
            raise ProtocolError(f"\"watts\" poza zakresem (0..{MAX_ERG_WATTS}): {watts:g}")
        rounded = round(watts)
        return ErgCommand(rounded if rounded > 0 else None)
    if cmd == "slope":
        grade = _number(obj, "grade")
        grade = max(-GRADE_LIMIT_PERCENT, min(GRADE_LIMIT_PERCENT, grade))
        return SlopeCommand(round(grade, 2))
    if cmd == "ping":
        return PingCommand()
    raise ProtocolError(f"nieznana komenda \"{cmd}\" (znane: erg, slope, ping)")


def _number(obj: dict[str, Any], key: str) -> float:
    value = obj.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ProtocolError(f"pole \"{key}\" musi być liczbą")
    number = float(value)
    if not math.isfinite(number):
        raise ProtocolError(f"pole \"{key}\" musi być skończoną liczbą")
    return number


# --- Wiadomości mostek -> gra --------------------------------------------------------------


def _dumps(obj: dict[str, Any]) -> str:
    return json.dumps(obj, ensure_ascii=False, allow_nan=False, separators=(",", ":"))


def _finite(value: float, default: float = 0.0) -> float:
    return value if math.isfinite(value) else default


def data_message(power_w: float, cadence_rpm: float, speed_kmh: float, timestamp: float) -> str:
    return _dumps(
        {
            "type": "data",
            "power": max(0, round(_finite(power_w))),
            "cadence": round(max(0.0, _finite(cadence_rpm)), 1),
            "speed": round(max(0.0, _finite(speed_kmh)), 2),
            "timestamp": round(_finite(timestamp), 3),
        }
    )


def status_message(state: LinkState, device: str | None, erg_watts: int | None, grade_percent: float | None) -> str:
    return _dumps(
        {
            "type": "status",
            "state": str(state),
            "device": device,
            "erg": erg_watts,
            "grade": None if grade_percent is None else round(_finite(grade_percent), 2),
        }
    )


def pong_message() -> str:
    return _dumps({"type": "pong"})


def error_message(message: str) -> str:
    return _dumps({"type": "error", "message": message})
