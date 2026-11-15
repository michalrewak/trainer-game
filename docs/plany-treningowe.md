# Plany treningowe – model i formaty plików

Plany treningowe sterują trybem treningowym (etap 4) i importem planów z Garmina (etap 7).
Gra wczytuje trzy formaty:

| Rozszerzenie | Format | Skąd |
|---|---|---|
| `.json` | nasz prosty format (opis niżej) | pisany ręcznie, plany dołączone do gry |
| `.zwo` | trening Zwift (XML) | Zwift, whatsonzwift, edytory treningów |
| `.fit` | plik treningu FIT (typ *workout*) | eksport treningu z Garmin Connect |

Format wybierany jest po rozszerzeniu (wielkość liter bez znaczenia). Plany dołączone do gry
leżą w `game/plans/`.

## Model w grze

Kod: `game/scripts/workout/`.

- **`WorkoutStep`** – jeden krok: rodzaj (`kind`), czas `duration_s`, cel mocy `power_start` →
  `power_end` jako **ułamek FTP** (0.75 = 75% FTP), opcjonalna kadencja `cadence_rpm` (0 = brak)
  i etykieta `label`. Krok stały ma `power_start == power_end`, rampa zmienia cel liniowo.
  Rodzaje: `WARMUP` (rozgrzewka), `COOLDOWN` (schłodzenie), `WORK` (praca/interwał),
  `RECOVERY` (regeneracja), `STEADY` (jazda równa), `FREERIDE` (jazda swobodna – **bez celu
  mocy**, cel = 0, czyli ERG wyłączony).
- **`WorkoutPlan`** – lista kroków z **rozwiniętymi powtórzeniami**, nazwa, opis,
  `source_format` (`json`/`zwo`/`fit`), `source_path`, `reference_ftp` (FTP użyte do przeliczenia
  watów z pliku; 0 = plan był względny). Najważniejsze funkcje:
  - `total_duration_s()`, `step_index_at(t)` (−1 po końcu planu; t < 0 jak 0),
    `step_start_s(i)`, `step_end_s(i)`, `time_in_step_s(t)`, `time_left_in_step_s(t)`;
  - `intensity_at(t)` – cel jako ułamek FTP (0 po końcu i w jeździe swobodnej),
    `target_watts_at(t, ftp)` – cel w watach dla FTP gracza;
  - `is_hard_step(i)` – krok ciężki: rodzaj `WORK` **albo** średni cel ≥ 0.88 FTP (jazda
    swobodna nigdy); `next_hard_step(i)`; `hard_blocks()` – ciężkie odcinki (ciągi sąsiednich
    ciężkich kroków) z `first`/`last` (indeksy kroków) i `start_s`/`end_s` – do zamiany
    interwałów na burze, podjazdy i pościgi na trasie;
  - `summary()` – podsumowanie (niżej), `to_json_dict()` – plan w naszym formacie JSON
    (np. do zapisania zaimportowanego planu), `describe()` – tekst do logów.
- **`WorkoutLoader`** – wczytywanie:
  - `load_file(path, ftp = 250)`, `parse_json(text, ftp = 250)`, `parse_zwo(text)`,
    `parse_fit(bytes, ftp = 250)`, `list_plan_files(dir)`, `is_supported_file(path)`;
  - wynik zawsze w postaci `{"plan": WorkoutPlan albo null, "error": String, "warnings": Array[String]}`.
    Błędny plik **nigdy nie wywraca gry**: `plan == null` i komunikat po polsku w `error`
    (przy `load_file` poprzedzony nazwą pliku). `warnings` to rzeczy wczytane z przybliżeniem –
    warto je pokazać graczowi przed startem.
  - `ftp` służy tylko do przeliczania planów zapisanych w **watach** (JSON z `absolute_watts`,
    cele FIT w watach). Najlepiej podawać FTP gracza – wtedy waty z pliku zostają dokładnie
    takie, jak w pliku. Plany względne (% FTP) skalują się z FTP gracza same.

