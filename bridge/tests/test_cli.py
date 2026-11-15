"""Uruchamianie mostka: opcje, start i zamknięcie (to samo, co robi Ctrl+C), zajęty port."""

import asyncio
import socket

import pytest

from wasteland_bridge import DEFAULT_PORT
from wasteland_bridge.cli import build_parser, run


def test_parser_defaults():
    args = build_parser().parse_args([])
    assert not args.sim
    assert args.name == "SUITO"
    assert args.address is None
    assert args.host == "127.0.0.1"
    assert args.port == DEFAULT_PORT
    assert args.sim_dropout_every == 0.0


def test_parser_sim_options():
    args = build_parser().parse_args(
        ["--sim", "--port", "8766", "--sim-power", "220", "--sim-seed", "5", "--sim-dropout-every", "30", "--no-ui"]
    )
    assert args.sim and args.no_ui
    assert (args.port, args.sim_power, args.sim_seed, args.sim_dropout_every) == (8766, 220.0, 5, 30.0)


def test_sim_bridge_starts_and_stops_cleanly_when_cancelled():
    """asyncio.run anuluje główne zadanie po Ctrl+C – mostek ma się wtedy zamknąć bez zawieszenia."""

    async def scenario():
        args = build_parser().parse_args(["--sim", "--port", "0", "--no-ui"])
        task = asyncio.create_task(run(args, None))
        await asyncio.sleep(0.4)
        assert not task.done(), "mostek działa, dopóki go nie zamkniemy"
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await asyncio.wait_for(task, 5.0)

    asyncio.run(scenario())


def test_busy_port_returns_exit_code_2():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as blocker:
        blocker.bind(("127.0.0.1", 0))
        blocker.listen()
        port = blocker.getsockname()[1]
        args = build_parser().parse_args(["--sim", "--port", str(port), "--no-ui"])
        assert asyncio.run(asyncio.wait_for(run(args, None), 5.0)) == 2
