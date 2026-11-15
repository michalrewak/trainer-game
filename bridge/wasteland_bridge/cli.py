"""Uruchamianie mostka: python -m wasteland_bridge [--sim] [--name SUITO | --address ADRES] ..."""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import logging
import sys

from rich.console import Console
from rich.logging import RichHandler

from . import DEFAULT_HOST, DEFAULT_PORT, PROTOCOL_VERSION, __version__
from .devices import DEFAULT_NAME
from .server import BridgeServer
from .state import BridgeState
from .trainer_sim import SimTrainer
from .ui import LiveView, PlainReporter

log = logging.getLogger("wasteland_bridge")

LOCAL_HOSTS = {"127.0.0.1", "localhost", "::1"}


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="python -m wasteland_bridge",
        description="Mostek trenażera (Bluetooth FTMS, np. Elite Suito) <-> WebSocket dla gry Wasteland Rider.",
    )
    p.add_argument("--sim", action="store_true", help="symulowany trenażer – działa bez sprzętu i bez Bluetooth")
    p.add_argument(
        "--address",
        help="adres BLE trenażera (Windows: AA:BB:CC:DD:EE:FF, macOS: UUID); listę daje scan.py",
    )
    p.add_argument(
        "--name",
        default=DEFAULT_NAME,
        help=f'fragment nazwy trenażera (domyślnie "{DEFAULT_NAME}"); --name "" = pierwszy trenażer FTMS',
    )
    p.add_argument("--host", default=DEFAULT_HOST, help=f"adres serwera WebSocket (domyślnie {DEFAULT_HOST})")
    p.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"port serwera WebSocket (domyślnie {DEFAULT_PORT})")
    p.add_argument("--scan-timeout", type=float, default=10.0, metavar="S", help="czas jednego skanowania BLE")
    p.add_argument("--no-ui", action="store_true", help="bez podglądu na żywo – zwykłe logi (np. praca w tle)")
    p.add_argument("-v", "--verbose", action="store_true", help="szczegółowe logi (także bleak i websockets)")
    p.add_argument("--version", action="version", version=f"%(prog)s {__version__} (protokół v{PROTOCOL_VERSION})")
    sim = p.add_argument_group("symulator (--sim)")
    sim.add_argument("--sim-power", type=float, default=180.0, metavar="W", help="moc bazowa bez ERG (domyślnie 180)")
    sim.add_argument("--sim-seed", type=int, default=None, metavar="N", help="stałe ziarno losowania")
    sim.add_argument(
        "--sim-dropout-every",
        type=float,
        default=0.0,
        metavar="S",
        help="co S sekund udawaj zerwanie łącza z trenażerem (test pauzy w grze); 0 = nigdy",
    )
    sim.add_argument("--sim-dropout-duration", type=float, default=6.0, metavar="S", help="długość udawanej przerwy")
    return p


def configure_logging(verbose: bool, console: Console | None) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    handler: logging.Handler
    if console is not None:
        handler = RichHandler(console=console, show_path=False, markup=False, log_time_format="%H:%M:%S")
        handler.setFormatter(logging.Formatter("%(message)s"))
    else:
        handler = logging.StreamHandler(sys.stderr)
        handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)-7s %(message)s", "%H:%M:%S"))
    logging.basicConfig(level=level, handlers=[handler], force=True)
    for noisy in ("websockets", "bleak"):
        logging.getLogger(noisy).setLevel(logging.DEBUG if verbose else logging.WARNING)


def _prepare_streams() -> None:
    """Przekierowane wyjście w Windows ma kodowanie cp125x – polskie znaki nie mogą wywrócić mostka."""
    for stream in (sys.stdout, sys.stderr):
        if stream is not None and hasattr(stream, "reconfigure") and not stream.isatty():
            with contextlib.suppress(Exception):
                stream.reconfigure(encoding="utf-8", errors="replace")


async def run(args: argparse.Namespace, console: Console | None) -> int:
    state = BridgeState()
    server = BridgeServer(state, host=args.host, port=args.port)
    try:
        await server.start()
    except OSError as exc:
        log.error(
            "Nie mogę otworzyć %s: %s. Port zajmuje już mostek w innym oknie albo inny program "
            "(Windows: netstat -ano | findstr :%d). Użyj innego portu: --port 8766 "
            "(i ustaw ten sam adres w grze).",
            server.url,
            exc,
            args.port,
        )
        return 2
    if args.host not in LOCAL_HOSTS:
        log.warning("Serwer nasłuchuje poza localhost (%s) – komendy nie są uwierzytelniane!", args.host)

    if args.sim:
        trainer = SimTrainer(
            state,
            seed=args.sim_seed,
            base_power_w=args.sim_power,
            dropout_every_s=args.sim_dropout_every,
            dropout_duration_s=args.sim_dropout_duration,
        )
    else:
        # bleak ładujemy dopiero tutaj – tryb --sim działa nawet bez stosu Bluetooth.
        from .trainer_ble import FtmsTrainer

        trainer = FtmsTrainer(state, address=args.address, name=args.name, scan_timeout_s=args.scan_timeout)

    view = LiveView(state, console, server.url) if console is not None else PlainReporter(state)
    async with asyncio.TaskGroup() as tasks:
        tasks.create_task(server.run())
        tasks.create_task(trainer.run())
        tasks.create_task(view.run())
    return 0


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    _prepare_streams()
    console = Console() if not args.no_ui and sys.stdout.isatty() else None
    configure_logging(args.verbose, console)
    log.info("Mostek Wasteland Rider %s (protokół v%d)%s", __version__, PROTOCOL_VERSION, " – SYMULATOR" if args.sim else "")
    try:
        return asyncio.run(run(args, console))
    except KeyboardInterrupt:
        log.info("Zamknięto (Ctrl+C)")
        return 0