### Podsumowanie planu – `summary()`

| Klucz | Znaczenie |
|---|---|
| `duration_s` | łączny czas planu (s) |
| `step_count` | liczba kroków po rozwinięciu powtórzeń |
| `hard_intervals` | liczba ciężkich interwałów; sąsiednie ciężkie kroki (np. over-under bez przerwy) liczą się raz |
| `hard_time_s` | czas w ciężkich krokach (s) |
| `time_above_threshold_s` | czas z celem ≥ 100% FTP (s); dla ramp liczony dokładnie |
| `freeride_s` | czas jazdy swobodnej (s) |
| `max_intensity` | najwyższy cel (ułamek FTP) |
| `avg_intensity` | średni cel ważony czasem |
| `intensity_factor` | szacunek IF = moc znormalizowana planu / FTP: próbki co 1 s, średnia krocząca 30 s, średnia czwartych potęg, pierwiastek 4. stopnia (jak NP) |
| `tss` | szacunek TSS = godziny × IF² × 100 |

Jazdę swobodną (bez celu) do `avg_intensity`, `intensity_factor` i `tss` liczymy jak 60% FTP.

## Nasz format JSON

```json
{
  "format": "wasteland-workout",
  "version": 1,
  "name": "Kanion 4x4",
  "description": "4 razy po 4 minuty mocno z 3 minutami luzu.",
  "steps": [
    {"type": "warmup", "duration": "10:00", "from": 0.50, "to": 0.75, "label": "Rozgrzewka"},
    {"repeat": 4, "steps": [
      {"type": "work", "duration": "4:00", "power": 1.05, "cadence": 95, "label": "Interwał 4 min"},
      {"type": "recovery", "duration": 180, "power": 0.55}
    ]},
    {"type": "cooldown", "duration": "10:00", "from": 0.65, "to": 0.45}
  ]
}
```

### Pola planu

| Pole | Typ | Wymagane | Opis |
|---|---|---|---|
| `steps` | lista | tak | kroki i bloki powtórzeń (niepusta) |
| `name` | tekst | nie | nazwa planu; bez niej – nazwa pliku |
| `description` | tekst | nie | opis dla gracza |
| `absolute_watts` | true/false | nie | `true` = liczby w `power`/`from`/`to` to **waty** |
| `ftp` | liczba (W) | nie | FTP, dla którego zapisano waty (przy `absolute_watts`) |
| `version` | liczba | nie | wersja formatu (teraz 1); nowsza → ostrzeżenie |
| `format`, `author`, `tags`, `sport` | dowolne | nie | informacyjne, ignorowane |

### Pola kroku

| Pole | Typ | Opis |
|---|---|---|
| `type` | tekst | `warmup`, `cooldown`, `work`, `recovery`, `steady`, `freeride`, `ramp` (bez rozróżniania wielkości liter); aliasy: `interval` = work, `rest` = recovery, `free`/`free_ride` = freeride, `warm_up`, `cool_down` |
| `duration` | liczba albo tekst | sekundy (`90`, `90.5`) albo `"mm:ss"` (`"4:30"`, `"90:00"`) albo `"h:mm:ss"` (`"1:05:00"`); musi być > 0 |
| `power` | liczba albo tekst | cel stały: ułamek FTP (`0.95`) albo tekst z procentem (`"95%"`) |
| `from`, `to` | jak `power` | rampa liniowa od `from` do `to` (zawsze oba) |
| `cadence` | liczba | sugerowana kadencja 0–250 obr./min |
| `label` | tekst | opis kroku dla gracza |

- Podaj **albo** `power`, **albo** `from` + `to` – nie oba.
- `ramp` wymaga `from` i `to`; rodzaj kroku wynika ze średniej: ≥ 0.88 FTP → praca, inaczej jazda równa.
  Każdy inny typ też może mieć `from`/`to` (np. `steady` z rampą).
- Bez celu mocy mogą być tylko: `warmup` (domyślnie 50 → 75%), `cooldown` (65 → 45%),
  `recovery` (50%) i `freeride` (zawsze bez celu – podane `power` jest pomijane z ostrzeżeniem).
