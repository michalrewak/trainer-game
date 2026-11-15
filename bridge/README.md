# Mostek trenażera – Elite Suito ⇄ Wasteland Rider

Mały program w Pythonie 3.12, który łączy się z trenażerem przez **Bluetooth LE (profil FTMS)**,
czyta moc, kadencję i prędkość, steruje oporem (ERG i nachylenie) i wystawia to wszystko grze
po **WebSocket na `ws://127.0.0.1:8765`**. Gra nie zna Bluetooth – rozmawia tylko z mostkiem.

```
Elite Suito ──BLE FTMS──▶ mostek (ten katalog) ──WebSocket 127.0.0.1:8765──▶ gra (Godot)
Pomiar mocy w rowerze + Fenix 7 Pro ──▶ Garmin Edge 840 ──▶ Garmin Connect   (niezależnie od gry)
```

Tryb `--sim` udaje trenażer bez żadnego sprzętu – tym samym protokołem, więc grę można testować
przy biurku.

## Instalacja

### Windows

```powershell
powershell -ExecutionPolicy Bypass -File bridge\setup.ps1
```

Skrypt tworzy `bridge\.venv` i instaluje przypięte wersje zależności (`requirements.txt`:
bleak, websockets, rich; `requirements-dev.txt`: dodatkowo pytest). Pythona 3.12+ szuka po kolei:
przenośny w `.tools\python-3.12` (wspólny folder repo, poza gitem), `python` z PATH, launcher `py`.
Jeśli żadnego nie ma, pobiera oficjalny pakiet NuGet „python” 3.12.10 (Python Software
Foundation), sprawdza sumę SHA-512 z metadanych NuGet i rozpakowuje go do `.tools\python-3.12`.
Niczego nie instaluje w systemie i nie zmienia PATH.

Przełączniki: `-NoDev` (bez pytest), `-Recreate` (usuń `.venv` i zbuduj od nowa),
`-Portable` (użyj tylko przenośnego Pythona, w razie potrzeby pobierz).

### macOS

```bash
brew install python@3.12        # albo instalator z python.org
cd bridge
python3.12 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
```

Przy pierwszym skanowaniu macOS zapyta o dostęp do Bluetooth dla Terminala (albo iTerm) –
trzeba się zgodzić (Ustawienia systemowe → Prywatność i ochrona → Bluetooth).

## Uruchomienie

Wszystkie polecenia z katalogu `bridge`. Na macOS zamiast `.\.venv\Scripts\python` pisz
`.venv/bin/python`.

```powershell
.\.venv\Scripts\python -m wasteland_bridge --sim     # symulator, bez sprzętu
.\.venv\Scripts\python -m wasteland_bridge           # prawdziwe Suito
```

Mostek pokazuje podgląd na żywo: stan łącza, moc, kadencję, prędkość, zadane ERG i nachylenie
oraz liczbę połączonych gier. **Ctrl+C** kończy pracę – wcześniej mostek zdejmuje opór ERG.

### Prawdziwe Suito krok po kroku

1. Podłącz Suito do prądu i zakręć korbą – trenażer się wybudzi i zacznie się ogłaszać.
2. Zamknij wszystko, co może się z nim łączyć: Zwift, MyWhoosh, Elite myETraining, aplikacje
   na telefonie i tablecie. FTMS pozwala sterować oporem tylko jednej aplikacji naraz.
3. Uruchom `.\.venv\Scripts\python -m wasteland_bridge`. Domyślnie mostek szuka urządzenia
   z „SUITO” w nazwie, a jeśli go nie widzi – pierwszego trenażera ogłaszającego FTMS (0x1826).
4. Stan zmieni się na **POŁĄCZONY**, a moc zacznie się zmieniać, gdy pedałujesz.
5. Uruchom grę i wybierz źródło mocy **TRENAŻER**.

Gdy w pobliżu jest kilka trenażerów, wybierz konkretny: `scan.py`, a potem `--address`.

### Opcje

| Opcja | Znaczenie |
|---|---|
| `--sim` | symulowany trenażer (bez Bluetooth) |
| `--address ADRES` | konkretny trenażer (Windows: `AA:BB:CC:DD:EE:FF`, macOS: UUID) |
| `--name TEKST` | fragment nazwy (domyślnie `SUITO`); `--name ""` = pierwszy trenażer FTMS |
| `--host`, `--port` | adres serwera WebSocket (domyślnie `127.0.0.1:8765`) |
| `--scan-timeout S` | długość jednego skanowania (domyślnie 10 s) |
| `--no-ui` | zwykłe logi zamiast podglądu (np. praca w tle) |
| `-v`, `--verbose` | szczegółowe logi, także bleak i websockets |
| `--sim-power W` | symulator: moc bazowa bez ERG (domyślnie 180 W) |
| `--sim-seed N` | symulator: stałe ziarno losowania |
| `--sim-dropout-every S`, `--sim-dropout-duration S` | symulator: co S s udawaj zerwanie łącza (test pauzy w grze) |

Symulator: moc wokół bazy z szumem i powolnym dryfem, ERG dochodzi do celu w ok. 2 s,
nachylenie zmienia moc i prędkość (pod górę mocniej i wolniej), kadencja 80–95 obr./min.

## Skaner BLE

```powershell
.\.venv\Scripts\python scan.py            # wszystkie urządzenia BLE w pobliżu
.\.venv\Scripts\python scan.py --ftms     # tylko trenażery FTMS
```

