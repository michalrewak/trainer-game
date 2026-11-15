"""ControlPointClient: zapis komendy i czekanie na wskazanie 0x80 – bez Bluetooth."""

import asyncio

import pytest

from wasteland_bridge import ftms
from wasteland_bridge.control import Backoff, ControlPointClient, ControlPointTimeout, Target, plan_target


class FakeTrainer:
    """Udaje Control Point: zapisuje komendy i odpowiada wskazaniem (od razu albo z opóźnieniem)."""

    def __init__(self, result: int = ftms.ResultCode.SUCCESS, *, respond: bool = True, immediate: bool = False):
        self.written: list[bytes] = []
        self.result = result
        self.respond = respond
        self.immediate = immediate
        self.client: ControlPointClient | None = None

    async def write(self, payload: bytes) -> None:
        self.written.append(bytes(payload))
        if not self.respond or self.client is None:
            return
        indication = bytes([0x80, payload[0], self.result])
        if self.immediate:
            # Odpowiedź przychodzi, zanim zapis „się zakończy” (zdarza się na Windows).
            self.client.handle_indication(indication)
        else:
            asyncio.get_running_loop().call_later(0.01, self.client.handle_indication, indication)


def make(trainer: FakeTrainer, timeout_s: float = 0.5) -> ControlPointClient:
    client = ControlPointClient(trainer.write, timeout_s=timeout_s)
    trainer.client = client
    return client


def test_successful_command_returns_response():
    async def scenario():
        trainer = FakeTrainer()
        cp = make(trainer)
        response = await cp.execute(ftms.encode_set_target_power(220))
        assert response.ok
        assert response.request_opcode == ftms.ControlOpCode.SET_TARGET_POWER
        assert trainer.written == [bytes.fromhex("05dc00")]

    asyncio.run(scenario())


def test_indication_before_write_returns_is_matched():
    async def scenario():
        cp = make(FakeTrainer(immediate=True))
        assert (await cp.request_control()).ok

    asyncio.run(scenario())


def test_failure_result_is_returned_not_raised():
    async def scenario():
        cp = make(FakeTrainer(result=ftms.ResultCode.CONTROL_NOT_PERMITTED))
        response = await cp.execute(ftms.encode_set_target_power(200))
        assert not response.ok
        assert response.result == ftms.ResultCode.CONTROL_NOT_PERMITTED

    asyncio.run(scenario())


def test_timeout_raises():
    async def scenario():
        cp = make(FakeTrainer(respond=False), timeout_s=0.05)
        with pytest.raises(ControlPointTimeout):
            await cp.execute(ftms.encode_start_or_resume())

    asyncio.run(scenario())


def test_unrelated_response_is_ignored():
    async def scenario():
        trainer = FakeTrainer(respond=False)
        cp = make(trainer)
        task = asyncio.create_task(cp.execute(ftms.encode_set_target_power(150)))
        await asyncio.sleep(0.01)
        cp.handle_indication(bytes.fromhex("800001"))  # odpowiedź na inną komendę
        await asyncio.sleep(0.01)
        assert not task.done()
        cp.handle_indication(bytes.fromhex("800501"))
        assert (await task).ok

    asyncio.run(scenario())


def test_malformed_indication_does_not_crash():
    cp = ControlPointClient(FakeTrainer().write)
    assert cp.handle_indication(b"\x05\xc8\x00") is None
    assert cp.handle_indication(b"") is None


def test_commands_are_serialized():
    async def scenario():
        trainer = FakeTrainer()
        cp = make(trainer)
        results = await asyncio.gather(
            cp.execute(ftms.encode_request_control()),
            cp.execute(ftms.encode_set_target_power(180)),
            cp.execute(ftms.encode_set_indoor_bike_simulation(2.0)),
        )
        assert all(r.ok for r in results)
        assert [p[0] for p in trainer.written] == [0x00, 0x05, 0x11]

    asyncio.run(scenario())


def test_plan_target_erg_has_priority_over_grade():
    assert plan_target(200, 4.0, None) == Target("erg", 200.0)
    assert plan_target(None, 4.0, None) == Target("sim", 4.0)
    # Nic nie zadano i nic nie było ustawione -> nie wysyłamy nic.
    assert plan_target(None, None, None) is None
    # ERG wyłączony bez nachylenia -> płaska symulacja zdejmuje opór ERG.
    assert plan_target(None, None, Target("erg", 200.0)) == Target("sim", 0.0)
    assert plan_target(1500, None, None, ftms.PowerRange(0, 1000, 1)) == Target("erg", 1000.0)


def test_target_encoding_and_description():
    assert Target("erg", 250.0).encode() == ftms.encode_set_target_power(250)
    assert Target("sim", 3.5).encode() == ftms.encode_set_indoor_bike_simulation(3.5)
    assert Target("erg", 250.0).describe() == "ERG 250 W"
    assert Target("sim", 3.5).describe() == "nachylenie 3,5 %"


def test_backoff_grows_and_resets():
    b = Backoff((1, 2, 5))
    assert [b.next() for _ in range(5)] == [1.0, 2.0, 5.0, 5.0, 5.0]
    b.reset()
    assert b.next() == 1.0
    with pytest.raises(ValueError):
        Backoff(())