- `work` z niską mocą jest dozwolone (decyzja autora planu).
- Klucze zaczynające się od `_` oraz `comment`, `comments`, `note`, `notes` są komentarzami.
  Inne nieznane klucze dają ostrzeżenie (łapie literówki typu `"durtion"`).

### Powtórzenia

```json
{"repeat": 3, "label": "seria", "steps": [ ...kroki albo kolejne bloki... ]}
```

`repeat` to łączna liczba wykonań bloku (1–100). Bloki można zagnieżdżać (do 8 poziomów).
Po wczytaniu powtórzenia są rozwinięte w zwykłą listę kroków (każdy krok to osobny obiekt).

### Waty zamiast % FTP

```json
{"name": "Waty", "absolute_watts": true, "ftp": 280, "steps": [
  {"type": "work", "duration": "2:00", "power": 308},
  {"type": "recovery", "duration": 120, "power": "50%"}
]}
```

Waty przeliczamy na ułamek FTP przez `ftp` z pliku (308 W / 280 = 1.10). Bez pola `ftp` używamy
FTP gracza przekazanego do loadera – wtedy cele w grze są dokładnie takie, jak w pliku. Tekst
z procentem (`"50%"`) zostaje względny, a domyślne cele rozgrzewki/schłodzenia też są względne.

### Walidacja i limity

Każdy błąd wskazuje miejsce ścieżką w stylu JSON, np.
`steps[1].steps[0]: brak celu mocy – dodaj "power" (ułamek FTP, np. 0.75) albo "from" i "to".`

- moc względna 0–3.0 (300% FTP) – liczba typu `95` daje błąd z podpowiedzią (procenty / waty);
  waty najwyżej 2500 W;
- czas kroku > 0 i ≤ 12 h; cały plan ≤ 12 h; najwyżej 5000 kroków po rozwinięciu;
- `repeat` całkowite 1–100, zagnieżdżenie ≤ 8;
- składnia: parser JSON Godota akceptuje przecinki na końcu list – to nie jest błąd.

## Zwift ZWO

Czytamy `<workout_file>` → `<name>`, `<description>` (także CDATA i encje XML), `<sportType>`
(inny niż `bike` → ostrzeżenie) i kroki z `<workout>`. Wielkość liter w nazwach elementów
i atrybutów nie ma znaczenia (`PowerLow` = `powerlow`).

| Element | Atrybuty | Krok w grze |
|---|---|---|
| `Warmup` | Duration, PowerLow, PowerHigh (albo Power), Cadence | `WARMUP`, rampa PowerLow → PowerHigh |
| `Cooldown` | jak wyżej | `COOLDOWN`, rampa **zawsze w dół** (od większej do mniejszej) – pliki bywają zapisane w obu konwencjach |
| `Ramp` | Duration, PowerLow, PowerHigh | rampa PowerLow → PowerHigh (może być w dół); rodzaj z mocy* |
| `SteadyState`, `SolidState` | Duration, Power (albo PowerLow/PowerHigh → środek), Cadence | stały cel; rodzaj z mocy* |
| `IntervalsT` | Repeat (domyślnie 1), OnDuration, OffDuration, OnPower, OffPower (albo PowerOnLow/PowerOnHigh, PowerOffLow/PowerOffHigh – rampy), Cadence, CadenceResting | Repeat × (`WORK` + `RECOVERY`); bez OffDuration – same części On |
| `FreeRide` / `Freeride` | Duration, Cadence | `FREERIDE` (bez celu) |
| `MaxEffort` | Duration | `WORK` na 150% FTP, etykieta „Maksymalny wysiłek” |
| `textevent` / `TextEvent` | – | pomijane |

\* rodzaj z mocy: średnia ≥ 0.88 FTP → `WORK`, ≤ 0.55 FTP → `RECOVERY`, pomiędzy → `STEADY`.

