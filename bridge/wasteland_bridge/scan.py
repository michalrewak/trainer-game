"""Skaner BLE: urządzenia w pobliżu (nazwa, adres, RSSI) z zaznaczeniem trenażerów FTMS (0x1826).

Uruchamiany przez bridge/scan.py albo: python -m wasteland_bridge.scan [--timeout 8] [--ftms]
"""

from __future__ import annotations

import argparse
import asyncio
import sys

from rich.console import Console
from rich.table import Table

from .devices import DeviceInfo, sort_for_display


def device_rows(devices: list[DeviceInfo]) -> list[tuple[str, str, str, str]]:
    """(nazwa, adres, RSSI, FTMS) – posortowane: trenażery FTMS na górze, potem wg sygnału."""
    rows = []
    for d in sort_for_display(devices):
        rssi = f"{d.rssi} dBm" if d.rssi is not None else "?"
        rows.append((d.name or "(bez nazwy)", d.address, rssi, "TAK – trenażer" if d.has_ftms else ""))
    return rows


async def scan(timeout_s: float) -> list[DeviceInfo]:
    from bleak import BleakScanner

    found = await BleakScanner.discover(timeout=timeout_s, return_adv=True)
    return [
        DeviceInfo.create(device.address, adv.local_name or device.name, adv.rssi, adv.service_uuids)
        for device, adv in found.values()
    ]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="scan.py", description="Lista urządzeń Bluetooth LE w pobliżu.")
    parser.add_argument("--timeout", type=float, default=8.0, metavar="S", help="czas skanowania (domyślnie 8 s)")
    parser.add_argument("--ftms", action="store_true", help="pokaż tylko trenażery FTMS (0x1826)")
    args = parser.parse_args(argv)
    console = Console()
    console.print(f"Skanuję Bluetooth LE przez {args.timeout:g} s… (trenażer musi być wybudzony – zakręć korbą)")
    try:
        from bleak.exc import BleakError

        devices = asyncio.run(scan(args.timeout))
    except BleakError as exc:
        console.print(f"[bold red]Bluetooth niedostępny:[/] {exc}. Włącz Bluetooth i spróbuj ponownie.")
        return 1
    except OSError as exc:
        console.print(f"[bold red]Błąd Bluetooth:[/] {exc}")
        return 1
    if args.ftms:
        devices = [d for d in devices if d.has_ftms]
    table = Table(title="Urządzenia Bluetooth LE")
    for column in ("Nazwa", "Adres", "RSSI", "FTMS 0x1826"):
        table.add_column(column)
    for row in device_rows(devices):
        table.add_row(*row, style="bold green" if row[3] else None)
    console.print(table)
    trainers = [d for d in devices if d.has_ftms]
    console.print(f"Znaleziono: {len(devices)}, w tym trenażerów FTMS: {len(trainers)}.")
    if trainers:
        best = sort_for_display(trainers)[0]
        console.print(f"Połączenie z konkretnym trenażerem: python -m wasteland_bridge --address {best.address}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
