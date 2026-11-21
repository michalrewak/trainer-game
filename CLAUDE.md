# Wasteland Rider – brief gry na trenażer

## Cel

Gra 3D w Godot 4 sterowana trenażerem Elite Suito (Bluetooth FTMS), wyświetlana na telewizorze LG OLED z laptopa/PC przez HDMI. Nadrzędna zasada: **jeśli załadowany jest trening, gra ma go zrealizować w 100%** – rozgrywka jest nagrodą i otoczką, nigdy nie wymaga odstępstwa od planu. Dodatkowo tryb wolnej jazdy bez treningu.

## Świat i klimat

Ziemia po apokalipsie w stylu Mad Max: pustynie, kaniony, zrujnowane miasta, strefy skażone, burze piaskowe, gangi na buggy. Kamera zza pojazdu, z góry pod kątem (third-person chase cam), pokazująca cały pojazd i to, co nadjeżdża.

Fabuła (Żarłok, Tłuści, burze iskrowe), kierunek graficzny (dzień, burza, noc) i filary rozgrywki (największy nacisk: rozwój pojazdu; decyzje na trasie i zwiad) są opisane w [docs/swiat.md](docs/swiat.md). Przy pracy nad wyglądem, fabułą i progresją trzymaj się tego dokumentu.

## Pojazd i progresja

- Start: jednoosiowy buggy z pedałowym generatorem.
- Rozbudowa modułowa: kolejne osie, przyczepy, wieżyczki, pancerz, zawieszenie, filtr powietrza, silnik/mnożniki mocy. Każdy moduł widocznie zmienia sylwetkę pojazdu (docelowo „pustynny pociąg pancerny”).
- Waluta: złom i paliwo zbierane podczas jazdy.
- Tereny odblokowywane częściami i wymaganiami mocy (np. góry dopiero przy odpowiednim FTP) – progres w grze odzwierciedla realną formę.

## Mechanika jazdy

- Moc z trenażera = prędkość pojazdu (z uwzględnieniem ulepszeń silnika).
- Trasa oparta o pasy: szeroki kanion z 3–4 torami, zmiana pasa krzyżakiem/lewą gałką pada. Omijanie wraków, zbieranie złomu, wybór odnogi na rozwidleniach.
- Kadencja pokazywana dyskretnie w HUD, nie jest mechaniką.

## Walka

- Wrogie pojazdy nadjeżdżają z boków i próbują zepchnąć gracza; obrona: strzał z wieżyczki (prawa gałka celuje, trigger strzela) lub zmiana pasa.
- Przegrana potyczka = utrata części złomu, nigdy „śmierć” ani przerwanie treningu.
- Trzymanie zadanej mocy = pełna tarcza i szybszy ogień; spadek poniżej celu = słabsze zasilanie, ale nadal można grać.
- Na ciężkich interwałach opcjonalne „pola bezpieczne” bez konieczności klikania.

## Trening

- Tryb treningowy: plan (interwały/regeneracja) rzeźbi trasę – interwał to burza piaskowa, podjazd lub pościg (trenażer dociska opór w trybie ERG), regeneracja to przejazd przez miasto ze zbieraniem złomu.
- Tryb wolny: gra sama proponuje wyzwania (ucieczka, podjazd) i dyktuje opór.
- Format planów: pliki workoutów (np. ZWO/FIT workout) + własny prosty format JSON.

## Sterowanie

Gamepad GameSir po Bluetooth, natywnie w Godot (klasa Input). Żadnych dodatkowych urządzeń na start.

## Integracja z Garminem

- Ustalony układ: Garmin Edge 840 nagrywa trening sam, z pomiaru mocy w rowerze (plus tętno z Fenix 7 Pro), i wysyła go do Garmin Connect. Gra NIE zapisuje FIT ani nie łączy się z Garminem. Suito jest podpięte tylko do gry (Bluetooth), więc nie ma konfliktu o sterowanie oporem. Opcjonalnie gra może czytać moc z pomiaru w rowerze zamiast z Suito.
- Import planowanych treningów z Garmina – faza późniejsza (API wymaga zgody); na start plany lokalne/importowane plikami.