Pokazuje nazwę, adres, siłę sygnału (RSSI) i zaznacza urządzenia z usługą FTMS (0x1826).
Na końcu podpowiada gotowe `--address`.

## Protokół WebSocket (wersja 1)

Ramki tekstowe z JSON. Mostek → gra:

```json
{"type":"data","power":212,"cadence":87.5,"speed":31.4,"timestamp":1763236800.25}
{"type":"status","state":"connected","device":"SUITO 12345","erg":220,"grade":null}
{"type":"pong"}
{"type":"error","message":"nieznana komenda \"boost\" (znane: erg, slope, ping)"}
```

- `data` – co 250 ms, tylko gdy trenażer jest połączony (albo działa symulator). Moc w W (int),
  kadencja w obr./min, prędkość w km/h, czas uniksowy w sekundach. Gdy połączony trenażer
  milknie na dłużej niż 3 s (koło stoi), mostek wysyła zera.
- `status` – po połączeniu gry i przy każdej zmianie. `state`: `searching` (szukam), `connecting`,
  `connected`, `disconnected` (zerwane – mostek sam ponawia), `sim`. `erg` i `grade` to cele
  zadane przez grę (`null` = brak).

Gra → mostek:

```json
{"cmd":"erg","watts":220}      // ERG: trenażer trzyma 220 W; watts <= 0 wyłącza ERG
{"cmd":"slope","grade":4.5}    // symulacja nachylenia w %, przycinana do ±20 %
{"cmd":"ping"}                 // odpowiedź {"type":"pong"}
```

Zasady:
- **ERG ma pierwszeństwo przed nachyleniem** – nachylenie zadane w czasie ERG czeka i wchodzi
  po wyłączeniu ERG (zaplanowany trening musi zostać zrealizowany w 100 %).
- ERG powyżej 2000 W jest odrzucany (`error`), zakres mocy zgłoszony przez trenażer też jest
  respektowany.
- Po ponownym połączeniu z trenażerem mostek sam wysyła ostatnie ERG/nachylenie; gra po
  ponownym połączeniu z mostkiem wysyła swoje cele jeszcze raz.
- Błędne ramki dostają `error`, połączenie zostaje otwarte. Nieznane pola są ignorowane.
- Serwer słucha tylko na localhost i odrzuca połączenia z przeglądarek (nagłówek `Origin`),
  więc żadna strona WWW nie może sterować oporem trenażera.

Po stronie gry protokół obsługuje `game/scripts/power/websocket_power_source.gd`
(`WebSocketPowerSource`). Ręczny test całego toru gra ⇄ mostek:

```powershell
.\.venv\Scripts\python -m wasteland_bridge --sim            # okno 1
godot --headless --path game --script res://tests/integration/bridge_probe.gd -- --seconds=6   # okno 2
```

Sonda co 0,5 s wypisuje stan, moc i kadencję, wysyła ERG 250 W i kończy się `WYNIK: OK`,
gdy mostek potwierdził ERG, a moc doszła do celu.

## Testy

```powershell
.\.venv\Scripts\python -m pytest
```

Testy nie potrzebują Bluetooth: parser Indoor Bike Data (różne kombinacje flag, w tym „More
Data”), kodowanie komend Control Point, odpowiedzi i statusy trenażera, wybór urządzenia,
symulator, obsługa komend oraz prawdziwe połączenie WebSocket na losowym porcie.

## Rozwiązywanie problemów

- **„Nie widać trenażera”** – Suito śpi (zakręć korbą), jest połączone z inną aplikacją albo
  telefonem (rozłącz), Bluetooth jest wyłączony albo komputer stoi za daleko (pomaga adapter
  BLE na przedłużaczu USB bliżej trenażera). Sprawdź `scan.py --ftms`.
- **„Trenażer odmówił sterowania”** – inna aplikacja trzyma sterowanie (Zwift, MyWhoosh, Elite).
  Zamknij ją i uruchom mostek ponownie.
- **Suito nie może być połączone jednocześnie z Zwiftem ani inną aplikacją sterującą** – oporem
  steruje wyłącznie gra przez ten mostek.
- **Garmin**: Edge 840 nagrywa trening sam, z pomiaru mocy w rowerze (i tętno z Fenix 7 Pro), i
  wysyła go do Garmin Connect. Nie dodawaj Suito na Edge jako trenażera – Edge mógłby przejąć
  sterowanie oporem. Moc w grze pochodzi z Suito, a w pliku Garmina z pomiaru w rowerze, więc
  drobne różnice są normalne.
- **Port 8765 zajęty** („Nie mogę otworzyć ws://127.0.0.1:8765”) – działa już drugi mostek albo
  inny program zajmuje ten port (sprawdź: `netstat -ano | findstr :8765`). Uruchom mostek z
  `--port 8766` i ustaw ten sam adres w grze.
- **Windows**: nie paruj Suito w Ustawieniach → Bluetooth – FTMS działa bez parowania. Jeśli
  było sparowane i są kłopoty, usuń je z listy urządzeń.
- **macOS**: adresy urządzeń to UUID-y, nie adresy MAC; bez zgody na Bluetooth skanowanie nic
  nie znajdzie.
- **ERG „staje dęba”** przy bardzo niskiej kadencji – zwiększ kadencję albo zmniejsz bieg; ERG
  trzyma moc niezależnie od przełożenia.
- Ctrl+C nie działa w Git Bash (mintty) – uruchamiaj mostek w PowerShell albo Windows Terminal.
- Więcej szczegółów: `-v`.
