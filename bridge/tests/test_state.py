"""BridgeState: łącze, cele ERG/nachylenia, ramki danych i ich „świeżość”."""

import json

from wasteland_bridge import ftms
from wasteland_bridge.protocol import LinkState
from wasteland_bridge.state import MEASUREMENT_STALE_S, BridgeState


class Clock:
    def __init__(self, t: float = 1000.0) -> None:
        self.t = t

    def __call__(self) -> float:
        return self.t


def make() -> tuple[BridgeState, Clock, list[str]]:
    clock = Clock()
    state = BridgeState(clock=clock, wall_clock=lambda: 1763236800.0)
    events: list[str] = []
    state.add_status_listener(lambda: events.append("status"))
    state.add_target_listener(lambda: events.append("target"))
    return state, clock, events


def test_link_changes_notify_once():
    state, _, events = make()
    state.set_link(LinkState.CONNECTING, "SUITO 1")
    state.set_link(LinkState.CONNECTING, "SUITO 1")
    state.set_link(LinkState.CONNECTED, "SUITO 1")
    assert events == ["status", "status"]


def test_erg_and_grade_targets():
    state, _, events = make()
    assert state.set_erg(200)
    assert not state.set_erg(200)
    assert events == ["status", "target"]
    assert state.set_erg(0)
    assert state.erg_watts is None
    assert state.set_grade(3.14159)
    assert state.grade_percent == 3.14
    assert not state.set_grade(3.14)
    status = json.loads(state.status_frame())
    assert status["erg"] is None and status["grade"] == 3.14


def test_no_data_frames_without_trainer_or_measurement():
    state, _, _ = make()
    assert state.data_frame() is None  # szukanie
    state.set_link(LinkState.CONNECTED, "SUITO 1")
    assert state.data_frame() is None  # połączony, ale jeszcze bez pakietu


def test_data_frame_after_measurement_and_zeros_when_stale():
    state, clock, _ = make()
    state.set_link(LinkState.CONNECTED, "SUITO 1")
    state.apply_bike_data(ftms.parse_indoor_bike_data(bytes.fromhex("4400100eb400c800")))
    frame = json.loads(state.data_frame())
    assert frame == {"type": "data", "power": 200, "cadence": 90.0, "speed": 36.0, "timestamp": 1763236800.0}
    clock.t += MEASUREMENT_STALE_S + 0.1
    stale = json.loads(state.data_frame())
    assert stale["power"] == 0 and stale["cadence"] == 0.0 and stale["speed"] == 0.0


def test_disconnect_resets_measurement():
    state, _, _ = make()
    state.set_link(LinkState.CONNECTED, "SUITO 1")
    state.update_measurement(power_w=250, cadence_rpm=90, speed_kmh=35)
    state.set_link(LinkState.DISCONNECTED, "SUITO 1")
    assert state.data_frame() is None
    state.set_link(LinkState.CONNECTED, "SUITO 1")
    assert state.data_frame() is None, "po ponownym połączeniu czekamy na świeży pomiar"


def test_listener_errors_do_not_propagate():
    state = BridgeState()

    def broken() -> None:
        raise RuntimeError("bum")

    state.add_status_listener(broken)
    state.set_link(LinkState.SIM, "SIM")  # nie rzuca
    assert state.link == LinkState.SIM