## Architektura

1. **Mostek (Python)** – łączy się z Suito przez BLE (biblioteka bleak, profil FTMS), czyta moc/kadencję/prędkość, ustawia opór/ERG i wystawia dane po WebSocket (localhost). Testowalny z terminala.
2. **Gra (Godot 4, GDScript)** – klient WebSocket, świat 3D, pojazd, pasy, walka, HUD, sklep ulepszeń, zapis postępu (JSON).
3. **Assety** – darmowe paczki (np. Kenney) na start, spójny low-poly styl.

## Etapy

1. Gra MVP bez trenażera: kanion z pasami, pojazd, zbieranie złomu, HUD. Pedałowanie symulowane padem (analogowy trigger = moc w watach).
2. Walka: wrogowie, wieżyczka, tarcza zależna od mocy, utrata złomu.
3. Progresja: baza między wyprawami, sklep, 3–5 ulepszeń, moduły pojazdu, drugi teren.
4. Tryb treningowy: parser planów, mapowanie interwałów na odcinki trasy, cel mocy w HUD, pola bezpieczne (nadal na symulowanej mocy).
5. Mostek Python do Suito (BLE FTMS, WebSocket) z trybem ERG – podmiana źródła mocy z pada na trenażer.
6. Tryb wolny z generowanymi wyzwaniami.
7. Garmin: import planów treningowych z plików eksportowanych z Garmin Connect.

## Zasady dla implementacji

- Każdy etap kończy się działającą, uruchamialną wersją.
- Symulator trenażera i tryb klawiaturowy w grze, żeby dało się testować bez sprzętu.
- Logika gry w czystych skryptach, minimalna zależność od klikania w edytorze.

## Prompt startowy dla Claude Code (etap 1: gra na padzie)

Najpierw sama gra, bez łączenia z trenażerem: integracja z Suito jest niskim ryzykiem i wchodzi dopiero w etapie 5. Przed startem zapisz treść tego briefu jako CLAUDE.md w istniejącym projekcie (nadpisując stary, jeśli jest), a poniższy tekst podaj jako pierwsze zadanie. Stary kod trafi na branch archive/stara-proba, a main zostanie wyczyszczony.

