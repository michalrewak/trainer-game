"""Mostek trenażera dla gry Wasteland Rider.

Łączy się z trenażerem (Elite Suito) przez Bluetooth LE w profilu FTMS i wystawia dane
po WebSocket na localhost. Gra (Godot) jest klientem WebSocket i nie wie nic o BLE.
"""

__version__ = "0.1.0"

#: Wersja protokołu WebSocket między mostkiem a grą (patrz protocol.py i README).
PROTOCOL_VERSION = 1

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
