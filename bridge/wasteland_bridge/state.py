"""Wspólny stan mostka: łącze z trenażerem, ostatni pomiar oraz cele ERG/nachylenia zadane przez grę.

Cały mostek działa w jednej pętli asyncio, więc stan nie potrzebuje blokad. Zmiany są
rozgłaszane słuchaczom: serwer WebSocket wysyła wtedy status, a trenażer stosuje nowe cele.
"""

from __future__ import annotations

import logging
import time
from collections.abc import Callable
from dataclasses import dataclass

from .ftms import IndoorBikeData
from .protocol import LinkState, data_message, status_message

log = logging.getLogger(__name__)

#: Gdy trenażer jest połączony, ale od tylu sekund nie przysłał pomiaru, wysyłamy zera
#: (koło stoi). Martwe łącze BLE i tak zgłosi rozłączenie po kilku sekundach.
MEASUREMENT_STALE_S = 3.0

Listener = Callable[[], None]


@dataclass(slots=True)
class Measurement:
    power_w: int = 0
    cadence_rpm: float = 0.0
    speed_kmh: float = 0.0
    heart_rate_bpm: int | None = None
    resistance_level: int | None = None
    updated_at: float | None = None  # zegar monotoniczny; None = jeszcze nic nie przyszło


class BridgeState:
    def __init__(
        self,
        *,
        clock: Callable[[], float] = time.monotonic,
        wall_clock: Callable[[], float] = time.time,
    ) -> None:
        self._clock = clock
        self._wall_clock = wall_clock
        self.link = LinkState.SEARCHING
        self.device: str | None = None
        self.erg_watts: int | None = None
        self.grade_percent: float | None = None
        self.measurement = Measurement()
        self.packets = 0
        self.clients = 0
        self._status_listeners: list[Listener] = []
        self._target_listeners: list[Listener] = []

    # --- Słuchacze ----------------------------------------------------------------------

    def add_status_listener(self, listener: Listener) -> None:
        """Wołany po każdej zmianie pól statusu (łącze, urządzenie, ERG, nachylenie)."""
        self._status_listeners.append(listener)

    def add_target_listener(self, listener: Listener) -> None:
        """Wołany po zmianie celu ERG albo nachylenia."""
        self._target_listeners.append(listener)

    def _emit(self, listeners: list[Listener]) -> None:
        for listener in list(listeners):
            try:
                listener()
            except Exception:  # słuchacz nie może położyć mostka
                log.exception("Błąd w obsłudze zmiany stanu")

    # --- Łącze z trenażerem ---------------------------------------------------------------

    def set_link(self, link: LinkState, device: str | None) -> None:
        if link == self.link and device == self.device:
            return
        self.link = link
        self.device = device
        if not link.delivers_data:
            # Po ponownym połączeniu zaczynamy od świeżego pomiaru, nie od starego.
            self.measurement = Measurement()
        self._emit(self._status_listeners)

    # --- Cele zadane przez grę ------------------------------------------------------------

    def set_erg(self, watts: int | None) -> bool:
        """Cel ERG w watach albo None (wyłączony). Zwraca True, gdy coś się zmieniło."""
        if watts is not None and watts <= 0:
            watts = None
        if watts == self.erg_watts:
            return False
        self.erg_watts = watts
        self._emit(self._status_listeners)
        self._emit(self._target_listeners)
        return True

    def set_grade(self, grade_percent: float | None) -> bool:
        if grade_percent is not None:
            grade_percent = round(grade_percent, 2)
        if grade_percent == self.grade_percent:
            return False
        self.grade_percent = grade_percent
        self._emit(self._status_listeners)
        self._emit(self._target_listeners)
        return True

    # --- Pomiary --------------------------------------------------------------------------

    def apply_bike_data(self, data: IndoorBikeData) -> None:
        """Nanosi pola obecne w pakiecie (pakiety „More Data” niosą tylko część pól)."""
        m = self.measurement
        if data.instantaneous_power_w is not None:
            m.power_w = max(0, data.instantaneous_power_w)
        if data.instantaneous_cadence_rpm is not None:
            m.cadence_rpm = data.instantaneous_cadence_rpm
        if data.instantaneous_speed_kmh is not None:
            m.speed_kmh = data.instantaneous_speed_kmh
        if data.heart_rate_bpm is not None:
            m.heart_rate_bpm = data.heart_rate_bpm
        if data.resistance_level is not None:
            m.resistance_level = data.resistance_level
        m.updated_at = self._clock()
        self.packets += 1

    def update_measurement(self, *, power_w: float, cadence_rpm: float, speed_kmh: float) -> None:
        """Pełny pomiar naraz (symulator)."""
        m = self.measurement
        m.power_w = max(0, round(power_w))
        m.cadence_rpm = max(0.0, cadence_rpm)
        m.speed_kmh = max(0.0, speed_kmh)
        m.updated_at = self._clock()
        self.packets += 1

    def measurement_age(self) -> float | None:
        if self.measurement.updated_at is None:
            return None
        return self._clock() - self.measurement.updated_at

    def live_measurement(self) -> Measurement | None:
        """Pomiar do wysłania grze; None, gdy trenażer nie daje danych (brak łącza, brak pakietu)."""
        if not self.link.delivers_data:
            return None
        age = self.measurement_age()
        if age is None:
            return None
        if age > MEASUREMENT_STALE_S:
            return Measurement(updated_at=self.measurement.updated_at)
        return self.measurement

    # --- Ramki protokołu ------------------------------------------------------------------

    def data_frame(self) -> str | None:
        m = self.live_measurement()
        if m is None:
            return None
        return data_message(m.power_w, m.cadence_rpm, m.speed_kmh, self._wall_clock())

    def status_frame(self) -> str:
        return status_message(self.link, self.device, self.erg_watts, self.grade_percent)