Kadencja: `Cadence` albo środek `CadenceLow`/`CadenceHigh`; zła wartość → ostrzeżenie i brak kadencji.
Moc musi być ułamkiem FTP 0–3; czas ≥ 0 (zero → krok pominięty z ostrzeżeniem). Nieznane
elementy w `<workout>` są pomijane z ostrzeżeniem. Uszkodzony XML (niedomknięte znaczniki,
niepasujące zamknięcia, dane za `</workout_file>`) daje błąd z numerem linii.

## Garmin FIT (eksport treningu z Garmin Connect)

Plik FIT typu *workout* (file_id.type = 5). Gra **nie zapisuje** plików FIT i nie łączy się
z Garminem – tylko czyta wyeksportowane pliki (zgodnie z CLAUDE.md: aktywność nagrywa Edge 840).
Inne pliki FIT (zapis jazdy, trasa, harmonogram) są odrzucane z czytelnym komunikatem.

### Dekoder binarny (`FitDecoder`)

- nagłówek 12 albo 14 B (i dłuższy – resztę pomijamy), sygnatura `.FIT`, protokół 1.x/2.x
  (nowszy → ostrzeżenie i próba odczytu);
- rekordy definicji i danych, lokalne typy 0–15, redefinicje, architektura little/big endian;
- pola deweloperskie (Connect IQ) – pomijane (rozmiar z definicji);
- nagłówki ze skompresowanym znacznikiem czasu – dekodowane (przesunięcie 5-bitowe z przeniesieniem);
- wszystkie typy bazowe (enum, sint/uint 8/16/32/64, warianty „z”, string UTF-8, float32/64,
  byte, tablice); wartości „nieprawidłowe” (np. 0xFF, 0xFFFF, 0 dla typów „z”) → `null`;
  nieznany typ bazowy albo rozmiar niepodzielny przez typ → pole jako bajty (ostrzeżenie);
- plik większy niż 4 MB → błąd (to na pewno nie plan).

**Decyzja o CRC:** sumy kontrolne są sprawdzane (CRC-16 z FIT SDK), ale **niezgodność to
ostrzeżenie, nie błąd** – zarówno dla nagłówka, jak i całego pliku. Powód: struktura pliku jest
weryfikowana bajt po bajcie (ucięty plik, rekord bez definicji, zła architektura → błąd), a plan
przechodzi potem walidację (zakresy mocy, czasy, liczba kroków). Dzięki temu wczytamy plik
z narzędzia, które źle liczy CRC, a gracz dostanie ostrzeżenie „Suma kontrolna pliku FIT się nie
zgadza – plik mógł zostać uszkodzony, sprawdź plan”. CRC nagłówka równe 0 oznacza „nie liczono”.
Brak sumy kontrolnej na końcu, dodatkowe bajty za danymi (np. sklejone pliki – czytamy pierwszy)
i rozmiar danych 0 w nagłówku (zapis strumieniowy) to także tylko ostrzeżenia.

### Wiadomości i pola

| Wiadomość | Pola |
|---|---|
| `file_id` (0) | `type` (0) – musi być 5 = workout (brak typu → ostrzeżenie) |
| `workout` (26) | `wkt_name` (8) → nazwa, `wkt_description` (17) → opis, `sport` (4) – inny niż kolarstwo/ogólny → ostrzeżenie, `num_valid_steps` (6) – niezgodność → ostrzeżenie |
| `workout_step` (27) | `message_index` (254), `wkt_step_name` (0), `duration_type` (1), `duration_value` (2), `target_type` (3), `target_value` (4), `custom_target_value_low/high` (5/6), `intensity` (7), `notes` (8), `secondary_target_type` (19), `secondary_custom_target_value_low/high` (21/22) |

Kroki układamy wg `message_index` (bity 0–11; flaga „selected” ignorowana). Bez poprawnych,
unikalnych numerów – kolejność z pliku (ostrzeżenie). Etykieta kroku: `wkt_step_name`, a bez
niej `notes`.

### Czas kroku (`duration_type`)

