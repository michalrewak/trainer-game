"""Symulator trenażera: ERG ~2 s, nachylenie zmienia moc i prędkość, kadencja 80–95."""

import asyncio
import statistics

import pytest

from wasteland_bridge.protocol import LinkState
from wasteland_bridge.state import BridgeState
from wasteland_bridge.trainer_sim import SimModel, SimTrainer

DT = 0.25


def run(model: SimModel, seconds: float) -> list[float]:
    powers = []
    for _ in range(round(seconds / DT)):
        model.step(DT)
        powers.append(model.power_w)
    return powers


def test_same_seed_same_ride():
    a, b = SimModel(seed=7), SimModel(seed=7)
    assert run(a, 30) == run(b, 30)
    assert run(SimModel(seed=8), 30) != run(SimModel(seed=7), 30)


def test_erg_step_reaches_target_in_about_two_seconds():
    m = SimModel(seed=1, base_power_w=150, noise=0.0)
    run(m, 10)
    assert m.power_w == pytest.approx(150, abs=1)
    m.erg_watts = 250
    run(m, 0.5)
    assert m.power_w < 230, "ERG nie skacze natychmiast"
    run(m, 1.5)
    assert m.power_w >= 240, "po ~2 s ERG trzyma ~95 % celu"
    run(m, 3)
    assert m.power_w == pytest.approx(250, abs=1)


def test_free_ride_power_hovers_around_base_with_noise():
    m = SimModel(seed=3, base_power_w=180)
    powers = run(m, 120)
    assert 140 < statistics.mean(powers) < 220
    assert statistics.pstdev(powers) > 1.0, "moc nie jest stała"
    assert min(powers) > 60


def test_cadence_stays_in_range():
    m = SimModel(seed=5)
    for grade in (0.0, 8.0, -5.0):
        m.grade_percent = grade
        for _ in range(200):
            m.step(DT)
            assert 80.0 <= m.cadence_rpm <= 95.0


def test_grade_changes_power_and_speed_plausibly():
    flat = SimModel(seed=2, base_power_w=180, noise=0.0)
    climb = SimModel(seed=2, base_power_w=180, noise=0.0)
    descent = SimModel(seed=2, base_power_w=180, noise=0.0)
    climb.grade_percent = 6.0
    descent.grade_percent = -4.0
    for m in (flat, climb, descent):
        run(m, 180)
    assert climb.power_w > flat.power_w > descent.power_w
    assert 28 < flat.speed_kmh < 38
    assert 10 < climb.speed_kmh < 20
    assert descent.speed_kmh > flat.speed_kmh


def test_erg_ignores_grade_for_power():
    m = SimModel(seed=4, noise=0.0)
    m.erg_watts = 200
    m.grade_percent = 10.0
    run(m, 10)
    assert m.power_w == pytest.approx(200, abs=1)


def test_sim_trainer_feeds_state_and_follows_erg():
    async def scenario():
        state = BridgeState()
        trainer = SimTrainer(state, seed=11, rate_hz=40.0)
        task = asyncio.create_task(trainer.run())
        await asyncio.sleep(0.2)
        assert state.link == LinkState.SIM
        assert state.packets > 3
        assert state.data_frame() is not None
        state.set_erg(300)
        await asyncio.sleep(0.4)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        assert trainer.model.erg_watts == 300
        assert state.measurement.power_w > 200

    asyncio.run(scenario())


def test_sim_dropout_goes_through_all_states():
    async def scenario():
        state = BridgeState()
        seen: list[LinkState] = []
        state.add_status_listener(lambda: seen.append(state.link))
        trainer = SimTrainer(state, seed=1, rate_hz=40.0, dropout_every_s=0.15, dropout_duration_s=1.0)
        task = asyncio.create_task(trainer.run())
        await asyncio.sleep(1.4)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task
        assert seen[:5] == [
            LinkState.SIM,
            LinkState.DISCONNECTED,
            LinkState.SEARCHING,
            LinkState.CONNECTING,
            LinkState.SIM,
        ]

    asyncio.run(scenario())
