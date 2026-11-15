"""Prawdziwy trenażer przez Bluetooth LE (bleak), profil FTMS 0x1826.

Pętla: szukanie -> łączenie -> subskrypcja Indoor Bike Data / Control Point / Status ->
Request Control + Start -> stosowanie celów ERG/nachylenia z BridgeState. Po zerwaniu łącza
status „disconnected”, przerwa (1 -> 5 s), ponowne szukanie i połączenie; ostatnie ERG
i nachylenie są wtedy wysyłane ponownie.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging

from bleak import BleakClient, BleakScanner
from bleak.backends.characteristic import BleakGATTCharacteristic
from bleak.backends.device import BLEDevice
from bleak.backends.scanner import AdvertisementData
from bleak.exc import BleakError

from . import ftms
from .control import Backoff, ControlPointClient, ControlPointTimeout, Target, plan_target
from .devices import DEFAULT_NAME, DeviceInfo, DeviceSelector
from .protocol import LinkState
from .state import BridgeState

log = logging.getLogger(__name__)

RECONNECT_DELAYS_S = (1.0, 2.0, 3.0, 5.0)
#: Najkrótszy odstęp między kolejnymi komendami ERG/nachylenia (trenażer i tak reaguje wolniej).
MIN_WRITE_INTERVAL_S = 0.25
#: Po nieudanej komendzie spróbujemy ponownie po tylu sekundach.
RETRY_AFTER_S = 2.0
#: Ile czekamy na wyłączenie ERG przy zamykaniu mostka.
RELEASE_TIMEOUT_S = 2.0


class TrainerError(Exception):
    """Urządzenie nie nadaje się do użycia (np. brak usługi FTMS)."""


class FtmsTrainer:
    def __init__(
        self,
        state: BridgeState,
        *,
        address: str | None = None,
        name: str | None = DEFAULT_NAME,
        scan_timeout_s: float = 10.0,
        connect_timeout_s: float = 20.0,
    ) -> None:
        self.state = state
        self.selector = DeviceSelector(address=address, name=name)
        self._scan_timeout_s = scan_timeout_s
        self._connect_timeout_s = connect_timeout_s
        self._backoff = Backoff(RECONNECT_DELAYS_S)
        self._targets_changed = asyncio.Event()
        self._cp: ControlPointClient | None = None
        self._has_control = False
        self._applied: Target | None = None
        self._power_range: ftms.PowerRange | None = None
        self._last_write = 0.0
        self._bad_packets = 0
        self._preferred_address: str | None = None
        self._last_problem = ""
        state.add_target_listener(self._targets_changed.set)

    # --- Pętla główna ---------------------------------------------------------------------

    async def run(self) -> None:
        log.info("Szukam trenażera: %s", self.selector.describe())
        while True:
            connected_before = False
            try:
                self.state.set_link(LinkState.SEARCHING, None)
                found = await self._scan()
                if found is None:
                    self._problem(
                        f"Nie widać trenażera ({self.selector.describe()}). Czy Suito jest włączone "
                        "i nie jest połączone z inną aplikacją?"
                    )
                else:
                    device, info = found
                    connected_before = await self._session(device, info.label)
            except asyncio.CancelledError:
                raise
            except BleakError as exc:
                self._problem(f"Błąd Bluetooth: {exc or type(exc).__name__}")
                self.state.set_link(LinkState.DISCONNECTED, self.state.device)
            except (TrainerError, OSError, TimeoutError) as exc:
                self._problem(f"Połączenie nieudane: {exc or type(exc).__name__}")
                self.state.set_link(LinkState.DISCONNECTED, self.state.device)
            except Exception:
                # Stos BLE potrafi rzucić czymś nietypowym – mostek ma przetrwać cały trening.
                log.exception("Nieoczekiwany błąd łącza z trenażerem – ponawiam")
                self.state.set_link(LinkState.DISCONNECTED, self.state.device)
            if connected_before:
                self._backoff.reset()
            delay = self._backoff.next()
            log.info("Ponowna próba za %.0f s", delay)
            await asyncio.sleep(delay)

    def _problem(self, message: str) -> None:
        """Ten sam problem w kółko logujemy raz (potem tylko w trybie --verbose)."""
        if message != self._last_problem:
            log.warning(message)
            self._last_problem = message
        else:
            log.debug(message)

    # --- Szukanie urządzenia --------------------------------------------------------------

    async def _scan(self) -> tuple[BLEDevice, DeviceInfo] | None:
        seen: dict[str, tuple[BLEDevice, DeviceInfo]] = {}
        done = asyncio.Event()
        preferred = self._preferred_address

        def on_advertisement(device: BLEDevice, adv: AdvertisementData) -> None:
            info = DeviceInfo.create(device.address, adv.local_name or device.name, adv.rssi, adv.service_uuids)
            previous = seen.get(device.address)
            if previous is not None:
                info = previous[1].merged(info)
            seen[device.address] = (device, info)
            if self.selector.is_definite_match(info, preferred):
                done.set()

        async with BleakScanner(on_advertisement):
            with contextlib.suppress(TimeoutError):
                await asyncio.wait_for(done.wait(), self._scan_timeout_s)
        choice = self.selector.choose((info for _, info in seen.values()), preferred_address=preferred)
        if choice is None:
            return None
        info, reason = choice
        log.info("Wybrano %s [%s] – %s", info.label, info.address, reason)
        return seen[info.address][0], info

    # --- Sesja z połączonym trenażerem ------------------------------------------------------

    async def _session(self, device: BLEDevice, label: str) -> bool:
        """Zwraca True, jeśli doszło do pełnego połączenia (wtedy przerwa liczy się od nowa)."""
        disconnected = asyncio.Event()
        self.state.set_link(LinkState.CONNECTING, label)
        log.info("Łączę z %s…", label)
        client = BleakClient(
            device,
            disconnected_callback=lambda _client: disconnected.set(),
            timeout=self._connect_timeout_s,
        )
        await client.connect()
        connected = False
        try:
            await self._setup(client)
            self._preferred_address = device.address
            self._applied = None
            self.state.set_link(LinkState.CONNECTED, label)
            self._last_problem = ""
            connected = True
            log.info("Połączono z %s", label)
            self._targets_changed.set()  # (ponownie) zastosuj bieżące ERG / nachylenie
            while not disconnected.is_set():
                await self._wait_for_work(disconnected)
                if disconnected.is_set():
                    break
                self._targets_changed.clear()
                await self._sync_targets()
            log.warning("Trenażer %s rozłączony", label)
            self.state.set_link(LinkState.DISCONNECTED, label)
            return True
        finally:
            if client.is_connected:
                with contextlib.suppress(Exception):
                    await asyncio.wait_for(self._release(), RELEASE_TIMEOUT_S)
                with contextlib.suppress(Exception):
                    await asyncio.wait_for(client.disconnect(), 5.0)
            self._cp = None
            self._has_control = False
            if not connected:
                self.state.set_link(LinkState.DISCONNECTED, label)

    async def _wait_for_work(self, disconnected: asyncio.Event) -> None:
        waiters = [
            asyncio.ensure_future(self._targets_changed.wait()),
            asyncio.ensure_future(disconnected.wait()),
        ]
        try:
            await asyncio.wait(waiters, return_when=asyncio.FIRST_COMPLETED)
        finally:
            for waiter in waiters:
                waiter.cancel()

    async def _setup(self, client: BleakClient) -> None:
        service = client.services.get_service(ftms.FTMS_SERVICE_UUID)
        if service is None:
            raise TrainerError("urządzenie nie ma usługi FTMS (0x1826)")

        feature = service.get_characteristic(ftms.FEATURE_UUID)
        if feature is not None:
            try:
                features = ftms.parse_features(await client.read_gatt_char(feature))
                log.info("Możliwości trenażera: %s", features.describe())
            except (BleakError, ftms.FtmsParseError, OSError) as exc:
                log.debug("Nie odczytano Fitness Machine Feature: %s", exc)

        self._power_range = None
        power_range = service.get_characteristic(ftms.SUPPORTED_POWER_RANGE_UUID)
        if power_range is not None:
            try:
                self._power_range = ftms.parse_supported_power_range(await client.read_gatt_char(power_range))
                log.info(
                    "Zakres ERG trenażera: %d–%d W", self._power_range.minimum_w, self._power_range.maximum_w
                )
            except (BleakError, ftms.FtmsParseError, OSError) as exc:
                log.debug("Nie odczytano Supported Power Range: %s", exc)

        bike_data = service.get_characteristic(ftms.INDOOR_BIKE_DATA_UUID)
        if bike_data is None:
            raise TrainerError("brak charakterystyki Indoor Bike Data (0x2AD2)")
        await client.start_notify(bike_data, self._on_bike_data)

        status = service.get_characteristic(ftms.MACHINE_STATUS_UUID)
        if status is not None:
            try:
                await client.start_notify(status, self._on_machine_status)
            except (BleakError, OSError) as exc:
                log.debug("Bez subskrypcji Fitness Machine Status: %s", exc)

        control_point = service.get_characteristic(ftms.CONTROL_POINT_UUID)
        if control_point is None:
            log.warning("Trenażer nie ma FTMS Control Point – tylko odczyt, bez ERG i nachylenia")
            return
        cp = ControlPointClient(lambda payload: client.write_gatt_char(control_point, payload, response=True))
        # Wskazania trzeba włączyć PRZED pierwszym zapisem, inaczej trenażer odrzuci komendę.
        await client.start_notify(control_point, lambda _char, data: cp.handle_indication(data))
        self._cp = cp
        if await self._take_control():
            try:
                response = await cp.start_or_resume()
                log.debug("Start/Resume: %s", response.describe())
            except (ControlPointTimeout, BleakError, OSError) as exc:
                log.debug("Start/Resume bez odpowiedzi: %s", exc)

    async def _take_control(self) -> bool:
        if self._cp is None:
            return False
        try:
            response = await self._cp.request_control()
        except (ControlPointTimeout, BleakError, OSError) as exc:
            log.warning("Request Control nieudane: %s", exc)
            self._has_control = False
            return False
        self._has_control = response.ok
        if response.ok:
            log.info("Mostek steruje oporem trenażera")
        else:
            log.warning(
                "Trenażer odmówił sterowania (%s). Zamknij Zwift / MyWhoosh / aplikację Elite.",
                response.describe(),
            )
        return self._has_control

    # --- Cele ERG / nachylenie ----------------------------------------------------------------

    def _desired(self) -> Target | None:
        return plan_target(self.state.erg_watts, self.state.grade_percent, self._applied, self._power_range)

    async def _sync_targets(self) -> None:
        if self._cp is None:
            return
        target = self._desired()
        if target is None or target == self._applied:
            return
        if not self._has_control and not await self._take_control():
            self._retry_later()
            return
        loop = asyncio.get_running_loop()
        wait = self._last_write + MIN_WRITE_INTERVAL_S - loop.time()
        if wait > 0:
            await asyncio.sleep(wait)
            target = self._desired()  # gra mogła w międzyczasie zmienić cel
            if target is None or target == self._applied:
                return
        self._last_write = loop.time()
        try:
            response = await self._cp.execute(target.encode())
        except (ControlPointTimeout, BleakError, OSError) as exc:
            log.warning("Nie ustawiono %s: %s", target.describe(), exc)
            self._retry_later()
            return
        if response.ok:
            self._applied = target
            log.info("Trenażer: %s", target.describe())
        elif response.result == ftms.ResultCode.CONTROL_NOT_PERMITTED:
            self._has_control = False
            self._retry_later()
        else:
            # Nie ponawiamy w kółko wartości, której trenażer nie przyjmuje.
            log.warning("Trenażer odrzucił %s: %s", target.describe(), response.describe())
            self._applied = target

    def _retry_later(self) -> None:
        asyncio.get_running_loop().call_later(RETRY_AFTER_S, self._targets_changed.set)

    async def _release(self) -> None:
        """Przy zamykaniu mostka zdejmij ERG/nachylenie (płaska symulacja), żeby nie zostawić oporu."""
        if self._cp is None or not self._has_control or self._applied is None:
            return
        response = await self._cp.execute(Target("sim", 0.0).encode())
        log.info("Opór zwolniony przed rozłączeniem: %s", response.describe())

    # --- Powiadomienia BLE ----------------------------------------------------------------------

    def _on_bike_data(self, _char: BleakGATTCharacteristic, data: bytearray) -> None:
        try:
            parsed = ftms.parse_indoor_bike_data(data)
        except ftms.FtmsParseError as exc:
            self._bad_packets += 1
            if self._bad_packets <= 3 or self._bad_packets % 100 == 0:
                log.warning("Błędny pakiet Indoor Bike Data (%d.): %s", self._bad_packets, exc)
            return
        self.state.apply_bike_data(parsed)

    def _on_machine_status(self, _char: BleakGATTCharacteristic, data: bytearray) -> None:
        try:
            status = ftms.parse_machine_status(data)
        except ftms.FtmsParseError as exc:
            log.debug("Niezrozumiały Fitness Machine Status: %s", exc)
            return
        if status.control_lost:
            log.warning("Trenażer odebrał mostkowi sterowanie (inna aplikacja?) – próbuję odzyskać")
            self._has_control = False
            self._applied = None
            self._targets_changed.set()
        elif status.opcode == ftms.MachineStatusOpCode.TARGET_POWER_CHANGED:
            log.debug("Trenażer potwierdza cel mocy: %s W", status.target_power_w)
        elif status.opcode == ftms.MachineStatusOpCode.INDOOR_BIKE_SIMULATION_CHANGED:
            log.debug("Trenażer potwierdza nachylenie: %s %%", status.grade_percent)
        else:
            log.info("Status trenażera: %s", status.name)
