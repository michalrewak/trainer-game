"""Serwer WebSocket dla gry (domyślnie ws://127.0.0.1:8765), protokół v1 – patrz protocol.py.

Co 250 ms rozsyła pomiar do wszystkich klientów, status wysyła po połączeniu i przy każdej
zmianie, komendy erg/slope zapisuje jako cele w BridgeState (trenażer stosuje je sam).
Połączenia z przeglądarek (z nagłówkiem Origin) są odrzucane – strona WWW nie może
sterować oporem trenażera.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging

from websockets.asyncio.server import Server, ServerConnection, broadcast, serve
from websockets.exceptions import ConnectionClosed

from . import DEFAULT_HOST, DEFAULT_PORT
from .protocol import (
    ErgCommand,
    PingCommand,
    ProtocolError,
    SlopeCommand,
    error_message,
    parse_command,
    pong_message,
)
from .state import BridgeState

log = logging.getLogger(__name__)

DATA_INTERVAL_S = 0.25
#: Większa ramka rozłącza klienta (komendy mają po kilkadziesiąt bajtów).
MAX_FRAME_BYTES = 64 * 1024


class BridgeServer:
    def __init__(
        self,
        state: BridgeState,
        *,
        host: str = DEFAULT_HOST,
        port: int = DEFAULT_PORT,
        data_interval_s: float = DATA_INTERVAL_S,
    ) -> None:
        self.state = state
        self.host = host
        self.port = port
        self.data_interval_s = data_interval_s
        self.frames_sent = 0
        self._server: Server | None = None
        state.add_status_listener(self._broadcast_status)

    @property
    def url(self) -> str:
        host = f"[{self.host}]" if ":" in self.host else self.host
        return f"ws://{host}:{self.port}"

    # --- Komendy od gry (bez sieci – testowalne) -------------------------------------------

    def handle_text(self, raw: str | bytes) -> str | None:
        """Obsługuje jedną ramkę od klienta. Zwraca odpowiedź dla tego klienta albo None."""
        try:
            command = parse_command(raw)
        except ProtocolError as exc:
            log.info("Odrzucona komenda od gry: %s", exc)
            return error_message(str(exc))
        if isinstance(command, PingCommand):
            return pong_message()
        if isinstance(command, ErgCommand):
            if self.state.set_erg(command.watts):
                log.info("Gra: ERG %s", f"{command.watts} W" if command.watts else "wyłączony")
            return None
        if isinstance(command, SlopeCommand):
            if self.state.set_grade(command.grade_percent):
                log.info("Gra: nachylenie %.1f %%", command.grade_percent)
            return None
        return error_message("nieobsługiwana komenda")

    # --- Sieć ------------------------------------------------------------------------------

    async def start(self) -> None:
        """Otwiera gniazdo. Rzuca OSError, gdy port jest zajęty (np. drugi mostek)."""
        self._server = await serve(
            self._handler,
            self.host,
            self.port,
            origins=[None],
            compression=None,
            max_size=MAX_FRAME_BYTES,
            ping_interval=20,
            ping_timeout=20,
            close_timeout=2,
        )
        sockets = self._server.sockets
        if sockets:
            self.port = sockets[0].getsockname()[1]
        log.info("Serwer WebSocket dla gry: %s", self.url)

    async def run(self) -> None:
        if self._server is None:
            await self.start()
        assert self._server is not None
        try:
            await self._data_loop()
        finally:
            self._server.close()
            with contextlib.suppress(Exception):
                await asyncio.wait_for(self._server.wait_closed(), 3.0)

    async def _data_loop(self) -> None:
        loop = asyncio.get_running_loop()
        next_tick = loop.time()
        while True:
            next_tick += self.data_interval_s
            delay = next_tick - loop.time()
            if delay < -self.data_interval_s:
                # Zaległość (np. uśpiony laptop) – nie nadrabiamy serią starych ramek.
                next_tick = loop.time()
                delay = 0.0
            await asyncio.sleep(max(0.0, delay))
            frame = self.state.data_frame()
            if frame is None or self._server is None:
                continue
            connections = self._server.connections
            if connections:
                broadcast(connections, frame)
                self.frames_sent += 1

    def _broadcast_status(self) -> None:
        if self._server is None:
            return
        connections = self._server.connections
        if connections:
            broadcast(connections, self.state.status_frame())

    async def _handler(self, ws: ServerConnection) -> None:
        peer = _peer_name(ws)
        self.state.clients += 1
        log.info("Gra połączona (%s), klientów: %d", peer, self.state.clients)
        try:
            await ws.send(self.state.status_frame())
            async for message in ws:
                reply = self.handle_text(message)
                if reply is not None:
                    await ws.send(reply)
        except ConnectionClosed:
            pass
        finally:
            self.state.clients -= 1
            log.info("Gra rozłączona (%s), klientów: %d", peer, self.state.clients)


def _peer_name(ws: ServerConnection) -> str:
    address = ws.remote_address
    if isinstance(address, tuple) and len(address) >= 2:
        return f"{address[0]}:{address[1]}"
    return str(address)
