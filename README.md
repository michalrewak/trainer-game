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
| Kierowanie płynne | **lewa gałka**: pojazd jedzie w dowolnym miejscu jezdni; po puszczeniu wspomaganie dociąga do najbliższego pasa (wyłączane w garażu) | – |
| Skok o pas | krzyżak **← / →** | A / D, strzałki ← / → |
| Celowanie wieżyczki | prawa gałka: czerwona linia pokazuje kierunek; blisko wroga celownik sam go łapie | auto-cel |
| Strzał | **LT** – strzela zawsze: we wroga w celowniku, a bez niego tam, gdzie wskazuje gałka (bez wychylenia prosto) | F |
| Dopalacz (wtrysk czystego paliwa) | **RB** albo **X** | B |
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
  200 W ≈ 31 km/h, 300 W ≈ 36 km/h.
- **Moc na kołach = moc z nóg × akceleratory × dopalacz.** Akceleratory działają stale:
  generator (moduł, do +25%) i załoga uwolnionych pedalarzy (+2% za osobę, tyle osób, ile
  ławek ma podwozie: 2, 4, 6). Dopalacz to chwilowy wtrysk czystego paliwa (+25–55% na
  6–10 s); wtryski uzupełniają kanistry zebrane na trasie. HUD pokazuje obie liczby, a
  wartości treningowe (kJ, NP, TSS, strefy) liczą się zawsze z samej mocy z nóg.
- **Wyprawa** to kurs z osady do osady. Trwa zadany czas (15/30/45/60 min, test 2 min
  albo długość planu treningowego): zaczyna się wyjazdem przez bramę, a pod koniec czasu
  na horyzoncie pojawia się osada docelowa i jazda kończy się wjazdem na jej plac. Nie ma
  „mety” ani porażki. Zderzenie z wrakiem kosztuje prędkość i część złomu.
- **Nawierzchnia** zmienia się co 200 m: stary asfalt, szuter z koleinami, betonowe płyty,
  stalowe maty.
- **Złom** (cyjanowe zębatki) i **paliwo** (czerwone kanistry) to waluty garażu.
- **Wraki można rozstrzelać**: dwa trafienia rozbijają wrak i zwalniają pas.
- **Gangi** dojeżdżają z boku i taranują. Obrona: wieżyczka, unik zmianą pasa po ostrzeżeniu
  „!” albo wyładowanie kondensatorów. Kondensatory ładują się i działko strzela szybciej, gdy trzymasz moc docelową
  (65% FTP w jeździe swobodnej). Przegrana potyczka to rabunek części złomu.
- **Garaż i rozwój pojazdu**: podwozie (druga i trzecia oś) oraz 8 modułów: generator,
  dopalacz, pancerz, kondensator, wieżyczka, taran, zawieszenie, chwytak. Każdy poziom
  widać na pojeździe. Przyczepa nie jest modułem: doczepiasz ją tylko na czas zadania
  „dowieź łup” po napadzie. Większe podwozie
  pozwala montować wyższe poziomy modułów i wymaga wypracowanych kilodżuli (400 kJ i
  2000 kJ łącznej pracy), więc nie da się go kupić samym złomem. Podsumowanie wyprawy
  podpowiada najbliższy cel. Wybór terenu: Kanion Rdzy, Martwe Miasto (wymaga pancerza i
  FTP ≥ 150 W). Ustawienie FTP i auto-ognia.
- **Tryb wolny – wyzwania**: gra sama proponuje wyzwania i dyktuje opór. Podjazd 5% to
  nachylenie (symulacja trenażera), ucieczka przed gangiem w burzy piaskowej i sprint za
  ciężarówką to ERG. Cele liczone są od FTP. Nagrody: złom i paliwo, a nieudana ucieczka
  sprowadza gang. Na padzie ERG jest symulowany (tempomat sam ustawia moc celu).
- **Napady i zwiad**: ok. 500 m przed zjazdem karta zwiadu pokazuje łup, obronę i koszt
  wysiłku liczony od FTP. Zjazd na skrajny pas = napad: podjazd pod ostrzałem z wież, brama
  (rozstrzelana, wyważona taranem albo sforsowana), plądrowanie, a potem dowiezienie łupu
  na doczepionej przyczepie.
- **Konwoje Tłustych**: środkowym pasem jedzie kolumna spięta sprzęgami: ogon ze strażą,
  galera (klatka z niewolnikami-pedalarzami i kanistrami) i ciągnik z tronem Barona Smalca.
  Cel: odczepić galerę. Sprzęg widać tylko z bocznego pasa, tuż zza niego, a konwój na
  zmianę ucieka (ok. 100% FTP) i hamuje (ok. 55% FTP), więc trzeba naprawdę przyspieszać
  i zwalniać, żeby utrzymać się w oknie. Trzy drogi: tylny sprzęg, potem przedni (czyste
  cięcie: pełny łup i dodatkowy uwolniony), od razu przedni (szybciej, ale ogon zabiera 30%
  łupu) albo rozbicie ciągnika (łup ×1,5, najwięcej pancerza). W klatkę nie wolno strzelać:
  trzy trafienia to jeden uwolniony mniej. Po odcięciu trzeba zwolnić poniżej 18 km/h
  i przytrzymać się wagonu – wtedy pedalarze przeskakują do załogi. Za mało mocy i konwój
  ucieka; po 3,5 min walki dojeżdża do twierdzy. Panel w lewym górnym rogu pokazuje schemat
  kolumny, twoją pozycję i polecenie „przyspiesz / zwolnij”.