```markdown
Budujemy grę opisaną w CLAUDE.md. Zaczynamy od ETAPU 1: grywalna gra BEZ trenażera. Nie pisz żadnego kodu Bluetooth, ANT+, FTMS ani WebSocket – to osobny, późniejszy etap.

Krok 0 – porządek w repozytorium. W tym projekcie jest wcześniejsza, nieudana próba tej gry. Zaczynamy od zera na main, a stary kod ma zostać zarchiwizowany na osobnym branchu:
- Pokaż git status i aktualny branch. Jeśli są niezacommitowane zmiany, zacommituj je na obecnym branchu (commit "archiwum: stan przed restartem").
- Utwórz z tego stanu branch archive/stara-proba. Jeśli repo ma remote, wypchnij go.
- Sprawdź, że branch archiwalny istnieje i wskazuje na ten commit. Dopiero wtedy przejdź na main (lub główny branch repo) i usuń z niego wszystkie stare pliki projektu jednym commitem ("restart: czysty start"). Zostaw CLAUDE.md, .gitignore i LICENSE, jeśli istnieją.
- Bez force-push, bez przepisywania historii, bez kasowania branchy. Nie korzystaj ze starego kodu i nie przenoś go do nowej wersji.
Nową grę buduj w katalogu game/ na main.

Zadanie: projekt Godot 4 (najnowsza stabilna wersja, GDScript), który po uruchomieniu daje grywalną pętlę:
1. Trasa: prosty kanion na postapokaliptycznej pustyni z 3 pasami, generowany z segmentów, bez końca. Kamera zza pojazdu, z góry pod kątem.
2. Pojazd: jednoosiowy buggy. Prędkość wynika z mocy w watach (prosty model: moc -> prędkość z bezwładnością).
3. Źródło mocy za interfejsem PowerSource (get_power_watts, get_cadence). Teraz jedyna implementacja to GamepadPowerSource: prawy analogowy trigger pada = 0–350 W z wygładzaniem, przycisk tempomatu blokuje aktualną moc, żeby nie trzymać triggera. Zapasowo klawiatura (W/S zmienia moc o 10 W). Reszta gry nie może wiedzieć, skąd pochodzi moc – później dojdzie implementacja czytająca trenażer.
4. Sterowanie padem (GameSir, standardowe mapowanie Godota przez Input Map): krzyżak lub lewa gałka = zmiana pasa, prawa gałka i trigger zarezerwowane na celowanie i strzał w etapie 2.
5. Na trasie: wraki do omijania (zderzenie = utrata prędkości i części złomu, nigdy koniec gry) oraz złom do zbierania.
6. HUD czytelny z 3 metrów na telewizorze: duża moc w watach, prędkość, dystans, czas, licznik złomu. Wysoki kontrast, minimum elementów.
7. Koniec wyprawy po zadanym czasie (domyślnie 15 min, do testów 2 min): ekran podsumowania, złom zapisany do pliku JSON. Każda sesja kończy się postępem.

Zakres jest celowo mały: jedna mapa, jeden pojazd, jedna pętla. Bez walki, sklepu i treningów – to kolejne etapy.

Wymagania techniczne: sceny jako pliki .tscn, logika w skryptach, minimum pracy w edytorze. Grafika low-poly z paczek CC0 (np. Kenney); jeśli pobranie się nie uda, użyj prymitywów, ale ze spójną paletą i oświetleniem. Sprawdzaj projekt przez godot --headless (import i testy logiki modelu mocy oraz zapisu). README: jak uruchomić i jakie jest sterowanie.

Zanim zaczniesz pisać kod, przedstaw krótki plan (struktura plików, sceny, model moc -> prędkość) i poczekaj na akceptację. Na końcu podaj, jak uruchomić grę i co dokładnie mam sprawdzić na padzie.
```

Kolejne etapy zlecaj osobno, każdy po przetestowaniu poprzedniego na telewizorze z padem.

## Prompt na etap 5 (mostek do Suito)

```markdown
ETAP 5 z CLAUDE.md: podłączamy prawdziwy trenażer. Gra działa już na GamepadPowerSource.

Stwórz w katalogu bridge/ aplikację w Pythonie 3.12, która:
1. Łączy się przez BLE z Elite Suito (biblioteka bleak), profil FTMS (Fitness Machine Service, UUID 0x1826). Odczytuje Indoor Bike Data (moc, kadencja, prędkość) i wysyła komendy Control Point: Request Control, Set Target Power (ERG), Set Simulation Parameters (nachylenie).
2. Wystawia serwer WebSocket na localhost:8765. Co 250 ms wysyła JSON {power, cadence, speed, timestamp}. Przyjmuje komendy {cmd: "erg", watts} oraz {cmd: "slope", grade}.
3. Ma tryb --sim generujący realistyczne dane bez sprzętu.
4. Obsługuje rozłączenia: ponawia połączenie, a gra dostaje status i pauzuje wyprawę zamiast ją przerywać.
5. Ma podgląd danych na żywo w terminalu (rich) i skrypt listujący urządzenia BLE w pobliżu.

W grze dodaj WebSocketPowerSource implementujący ten sam interfejs PowerSource oraz wybór źródła mocy w menu (pad / trenażer). Testy jednostkowe parsera FTMS. README dla macOS i Windows.

Najpierw plan i akceptacja. Na końcu instrukcja krok po kroku, jak przetestować z prawdziwym Suito.
```
