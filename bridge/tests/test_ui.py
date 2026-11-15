"""Podgląd w terminalu: panel rich i linia stanu dla trybu --no-ui."""

import io

from rich.console import Console

from wasteland_bridge.protocol import LinkState
from wasteland_bridge.state import BridgeState
from wasteland_bridge.ui import render, summary_line


def rendered(state: BridgeState) -> str:
    console = Console(file=io.StringIO(), force_terminal=True, color_system=None, width=100)
    console.print(render(state, "ws://127.0.0.1:8765"))
    return console.file.getvalue()


def test_panel_shows_live_values():
    state = BridgeState()
    state.set_link(LinkState.CONNECTED, "SUITO 12345")
    state.update_measurement(power_w=231, cadence_rpm=88.4, speed_kmh=31.27)
    state.set_erg(230)
    state.set_grade(2.5)
    state.clients = 1
    text = rendered(state)
    for expected in ("POŁĄCZONY", "SUITO 12345", "231 W", "88 obr/min", "31,3 km/h", "230 W", "2,5 %", "ws://127.0.0.1:8765"):
        assert expected in text, expected


def test_panel_without_trainer():
    state = BridgeState()
    text = rendered(state)
    assert "SZUKAM TRENAŻERA" in text
    assert "wyłączony" in text


def test_summary_line():
    state = BridgeState()
    assert "brak danych" in summary_line(state)
    state.set_link(LinkState.SIM, "SIM SUITO")
    state.update_measurement(power_w=180, cadence_rpm=90, speed_kmh=30)
    line = summary_line(state)
    assert "SYMULATOR" in line and "moc 180 W" in line and "ERG wył." in line
