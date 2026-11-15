"""Wybór urządzenia BLE spośród zeskanowanych – czysta logika (bez bleak), używana przez
mostek i przez skaner (scan.py).

Kolejność: --address (dokładnie to urządzenie) > ostatnio używany trenażer (po rozłączeniu)
> nazwa zawiera --name (domyślnie "SUITO", bez rozróżniania wielkości liter)
> pierwszy/najbliższy trenażer ogłaszający usługę FTMS 0x1826.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

from .ftms import FTMS_SERVICE_UUID

DEFAULT_NAME = "SUITO"
_BASE_UUID_SUFFIX = "-0000-1000-8000-00805f9b34fb"


def normalize_uuid(value: str) -> str:
    """'1826', '0x1826' i pełny zapis -> pełny UUID małymi literami."""
    text = value.strip().lower()
    if text.startswith("0x"):
        text = text[2:]
    if len(text) == 4:
        return f"0000{text}{_BASE_UUID_SUFFIX}"
    if len(text) == 8:
        return f"{text}{_BASE_UUID_SUFFIX}"
    return text


@dataclass(frozen=True, slots=True)
class DeviceInfo:
    address: str
    name: str | None
    rssi: int | None
    service_uuids: tuple[str, ...] = ()

    @staticmethod
    def create(address: str, name: str | None, rssi: int | None, service_uuids: Iterable[str]) -> DeviceInfo:
        return DeviceInfo(address, name or None, rssi, tuple(sorted({normalize_uuid(u) for u in service_uuids})))

    @property
    def has_ftms(self) -> bool:
        return FTMS_SERVICE_UUID in self.service_uuids

    @property
    def label(self) -> str:
        return self.name or self.address

    def merged(self, newer: DeviceInfo) -> DeviceInfo:
        """Łączy kolejne ogłoszenia: nazwa bywa tylko w scan response, UUID-y w samym ogłoszeniu."""
        return DeviceInfo(
            self.address,
            newer.name or self.name,
            newer.rssi if newer.rssi is not None else self.rssi,
            tuple(sorted(set(self.service_uuids) | set(newer.service_uuids))),
        )


def _rssi_key(device: DeviceInfo) -> int:
    return device.rssi if device.rssi is not None else -999


def sort_for_display(devices: Iterable[DeviceInfo]) -> list[DeviceInfo]:
    """Trenażery FTMS na górze, dalej od najsilniejszego sygnału."""
    return sorted(devices, key=lambda d: (not d.has_ftms, -_rssi_key(d), d.label.lower()))


class DeviceSelector:
    def __init__(self, *, address: str | None = None, name: str | None = DEFAULT_NAME) -> None:
        self.address = address.strip().lower() if address and address.strip() else None
        cleaned = (name or "").strip().lower()
        self.name = cleaned or None

    def describe(self) -> str:
        if self.address:
            return f"adres {self.address}"
        if self.name:
            return f"nazwa zawiera \"{self.name.upper()}\" albo dowolny trenażer FTMS"
        return "dowolny trenażer FTMS (0x1826)"

    def _name_matches(self, device: DeviceInfo) -> bool:
        return self.name is not None and self.name in (device.name or "").lower()

    def is_definite_match(self, device: DeviceInfo, preferred_address: str | None = None) -> bool:
        """True = można od razu przerwać skanowanie i łączyć się z tym urządzeniem."""
        address = device.address.lower()
        if self.address:
            return address == self.address
        if preferred_address and address == preferred_address.lower():
            return True
        if self.name:
            return self._name_matches(device)
        return device.has_ftms

    def choose(
        self, devices: Iterable[DeviceInfo], *, preferred_address: str | None = None
    ) -> tuple[DeviceInfo, str] | None:
        """Wybiera urządzenie po zakończonym skanowaniu. Zwraca (urządzenie, powód) albo None."""
        candidates = list(devices)
        if self.address:
            for d in candidates:
                if d.address.lower() == self.address:
                    return d, "adres podany w --address"
            return None
        if preferred_address:
            for d in candidates:
                if d.address.lower() == preferred_address.lower():
                    return d, "ostatnio używany trenażer"
        if self.name:
            named = [d for d in candidates if self._name_matches(d)]
            if named:
                best = max(named, key=lambda d: (d.has_ftms, _rssi_key(d)))
                return best, f"nazwa zawiera \"{self.name.upper()}\""
        with_ftms = [d for d in candidates if d.has_ftms]
        if with_ftms:
            best = max(with_ftms, key=_rssi_key)
            reason = "trenażer FTMS (0x1826)"
            if self.name:
                reason += f" – brak urządzenia z \"{self.name.upper()}\" w nazwie"
            return best, reason
        return None