| Typ | W grze |
|---|---|
| TIME (0), REPETITION_TIME (28), TIME_ONLY (31) | `duration_value` w ms → sekundy; 0/brak → krok pominięty (ostrzeżenie) |
| OPEN (5) – „do naciśnięcia Lap” | **5 minut** (ostrzeżenie); cel kroku zostaje (bez celu → jazda swobodna) |
| DISTANCE (1) | dystans przeliczony przy 30 km/h (ostrzeżenie) |
| CALORIES (4) | czas = kcal × 1000 / waty celu (1 kcal ≈ 1 kJ pracy; min. 100 W) (ostrzeżenie) |
| warunki tętna/mocy/TSS (2, 3, 14–26, 29 i inne) | 5 minut (ostrzeżenie – gra nie sprawdza warunków) |
| REPEAT_UNTIL_STEPS_CMPLT (6) | powtórzenie, niżej |

### Powtórzenia

Krok z `duration_type = REPEAT_UNTIL_STEPS_CMPLT` (6): `duration_value` = `message_index`
pierwszego kroku bloku, `target_value` = **łączna** liczba wykonań bloku (np. 4 = blok 4 razy).
Blok to wszystko od wskazanego kroku do kroku powtórzenia, więc zagnieżdżone powtórzenia
działają (wewnętrzne są już rozwinięte). `REPEAT_UNTIL_TIME` (7): tyle wykonań, ile trzeba, żeby
przekroczyć zadany czas (ostrzeżenie). Inne warunki (dystans, kalorie, tętno, moc): blok raz
(ostrzeżenie). Błędne odwołanie (do przodu, do siebie) → powtórzenie pominięte (ostrzeżenie);
więcej niż 100 powtórzeń albo 5000 kroków → błąd (plik prawdopodobnie uszkodzony).

### Cel (`target_type`)

| Cel | W grze |
|---|---|
| POWER (4) i warianty POWER_3S/10S/30S/LAP (7–10) | `target_value` 1–7 → strefa mocy (tabela niżej); `target_value` 0 → własny zakres `custom_target_value_low/high`: **0–1000 = % FTP, > 1000 = waty + 1000** (1250 = 250 W → ułamek FTP przez `ftp` loadera, domyślnie 250 W). Brak jednej granicy → druga; odwrócone granice są zamieniane; ponad 300% FTP → przycięte (ostrzeżenie); zakres 0–0 → brak celu |
| OPEN (2) albo brak celu | `FREERIDE` – jazda swobodna (ERG wyłączony); etykieta np. „Regeneracja – bez celu mocy” |
| tętno (1, 13) | strefa 1–5 → szacunek mocy (tabela); zakres (`% HRmax` 0–100 albo `bpm + 100`) → moc wg intensywności; etykieta np. „Cel: tętno 140–150 ud./min” |
| prędkość (0, 12), kadencja (3), nachylenie (5), opór (6), inne | moc szacowana wg intensywności, etykieta z celem oryginalnym; dla kadencji z zakresu – `cadence_rpm` = środek |

Jeśli cel główny nie jest mocą, a **drugi cel** (`secondary_target_*`) jest – bierzemy moc z drugiego.
Drugi cel kadencji (np. 90–100) → `cadence_rpm` = środek (95).

**Zakres mocy → cel ERG:** trenażer potrzebuje jednej wartości, więc bierzemy **środek zakresu**.
Wyjątki, w których rampa przez cały czas mieści się w zakresie: rozgrzewka – rampa od dolnej do
górnej granicy, schłodzenie – od górnej do dolnej. Dzięki temu np. rozgrzewka „50–75% FTP”
z Garmina jest tą samą rampą 50 → 75%, co w planie JSON.

| Strefa mocy | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| ułamek FTP | 0.50 | 0.65 | 0.83 | 0.98 | 1.13 | 1.35 | 1.50 |

| Strefa tętna | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| szacowana moc (ułamek FTP) | 0.50 | 0.65 | 0.80 | 0.92 | 1.05 |

