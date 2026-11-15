"""Sterowanie trenażerem przez FTMS Control Point – bez zależności od BLE (testowalne).

ControlPointClient zapisuje komendę i czeka na wskazanie (indication) z kodem 0x80,
plan_target() decyduje, co trenażer powinien mieć ustawione, a Backoff liczy przerwy
między kolejnymi próbami połączenia.
"""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Awaitable, Callable, Sequence
from dataclasses import dataclass

from . import ftms

log = logging.getLogger(__name__)

Writer = Callable[[bytes], Awaitable[object]]


class ControlPointTimeout(TimeoutError):
    """Trenażer nie odpowiedział na komendę Control Point w zadanym czasie."""


class ControlPointClient:
    """Jedna komenda naraz: zapis -> czekanie na odpowiedź z pasującym Request Op Code."""

    def __init__(self, write: Writer, *, timeout_s: float = 3.0) -> None:
        self._write = write
        self._timeout_s = timeout_s
        self._lock = asyncio.Lock()
        self._pending: tuple[int, asyncio.Future[ftms.ControlPointResponse]] | None = None
        self.last_response: ftms.ControlPointResponse | None = None

    def handle_indication(self, data: bytes | bytearray) -> ftms.ControlPointResponse | None:
        """Wołane z obsługi wskazań BLE. Odpowiedź może przyjść, zanim zapis się zakończy."""
        try:
            response = ftms.parse_control_point_response(data)
        except ftms.FtmsParseError as exc:
            log.warning("Niezrozumiała odpowiedź Control Point: %s", exc)
            return None
        self.last_response = response
        pending = self._pending
        if pending is not None and pending[0] == response.request_opcode and not pending[1].done():
            pending[1].set_result(response)
        else:
            log.debug("Odpowiedź Control Point bez oczekującej komendy: %s", response.describe())
        return response

    async def execute(self, payload: bytes) -> ftms.ControlPointResponse:
        """Wysyła komendę i zwraca odpowiedź (także niepomyślną). Rzuca ControlPointTimeout."""
        if not payload:
            raise ValueError("pusta komenda Control Point")
        async with self._lock:
            future: asyncio.Future[ftms.ControlPointResponse] = asyncio.get_running_loop().create_future()
            self._pending = (payload[0], future)
            try:
                await self._write(payload)
                try:
                    return await asyncio.wait_for(future, self._timeout_s)
                except TimeoutError:
                    raise ControlPointTimeout(
                        f"trenażer nie odpowiedział na {ftms.opcode_name(payload[0])} w {self._timeout_s:g} s"
                    ) from None
            finally:
                self._pending = None

    async def request_control(self) -> ftms.ControlPointResponse:
        return await self.execute(ftms.encode_request_control())

    async def start_or_resume(self) -> ftms.ControlPointResponse:
        return await self.execute(ftms.encode_start_or_resume())


@dataclass(frozen=True, slots=True)
class Target:
    """Ustawienie trenażera: tryb ERG (moc w W) albo symulacja (nachylenie w %)."""

    mode: str  # "erg" | "sim"
    value: float

    def encode(self) -> bytes:
        if self.mode == "erg":
            return ftms.encode_set_target_power(self.value)
        return ftms.encode_set_indoor_bike_simulation(self.value)

    def describe(self) -> str:
        if self.mode == "erg":
            return f"ERG {round(self.value)} W"
        return f"nachylenie {self.value:.1f} %".replace(".", ",")


def plan_target(
    erg_watts: int | None,
    grade_percent: float | None,
    applied: Target | None,
    power_range: ftms.PowerRange | None = None,
) -> Target | None:
    """Co trenażer powinien mieć ustawione.

    ERG ma pierwszeństwo przed nachyleniem (zaplanowany trening musi zostać zrealizowany):
    nachylenie zadane w czasie ERG czeka i wchodzi po wyłączeniu ERG. Bez żadnego celu nic
    nie wysyłamy – chyba że wcześniej coś ustawiliśmy; wtedy wracamy do płaskiej symulacji (0 %),
    co zdejmuje opór ERG.
    """
    if erg_watts is not None and erg_watts > 0:
        watts = power_range.clamp(erg_watts) if power_range is not None else erg_watts
        return Target("erg", float(watts))
    if grade_percent is not None:
        return Target("sim", float(grade_percent))
    if applied is not None:
        return Target("sim", 0.0)
    return None


class Backoff:
    """Rosnące przerwy między próbami: kolejne wartości z listy, potem stale ostatnia."""

    def __init__(self, delays: Sequence[float]) -> None:
        if not delays:
            raise ValueError("lista przerw nie może być pusta")
        self._delays = tuple(float(d) for d in delays)
        self._attempt = 0

    def next(self) -> float:
        delay = self._delays[min(self._attempt, len(self._delays) - 1)]
        self._attempt += 1
        return delay

    def reset(self) -> None:
        self._attempt = 0
