"""Podgląd na żywo w terminalu (rich) albo prosty tryb tekstowy (--no-ui, praca w tle)."""

from __future__ import annotations

import asyncio
import logging

from rich.console import Console
from rich.live import Live
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

from .protocol import LinkState
from .state import BridgeState

log = logging.getLogger(__name__)

STATE_LABELS: dict[LinkState, tuple[str, str]] = {
    LinkState.SEARCHING: ("SZUKAM TRENAŻERA", "bold yellow"),
    LinkState.CONNECTING: ("ŁĄCZĘ…", "bold yellow"),
    LinkState.CONNECTED: ("POŁĄCZONY", "bold green"),
    LinkState.DISCONNECTED: ("ROZŁĄCZONY – ponawiam", "bold red"),
    LinkState.SIM: ("SYMULATOR (--sim)", "bold cyan"),
}


def _pl(value: float, digits: int) -> str:
    """Liczba z przecinkiem dziesiętnym."""
    return f"{value:.{digits}f}".replace(".", ",")


def summary_line(state: BridgeState) -> str:
    label = STATE_LABELS[state.link][0]
    m = state.live_measurement()
    data = (
        f"moc {m.power_w} W, kadencja {_pl(m.cadence_rpm, 0)} obr/min, prędkość {_pl(m.speed_kmh, 1)} km/h"
        if m is not None
        else "brak danych"
    )
    erg = f"{state.erg_watts} W" if state.erg_watts else "wył."
    grade = f"{_pl(state.grade_percent, 1)} %" if state.grade_percent is not None else "–"
    return f"[{label}] {state.device or '–'}: {data} | ERG {erg}, nachylenie {grade} | gra: {state.clients}"


def render(state: BridgeState, url: str) -> Panel:
    label, style = STATE_LABELS[state.link]
    m = state.live_measurement()
    table = Table.grid(padding=(0, 3))
    table.add_column(justify="right", style="dim")
    table.add_column(min_width=28)
    table.add_row("Stan", Text(label, style=style))
    table.add_row("Urządzenie", state.device or "–")
    table.add_row("Moc", Text(f"{m.power_w} W" if m else "–", style="bold"))
    table.add_row("Kadencja", f"{_pl(m.cadence_rpm, 0)} obr/min" if m else "–")
    table.add_row("Prędkość", f"{_pl(m.speed_kmh, 1)} km/h" if m else "–")
    if m is not None and m.heart_rate_bpm:
        table.add_row("Tętno", f"{m.heart_rate_bpm} ud/min")
    table.add_row("ERG", Text(f"{state.erg_watts} W" if state.erg_watts else "wyłączony", style="bold magenta" if state.erg_watts else ""))
    table.add_row("Nachylenie", f"{_pl(state.grade_percent, 1)} %" if state.grade_percent is not None else "–")
    table.add_row("Gra (klienci)", str(state.clients))
    age = state.measurement_age()
    table.add_row("Ostatni pomiar", f"{_pl(age, 1)} s temu · pakietów: {state.packets}" if age is not None else "–")
    border = style.replace("bold ", "")
    return Panel(table, title="Wasteland Rider · mostek trenażera", subtitle=f"{url} · Ctrl+C kończy", border_style=border, expand=False)


class LiveView:
    """Odświeżanie w pętli asyncio (bez wątku rich), żeby nie czytać stanu z dwóch wątków."""

    def __init__(self, state: BridgeState, console: Console, url: str, *, refresh_s: float = 0.25) -> None:
        self.state = state
        self.console = console
        self.url = url
        self.refresh_s = refresh_s

    async def run(self) -> None:
        with Live(render(self.state, self.url), console=self.console, auto_refresh=False) as live:
            while True:
                await asyncio.sleep(self.refresh_s)
                live.update(render(self.state, self.url), refresh=True)


class PlainReporter:
    """Bez terminala: co kilka sekund jedna linia stanu w logu."""

    def __init__(self, state: BridgeState, *, interval_s: float = 5.0) -> None:
        self.state = state
        self.interval_s = interval_s

    async def run(self) -> None:
        while True:
            await asyncio.sleep(self.interval_s)
            log.info(summary_line(self.state))
