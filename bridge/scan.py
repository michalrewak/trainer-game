"""Lista urządzeń BLE w pobliżu (nazwa, adres, RSSI, czy to trenażer FTMS 0x1826).

Windows:  .venv\\Scripts\\python scan.py [--timeout 8] [--ftms]
macOS:    .venv/bin/python scan.py [--timeout 8] [--ftms]
"""

import sys

from wasteland_bridge.scan import main

if __name__ == "__main__":
    sys.exit(main())
