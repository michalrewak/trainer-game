"""Symulowany trenażer (--sim): wiarygodne dane bez sprzętu, ten sam protokół co prawdziwy.

SimModel to czysty model (testowalny bez asyncio), SimTrainer co 250 ms przelicza go
i wpisuje pomiar do BridgeState. Opcjonalnie udaje zerwania łącza (--sim-dropout-every),
żeby sprawdzić pauzę i wznawianie wyprawy w grze.
"""

from __future__ import annotations

import asyncio
import logging
import math
import random

from .protocol import LinkState
from .state import BridgeState

log = logging.getLogger(__name__)

SIM_DEVICE_NAME = "SIM SUITO"
GRAVITY = 9.81
AIR_DENSITY = 1.2


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


class SimModel:
    """Kolarz + trenażer.

    - Bez ERG: moc = baza + powolny dryf (proces Ornsteina-Uhlenbecka, ±25 W) + reakcja na
      nachylenie (pod górę mocniej, z góry luźniej), dochodzenie do celu ze stałą 1,5 s.
    - ERG: trenażer dociąga moc do celu odpowiedzią pierwszego rzędu (~2 s do 95 %).
    - Szum pomiaru ~1,5 % mocy. Kadencja 80–95 obr./min, pod górę niższa.
    - Prędkość z równania ruchu: grawitacja, opór toczenia i powietrza – nachylenie ją zmienia.
    """

    ERG_TAU_S = 0.65
    FREE_TAU_S = 1.5
    DRIFT_TAU_S = 40.0
    DRIFT_SIGMA_W = 25.0
    #: Pod górę kolarz dokłada 6 % mocy na każdy 1 % nachylenia (maks. +80 %).
    UPHILL_GAIN = 0.06
    #: Z góry odpuszcza 12 % mocy na każdy 1 % spadku (min. 15 % bazy).
    DOWNHILL_GAIN = 0.12

    def __init__(
        self,
        *,
        seed: int | None = None,
        base_power_w: float = 180.0,
        noise: float = 1.0,
        mass_kg: float = 85.0,
    ) -> None:
        self.rng = random.Random(seed)
        self.base_power_w = max(0.0, base_power_w)
        self.noise = noise
        self.mass_kg = mass_kg
        self.crr = 0.004
        self.cda_m2 = 0.32
        self.erg_watts: int | None = None
        self.grade_percent = 0.0
        self.time_s = 0.0
        self.power_w = self.base_power_w
        self.cadence_rpm = 88.0
        self.speed_mps = 8.0
        self._effort_w = self.base_power_w
        self._drift_w = 0.0
        self._cadence_base = 88.0

    @property
    def speed_kmh(self) -> float:
        return self.speed_mps * 3.6

    def target_power(self) -> float:
        if self.erg_watts is not None and self.erg_watts > 0:
            return float(self.erg_watts)
        g = self.grade_percent
        if g >= 0.0:
            factor = min(1.8, 1.0 + self.UPHILL_GAIN * g)
        else:
            factor = max(0.15, 1.0 + self.DOWNHILL_GAIN * g)
        return max(0.0, self.base_power_w * factor + self._drift_w)

    def step(self, dt: float) -> None:
        if dt <= 0.0:
            return
        self.time_s += dt
        rng = self.rng
        # Powolny dryf formy/„chęci” (OU): średnio 0, odchylenie DRIFT_SIGMA_W.
        self._drift_w += -self._drift_w / self.DRIFT_TAU_S * dt + self.DRIFT_SIGMA_W * math.sqrt(
            2.0 * dt / self.DRIFT_TAU_S
        ) * rng.gauss(0.0, 1.0) * self.noise
        erg = self.erg_watts is not None and self.erg_watts > 0
        tau = self.ERG_TAU_S if erg else self.FREE_TAU_S
        self._effort_w += (self.target_power() - self._effort_w) * (1.0 - math.exp(-dt / tau))
        jitter = rng.gauss(0.0, 0.015 * self._effort_w + 1.5) * self.noise
        self.power_w = max(0.0, self._effort_w + jitter)

        cadence_goal = 88.0 - 0.8 * max(0.0, self.grade_percent) + (2.0 if erg else 0.0)
        cadence_goal += 3.0 * math.sin(self.time_s * math.tau / 23.0)
        self._cadence_base += (cadence_goal - self._cadence_base) * (1.0 - math.exp(-dt / 3.0))
        if self.power_w < 5.0:
            self.cadence_rpm = 0.0
        else:
            self.cadence_rpm = _clamp(self._cadence_base + rng.gauss(0.0, 0.8) * self.noise, 80.0, 95.0)

        theta = math.atan(self.grade_percent / 100.0)
        v = self.speed_mps
        drive = self.power_w / max(v, 1.0)
        resist = self.mass_kg * GRAVITY * (math.sin(theta) + self.crr * math.cos(theta))
        resist += 0.5 * AIR_DENSITY * self.cda_m2 * v * v
        self.speed_mps = max(0.0, v + (drive - resist) / (self.mass_kg + 3.0) * dt)


class SimTrainer:
    def __init__(
        self,
        state: BridgeState,
        *,
        seed: int | None = None,
        base_power_w: float = 180.0,
        rate_hz: float = 4.0,
        dropout_every_s: float = 0.0,
        dropout_duration_s: float = 6.0,
    ) -> None:
        self.state = state
        self.model = SimModel(seed=seed, base_power_w=base_power_w)
        self.rate_hz = max(0.5, rate_hz)
        self.dropout_every_s = max(0.0, dropout_every_s)
        self.dropout_duration_s = max(1.0, dropout_duration_s)

    async def run(self) -> None:
        log.info(
            "Symulator trenażera: baza %.0f W, %.0f pomiarów/s%s",
            self.model.base_power_w,
            self.rate_hz,
            f", zerwanie łącza co {self.dropout_every_s:.0f} s" if self.dropout_every_s else "",
        )
        loop = asyncio.get_running_loop()
        dt = 1.0 / self.rate_hz
        self.state.set_link(LinkState.SIM, SIM_DEVICE_NAME)
        next_tick = loop.time()
        next_dropout = loop.time() + self.dropout_every_s if self.dropout_every_s else math.inf
        while True:
            next_tick += dt
            await asyncio.sleep(max(0.0, next_tick - loop.time()))
            if loop.time() >= next_dropout:
                await self._dropout()
                next_tick = loop.time()
                next_dropout = loop.time() + self.dropout_every_s
                continue
            # Cele czytamy co krok – po „ponownym połączeniu” ERG/nachylenie wracają same.
            self.model.erg_watts = self.state.erg_watts
            self.model.grade_percent = self.state.grade_percent or 0.0
            self.model.step(dt)
            self.state.update_measurement(
                power_w=self.model.power_w,
                cadence_rpm=self.model.cadence_rpm,
                speed_kmh=self.model.speed_kmh,
            )

    async def _dropout(self) -> None:
        duration = self.dropout_duration_s
        log.warning("Symulator: udawane zerwanie łącza na %.0f s", duration)
        self.state.set_link(LinkState.DISCONNECTED, SIM_DEVICE_NAME)
        await asyncio.sleep(duration * 0.5)
        self.state.set_link(LinkState.SEARCHING, None)
        await asyncio.sleep(duration * 0.3)
        self.state.set_link(LinkState.CONNECTING, SIM_DEVICE_NAME)
        await asyncio.sleep(duration * 0.2)
        self.state.set_link(LinkState.SIM, SIM_DEVICE_NAME)
        log.info("Symulator: łącze wróciło, ERG i nachylenie obowiązują dalej")