| Intensywność kroku (gdy cel nie jest mocą) | active | rest | warmup | cooldown | recovery | interval | other |
|---|---|---|---|---|---|---|---|
| szacowana moc (ułamek FTP) | 0.70 | 0.50 | 0.55 | 0.50 | 0.50 | 0.90 | 0.65 |

### Rodzaj kroku (`intensity`)

| intensity | Rodzaj |
|---|---|
| active (0), other (6), brak | `WORK` gdy cel ≥ 0.88 FTP, inaczej `STEADY` |
| rest (1), recovery (4) | `RECOVERY` |
| warmup (2) | `WARMUP` |
| cooldown (3) | `COOLDOWN` |
| interval (5) | `WORK` |

Brak celu mocy (OPEN) zawsze daje `FREERIDE`, niezależnie od intensywności.

## Plany dołączone do gry (`game/plans/`)

| Plik | Plan | Czas | Opis |
|---|---|---|---|
| `kanion_4x4.json` | Kanion 4x4 | 48 min | rozgrzewka 50 → 75%, 4 × (4 min 105% / 3 min 55%), schłodzenie 65 → 45%; IF ≈ 0.83, TSS ≈ 55 |
| `pustynny_szlak.json` | Pustynny szlak | 30 min | jazda w 2. strefie (70%) z pięcioma zrywami 30 s na 120%; IF ≈ 0.75 |
| `szybki_test_20min.json` | Szybki test 20 min | 20 min | demo/test gry i trenażera: 6 × (1 min 110% / 1 min 50%), rampa 60 → 95%, jazda swobodna, schłodzenie – każdy rodzaj kroku |
| `piramida_progowa.zwo` | Piramida progowa | 39 min | przykład formatu ZWO: 2-3-4-3-2 min przy 95–103% FTP, jazda swobodna, schłodzenie |

Uwaga dla eksportu gry: pliki `.json`, `.zwo` i `.fit` nie są zasobami Godota – trzeba je dodać do
filtra eksportu („Filters to export non-resource files”: `plans/*`).

## Testy i fixture'y

- Testy: `game/tests/unit/test_workout_*.gd` (model, JSON, ZWO, dekoder FIT, treningi FIT, loader)
  – uruchamiane razem z resztą: `godot --headless --path game --script res://tests/run_tests.gd`
  (tylko plany: `-- --filter=workout`).
- Fixture'y: `game/tests/fixtures/workouts/` – `kanion_4x4.zwo` i `kanion_4x4.fit` (ten sam plan co
  `game/plans/kanion_4x4.json`; test sprawdza, że wszystkie trzy dają identyczne kroki),
  `garmin_powtorzenia_waty.fit` (cele w watach, strefy, krok „do Lap”, drugi cel kadencji,
  zagnieżdżone powtórzenia), `zwift_warianty.zwo` (warianty zapisu), pliki uszkodzone (`zly.json`,
  `zly.zwo`, `uciety.fit`, `zla_suma_kontrolna.fit`, `aktywnosc.fit`, `bez_krokow.json`) i
  `waty_absolutne.json`.
- Pliki `.fit` generuje koder testowy `FitWriter` (`game/tests/fixtures/fit_writer.gd`) z definicji
  w `WorkoutFixtures` (`game/tests/fixtures/workout_fixtures.gd`). Po zmianie definicji:
  ```
  godot --headless --path game --script res://tests/fixtures/make_workout_fixtures.gd
  ```
  Test `test_fixture_files_are_up_to_date` pilnuje, że pliki w repozytorium zgadzają się z kodem.
  `FitWriter` liczy CRC inną metodą (16-elementowa tablica z FIT SDK) niż dekoder (tablica
  256-elementowa) – testy porównują obie i wektor kontrolny CRC-16/ARC („123456789” → 0xBB3D).
- Testy odporności: losowo uszkadzane pliki FIT i ZWO (stałe ziarno) – wynik zawsze jest
  słownikiem z planem albo komunikatem błędu.
