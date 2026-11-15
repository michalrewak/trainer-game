"""Serwer WebSocket: obsługa komend bez sieci oraz prawdziwe połączenie na localhost (port losowy)."""

import asyncio
import json

import pytest
from websockets.asyncio.client import connect
from websockets.exceptions import InvalidStatus

from wasteland_bridge.protocol import LinkState
from wasteland_bridge.server import BridgeServer
from wasteland_bridge.state import BridgeState
from wasteland_bridge.trainer_sim import SimTrainer


def test_handle_text_ping_erg_slope_and_errors():
    state = BridgeState()
    server = BridgeServer(state)
    statuses: list[str] = []
    state.add_status_listener(lambda: statuses.append(state.status_frame()))

    assert json.loads(server.handle_text('{"cmd":"ping"}')) == {"type": "pong"}
    assert server.handle_text('{"cmd":"erg","watts":215}') is None
    assert state.erg_watts == 215
    assert server.handle_text('{"cmd":"slope","grade":3.5}') is None
    assert state.grade_percent == 3.5
    assert server.handle_text('{"cmd":"erg","watts":0}') is None
    assert state.erg_watts is None
    assert len(statuses) == 3, "każda zmiana celu rozsyła status"

    for bad in ("nie json", '{"cmd":"erg","watts":"dużo"}', '{"cmd":"turbo"}', b"\x00\x01"):
        reply = json.loads(server.handle_text(bad))
        assert reply["type"] == "error"
        assert reply["message"]
    assert state.erg_watts is None, "błędne komendy nic nie zmieniają"


async def _recv_until(ws, predicate, timeout=3.0):
    async def loop():
        while True:
            msg = json.loads(await ws.recv())
            if predicate(msg):
                return msg

    return await asyncio.wait_for(loop(), timeout)


def test_websocket_roundtrip_with_simulated_trainer():
    async def scenario():
        state = BridgeState()
        server = BridgeServer(state, host="127.0.0.1", port=0, data_interval_s=0.05)
        await server.start()
        assert server.port != 0
        tasks = [
            asyncio.create_task(server.run()),
            asyncio.create_task(SimTrainer(state, seed=1, rate_hz=40.0).run()),
        ]
        try:
            async with connect(server.url) as ws:
                first = json.loads(await asyncio.wait_for(ws.recv(), 3.0))
                assert first["type"] == "status"
                assert set(first) == {"type", "state", "device", "erg", "grade"}

                data = await _recv_until(ws, lambda m: m["type"] == "data")
                assert set(data) == {"type", "power", "cadence", "speed", "timestamp"}
                assert data["power"] > 0 and 80 <= data["cadence"] <= 95
                assert state.clients == 1

                await ws.send('{"cmd":"erg","watts":250}')
                status = await _recv_until(ws, lambda m: m["type"] == "status" and m["erg"] == 250)
                assert status["state"] == "sim"

                await ws.send('{"cmd":"slope","grade":4.2}')
                await _recv_until(ws, lambda m: m["type"] == "status" and m["grade"] == 4.2)

                await ws.send('{"cmd":"ping"}')
                await _recv_until(ws, lambda m: m["type"] == "pong")

                await ws.send("to nie jest JSON")
                error = await _recv_until(ws, lambda m: m["type"] == "error")
                assert "JSON" in error["message"]

                await ws.send(b"\x01\x02")
                await _recv_until(ws, lambda m: m["type"] == "error")

                # Po błędnych ramkach połączenie dalej działa.
                await ws.send('{"cmd":"ping"}')
                await _recv_until(ws, lambda m: m["type"] == "pong")

                # Zerwanie łącza z trenażerem: status „disconnected”, dane przestają płynąć.
                state.set_link(LinkState.DISCONNECTED, "SIM SUITO")
                await _recv_until(ws, lambda m: m["type"] == "status" and m["state"] == "disconnected")
        finally:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
        assert state.clients == 0

    asyncio.run(scenario())


def test_browser_origin_is_rejected():
    async def scenario():
        state = BridgeState()
        server = BridgeServer(state, host="127.0.0.1", port=0)
        await server.start()
        task = asyncio.create_task(server.run())
        try:
            with pytest.raises(InvalidStatus) as info:
                async with connect(server.url, origin="http://example.com"):
                    pass
            assert info.value.response.status_code == 403
        finally:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)

    asyncio.run(scenario())


def test_port_in_use_raises_oserror():
    async def scenario():
        first = BridgeServer(BridgeState(), host="127.0.0.1", port=0)
        await first.start()
        task = asyncio.create_task(first.run())
        try:
            second = BridgeServer(BridgeState(), host="127.0.0.1", port=first.port)
            with pytest.raises(OSError):
                await second.start()
        finally:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)

    asyncio.run(scenario())