- **Gadające głowy**: zdarzenia komentują postacie ze świata gry – Baron Smalec (Tłusty),
  Chudy (pedalarz z galery), Zębatka (mechaniczka z osady, podpowiada taktykę), Brat Obrót
  (Kościół Świętej Kadencji, komentuje kadencję) i Iskra (gang). W spokojnych chwilach
  opowiadają historię świata.
- **Passa**: zębatki, uniki i rozbite cele bez wpadki podbijają mnożnik złomu (do ×3). Zegar
  passy odnawia każdy punkt; zderzenie, rabunek albo mina zerują ją.
- **Zlecenia**: trzy cele na wyprawę widoczne w prawym górnym rogu (jedno treningowe, np.
  czas w widełkach, i dwa zręcznościowe albo „duże”: konwój, osada). Nagroda w złomie,
  za komplet dodatkowy kanister.
- **Skrzynie** ze znakiem zapytania: losowo deszcz zębatek, kanister, pełny dopalacz
  z kondensatorami albo złota zębatka. **Unik o włos** (zjazd z pasa wraku w ostatniej chwili)
  daje punkty passy.
- **Rekordy**: najlepsza moc z 20 s, 1 min, 5 min i 20 min, najwyższa passa, złom i praca
  z wyprawy. Osobne tabele dla pada i trenażera; komunikat na żywo i lista w podsumowaniu.
  Garaż pokazuje cel tygodnia w TSS i liczbę dni z rzędu.
- **Dźwięk**: efekty generowane w grze (bez plików audio); kolejne zębatki grają coraz
  wyższą nutą. Wyłączanie w garażu albo opcją startu --mute.
- **Wartości treningowe**: HUD pokazuje procent FTP i strefę mocy, podsumowanie – NP, IF,
  TSS, kJ i czas w strefach Z1–Z7, garaż – rangę wynikającą z FTP i trening z 7 dni.
- Postęp zapisuje się w `%APPDATA%\Godot\app_userdata\Wasteland Rider\progress.json`
  (zapis atomowy z kopią `.bak`), także przy przerwaniu wyprawy albo zamknięciu okna.

## Stan etapów

| Etap | Stan |
|---|---|
| 1. Gra na padzie (kanion, buggy, moc, HUD, zapis) | gotowe |
| 2. Walka (gang, wieżyczka, kondensatory ładowane mocą) | gotowe |
| 3. Garaż, 5 ulepszeń, paliwo, drugi teren | gotowe |
| 4. Tryb treningowy | gotowe (wersja podstawowa): plan prowadzi jazdę, ERG, widełki ±5%, burze = pola bezpieczne |
| 5. Mostek Python do Suito | gra: wybór PAD/TRENAŻER w garażu, czekanie na mostek; mostek – patrz `bridge/` |
| 6. Tryb wolny z wyzwaniami | gotowe |
| 7. Import planów z Garmina (FIT) | parsery JSON/ZWO/FIT gotowe; pliki planów wrzucaj do `%APPDATA%\Godot\app_userdata\Wasteland Rider\plans` |

Cel mocy zawsze ma **widełki**: za mało i za dużo to błąd. W treningu obowiązuje ±5%, w
wyzwaniach ±8%. Powyżej górnej granicy generator się przegrzewa (wolniej ładują się kondensatory, wolniejszy ogień).

Następne kroki: nowy wygląd menu i HUD, kampanie treningowe (kilka tygodni, prawdziwe
protokoły, bossowie), ramp test FTP jako walka z bossem, napady i konwoje w trybie
treningowym (dziś są tylko w jeździe swobodnej).

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
`--terrain=city`, `--all-upgrades`, `--challenge-test`, `--no-challenges`, `--raid-test`,
`--no-raids`, `--convoy-test` (konwój po 5 s, bez zwiadów i wyzwań), `--no-convoys`, `--mute`,
`--window=1920x1080` (okno zamiast pełnego ekranu, np. podgląd układu telewizora), `--trainer`,
`--plan=res://plans/kanion_4x4.json`, `--time=cycle|day|dusk|night|storm`.
Szczegóły: `game/scripts/app/launch_options.gd`.

## Testy (bez sprzętu)

```bash
powershell -ExecutionPolicy Bypass -File tools/test.ps1
```

Skrypt importuje projekt, kompiluje wszystkie skrypty i sceny, uruchamia testy jednostkowe
(model mocy, pojazd, pasy, trasa, walka, napady, konwoje, układ napędowy, progresja, zapis)
i dwa testy dymne: pełną wyprawę autopilotem oraz wyprawę z konwojem, przyspieszone,
z zapisem wyniku. Podgląd gadających głów: `--script res://tests/show_busts.gd -- plik.png`.
Pojedynczo:

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
