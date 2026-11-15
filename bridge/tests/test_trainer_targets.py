"""FtmsTrainer bez Bluetooth: jakie komendy Control Point idą do trenażera przy zmianach celów,
po utracie sterowania i po ponownym połączeniu (atrapa Control Point zamiast BLE)."""

import asyncio

import pytest

from wasteland_bridge import ftms, trainer_ble
from wasteland_bridge.control import ControlPointClient, Target
from wasteland_bridge.state import BridgeState
from wasteland_bridge.trainer_ble import FtmsTrainer


class FakeControlPoint:
    def __init__(self) -> None:
        self.written: list[str] = []
        self.results: dict[int, int] = {}
        self.client = ControlPointClient(self.write, timeout_s=0.5)

    async def write(self, payload: bytes) -> None:
        self.written.append(payload.hex())
        result = self.results.get(payload[0], ftms.ResultCode.SUCCESS)
        asyncio.get_running_loop().call_soon(self.client.handle_indication, bytes([0x80, payload[0], result]))


@pytest.fixture(autouse=True)
def no_write_throttle(monkeypatch):
    monkeypatch.setattr(trainer_ble, "MIN_WRITE_INTERVAL_S", 0.0)
    monkeypatch.setattr(trainer_ble, "RETRY_AFTER_S", 0.01)


def make() -> tuple[BridgeState, FtmsTrainer, FakeControlPoint]:
    state = BridgeState()
    trainer = FtmsTrainer(state)
    fake = FakeControlPoint()
    trainer._cp = fake.client
    trainer._has_control = True
    return state, trainer, fake


def test_erg_then_grade_then_erg_off():
    async def scenario():
        state, trainer, fake = make()
        state.set_erg(200)
        await trainer._sync_targets()
        assert fake.written == ["05c800"]
        assert trainer._applied == Target("erg", 200.0)

        state.set_grade(3.0)  # w czasie ERG nachylenie czeka
        await trainer._sync_targets()
        assert fake.written == ["05c800"]

        state.set_erg(None)  # koniec interwału -> wchodzi nachylenie
        await trainer._sync_targets()
        assert fake.written[-1] == ftms.encode_set_indoor_bike_simulation(3.0).hex()

        state.set_grade(None)
        await trainer._sync_targets()  # brak celów -> płaska symulacja
        assert fake.written[-1] == ftms.encode_set_indoor_bike_simulation(0.0).hex()
        await trainer._sync_targets()
        assert len(fake.written) == 3, "płaskiej symulacji nie powtarzamy"

    asyncio.run(scenario())


def test_erg_off_without_grade_releases_resistance():
    async def scenario():
        state, trainer, fake = make()
        state.set_erg(250)
        await trainer._sync_targets()
        state.set_erg(0)
        await trainer._sync_targets()
        assert fake.written == ["05fa00", ftms.encode_set_indoor_bike_simulation(0.0).hex()]

    asyncio.run(scenario())


def test_targets_are_reapplied_after_reconnect():
    async def scenario():
        state, trainer, fake = make()
        state.set_erg(180)
        await trainer._sync_targets()
        await trainer._sync_targets()
        assert fake.written == ["05b400"], "bez zmian nic nie wysyłamy"
        trainer._applied = None  # tak zaczyna się każda nowa sesja BLE
        await trainer._sync_targets()
        assert fake.written == ["05b400", "05b400"]

    asyncio.run(scenario())


def test_power_range_from_trainer_clamps_erg():
    async def scenario():
        state, trainer, fake = make()
        trainer._power_range = ftms.PowerRange(0, 1000, 1)
        state.set_erg(1500)
        await trainer._sync_targets()
        assert fake.written == [ftms.encode_set_target_power(1000).hex()]

    asyncio.run(scenario())


def test_control_not_permitted_requests_control_again():
    async def scenario():
        state, trainer, fake = make()
        fake.results[ftms.ControlOpCode.SET_TARGET_POWER] = ftms.ResultCode.CONTROL_NOT_PERMITTED
        state.set_erg(220)
        await trainer._sync_targets()
        assert not trainer._has_control
        assert trainer._applied is None
        fake.results.clear()
        await asyncio.sleep(0.05)  # ponowienie zaplanowane po RETRY_AFTER_S
        assert trainer._targets_changed.is_set()
        trainer._targets_changed.clear()
        await trainer._sync_targets()
        assert fake.written == ["05dc00", "00", "05dc00"], "Request Control, potem ponownie ERG"
        assert trainer._has_control and trainer._applied == Target("erg", 220.0)

    asyncio.run(scenario())


def test_control_permission_lost_status_triggers_reapply():
    async def scenario():
        state, trainer, fake = make()
        state.set_erg(200)
        await trainer._sync_targets()
        trainer._targets_changed.clear()
        trainer._on_machine_status(None, bytearray(b"\xff"))
        assert trainer._targets_changed.is_set()
        await trainer._sync_targets()
        assert fake.written == ["05c800", "00", "05c800"]

    asyncio.run(scenario())


def test_rejected_value_is_not_retried_forever():
    async def scenario():
        state, trainer, fake = make()
        fake.results[ftms.ControlOpCode.SET_INDOOR_BIKE_SIMULATION] = ftms.ResultCode.INVALID_PARAMETER
        state.set_grade(12.0)
        await trainer._sync_targets()
        await trainer._sync_targets()
        assert len(fake.written) == 1

    asyncio.run(scenario())


def test_bad_bike_data_packets_are_counted_not_raised():
    state, trainer, _ = make()
    trainer._on_bike_data(None, bytearray(b"\x44"))
    trainer._on_bike_data(None, bytearray.fromhex("4400100eb400c800"))
    assert trainer._bad_packets == 1
    assert state.measurement.power_w == 200
