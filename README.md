# Wasteland Rider

Gra 3D na trenażer rowerowy (Godot 4.7, GDScript). Postapokaliptyczna wyprawa przez kanion:
moc z nóg napędza buggy, pasy, wraki, złom, gangi na buggy, garaż z ulepszeniami.
Pełny opis założeń: [CLAUDE.md](CLAUDE.md).

## Uruchomienie (Windows)

1. Godot 4.7.2: albo własna instalacja, albo wersja przenośna pobierana skryptem
   (oficjalne wydanie z GitHuba, suma SHA-512 sprawdzana automatycznie):

   ```bash
   powershell -ExecutionPolicy Bypass -File tools/get-godot.ps1
   ```

2. Start gry (pełny ekran):

   ```bash
   .tools/godot-4.7.2/Godot_v4.7.2-stable_win64.exe --path game
   ```

   Na telewizorze podłączonym przez HDMI: `--screen 1` (numer ekranu) albo w grze **F10**
   (przenosi okno na kolejny ekran i zapamiętuje wybór). **F11** / **Alt+Enter** – pełny ekran.

3. Edytor: otwórz `game/project.godot` w Godot 4.7.

## Sterowanie

| Akcja | Pad (GameSir, układ standardowy) | Klawiatura |
|---|---|---|
| Moc (symulacja trenażera) | **RT** analogowo 0–350 W | – |
| Tempomat (zablokuj moc) | **LB** | C / Spacja |
| Moc ±10 W (włącza tempomat) | krzyżak **↑ / ↓** | W / S, strzałki ↑ / ↓ |
| Zmiana pasa | krzyżak **← / →**, lewa gałka | A / D, strzałki ← / → |
| Celowanie wieżyczki | prawa gałka (bez wychylenia = auto-cel) | auto-cel |
| Strzał | **LT** | F |
| Pauza / menu wyprawy | **Start** | Esc / P |
| Podgląd wejść pada | **Back / Select** | F3 |
| Menu | krzyżak/gałka + **A**, **B** wstecz | strzałki + Enter, Esc |

RT steruje mocą tylko w symulacji. Gdy moc będzie pochodzić z trenażera (etap 5), RT też
będzie strzelał.

### Pady GameSir po Bluetooth

Po Bluetooth GameSir nie daje trybu XInput. Analogowe triggery są w trybie **DS4**
(z wyłączonego pada: Home+B, niebieska dioda) albo przez **dongle 2,4 GHz** (Home+X). W trybie
Switch (Home+Y) triggery są cyfrowe (0 albo 1). Gra to wykrywa: wtedy przytrzymanie RT podnosi
moc o 40 W/s, a krzyżak ↑/↓ zmienia ją o 10 W. Gdy Steam jest uruchomiony, wyłącz Steam Input
dla tego pada (inaczej pad udaje mysz).

## Rozgrywka

- **Moc → prędkość**: model rowerowy z bezwładnością (opór powietrza, toczenia, podjazdy).
  200 W ≈ 31 km/h, 300 W ≈ 36 km/h. Moduł generatora podnosi prędkość przy tej samej mocy.
- **Wyprawa** trwa zadany czas (15/30/45/60 min, test 2 min). Kończy się zawsze po czasie,
  nigdy porażką. Zderzenie z wrakiem kosztuje prędkość i część złomu.
- **Złom** (cyjanowe zębatki) i **paliwo** (czerwone kanistry) to waluty garażu.
- **Gangi** dojeżdżają z boku i taranują. Obrona: wieżyczka, unik zmianą pasa po ostrzeżeniu
  „!” albo tarcza. Tarcza ładuje się i działko strzela szybciej, gdy trzymasz moc docelową
  (65% FTP w jeździe swobodnej). Przegrana potyczka to rabunek części złomu.
- **Garaż**: 5 ulepszeń (generator, pancerz, kondensator tarczy, wieżyczka, przyczepa),
  każde widać na pojeździe. Wybór terenu: Kanion Rdzy, Martwe Miasto (wymaga pancerza i
  FTP ≥ 150 W). Ustawienie FTP i auto-ognia.
- **Tryb wolny – wyzwania**: gra sama proponuje wyzwania i dyktuje opór. Podjazd 5% to
  nachylenie (symulacja trenażera), ucieczka przed gangiem w burzy piaskowej i sprint za
  ciężarówką to ERG. Cele liczone są od FTP. Nagrody: złom i paliwo, a nieudana ucieczka
  sprowadza gang. Na padzie ERG jest symulowany (tempomat sam ustawia moc celu).
- Postęp zapisuje się w `%APPDATA%\Godot\app_userdata\Wasteland Rider\progress.json`
  (zapis atomowy z kopią `.bak`), także przy przerwaniu wyprawy albo zamknięciu okna.

## Stan etapów

| Etap | Stan |
|---|---|
| 1. Gra na padzie (kanion, buggy, moc, HUD, zapis) | gotowe |
| 2. Walka (gang, wieżyczka, tarcza zależna od mocy) | gotowe |
| 3. Garaż, 5 ulepszeń, paliwo, drugi teren | gotowe |
| 4. Tryb treningowy | gotowe (wersja podstawowa): plan prowadzi jazdę, ERG, widełki ±5%, burze = pola bezpieczne |
| 5. Mostek Python do Suito | gra: wybór PAD/TRENAŻER w garażu, czekanie na mostek; mostek – patrz `bridge/` |
| 6. Tryb wolny z wyzwaniami | gotowe |
| 7. Import planów z Garmina (FIT) | parsery JSON/ZWO/FIT gotowe; pliki planów wrzucaj do `%APPDATA%\Godot\app_userdata\Wasteland Rider\plans` |

Cel mocy zawsze ma **widełki**: za mało i za dużo to błąd. W treningu obowiązuje ±5%, w
wyzwaniach ±8%. Powyżej górnej granicy generator się przegrzewa (słabsza tarcza i ogień).

Następne kroki: kampanie treningowe (kilka tygodni, prawdziwe protokoły, bossowie), ramp
test FTP jako walka z bossem, zakręty, wzniesienia i doliny na trasie, tempo gry
względem FTP.

## Trenażer Elite Suito (etap 5)

Gra łączy się z trenażerem przez mostek w Pythonie (`bridge/`, BLE FTMS ↔ WebSocket).
Szczegóły: [bridge/README.md](bridge/README.md).

1. Raz: `powershell -ExecutionPolicy Bypass -File bridge/setup.ps1` (venv z bleak/websockets/rich;
   użyje Pythona 3.12 z systemu albo przenośnego z `.tools/`).
2. Przed jazdą: `bridge/.venv/Scripts/python -m wasteland_bridge` (prawdziwe Suito) albo z
   `--sim` (symulator bez sprzętu). Suito nie może być w tym czasie połączone z Zwiftem ani
   inną aplikacją. Garmin Edge dalej nagrywa z pomiaru mocy w rowerze.
3. W garażu: **Moc: TRENAŻER**. Gra czeka na mostek (czas wyprawy stoi), a po utracie
   połączenia pauzuje. Przy trenażerze RT też strzela.

Port: domyślnie 8765. Na tym komputerze **8765 zajmuje inny program** (CutLoop). Uruchom
wtedy mostek z `--port 8766`, a grę z `-- --bridge-port=8766`; gra zapamięta port.

## Opcje uruchomienia (po `--`)

```bash
.tools/godot-4.7.2/Godot_v4.7.2-stable_win64.exe --path game -- --test --autostart
```

`--minutes=N`, `--test` (2 min), `--autostart`, `--autopilot` (jazda automatyczna),
`--time-scale=K`, `--seed=N`, `--quit-on-finish`, `--save=user://plik.json`,
`--screenshots=KATALOG --shot-times=4,12`, `--combat-test`, `--no-combat`,
`--terrain=city`, `--all-upgrades`, `--challenge-test`, `--no-challenges`, `--trainer`,
`--plan=res://plans/kanion_4x4.json`.
Szczegóły: `game/scripts/app/launch_options.gd`.

## Testy (bez sprzętu)

```bash
powershell -ExecutionPolicy Bypass -File tools/test.ps1
```

Skrypt importuje projekt, kompiluje wszystkie skrypty i sceny, uruchamia testy jednostkowe
(model mocy, pojazd, pasy, trasa, walka, progresja, zapis) i test dymny: pełną wyprawę
autopilotem, przyspieszoną, z zapisem wyniku. Pojedynczo:

```bash
.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/run_tests.gd
```

## Struktura

```
game/
  project.godot           ustawienia, Input Map (generowana: tools/generate_input_map.gd)
  scenes/                 sceny .tscn (wyprawa, buggy, garaż, HUD, pauza, podsumowanie)
  scripts/power/          PowerSource (interfejs) + źródła: pad, skrypt (autopilot)
  scripts/sim/            czysta logika: pojazd, pasy, trasa, walka, wyprawa, autopilot
  scripts/progression/    ulepszenia, moduły (Loadout), tereny
  scripts/save/           zapis postępu (JSON)
  scripts/view/, ui/      widoki 3D i interfejs
  tests/                  runner testów, testy jednostkowe, kontrola kompilacji
tools/                    get-godot.ps1, test.ps1
```

Reszta gry zna tylko interfejs `PowerSource` (`get_power_watts`, `get_cadence`, status,
ERG/nachylenie). Źródło trenażera z etapu 5 wpina się w `PowerSourceFactory` bez zmian w grze.

## Co sprawdzić na padzie

1. Ekran garażu: krzyżak przesuwa wybór, A zatwierdza. WYRUSZ! startuje wyprawę.
2. **Back** w trakcie jazdy: podgląd wejść. Sprawdź nazwę pada i czy „RT (oś 5)” płynnie
   rośnie od 0.00 do 1.00 przy powolnym wciskaniu. Same 0/1 oznaczają cyfrowy trigger
   (przełącz pad w tryb DS4: Home+B).
3. RT: moc w HUD rośnie płynnie do 350 W, a po puszczeniu spada.
4. **LB** przy wciśniętym RT: pojawia się „TEMPOMAT xxx W” i moc zostaje po puszczeniu RT.
   Ponowne LB wyłącza tempomat.
5. Krzyżak ↑/↓: ±10 W (przytrzymanie powtarza).
6. Krzyżak ←/→ i lewa gałka: zmiana pasa o jeden. Przytrzymanie przejeżdża dalej, a lekkie
   drgania gałki nie zmieniają pasa.
7. Wjedź w wrak: „-N ZŁOMU”, spadek prędkości, wyprawa trwa dalej.
8. Gang („◀ GANG”, potem „!!”): LT strzela, prawa gałka wybiera cel, zmiana pasa po „!”
   to unik.
9. **Start**: pauza. „Jedź dalej” albo „Zakończ wyprawę” (złom zostaje zapisany).
10. Test 2 min do końca: podsumowanie, a złom trafia do magazynu w garażu.
11. Wyłącz pad w trakcie jazdy: gra pauzuje z komunikatem i wraca po Start.
