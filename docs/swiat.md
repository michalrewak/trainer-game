# Wasteland Rider – świat, kierunek graficzny i filary rozgrywki

Ustalenia z 2026-11-21. Ten dokument jest źródłem prawdy dla fabuły, wyglądu gry
i priorytetów projektowych. Założenia techniczne i etapy są w [CLAUDE.md](../CLAUDE.md).

## Historia: dlaczego wszyscy pedałują

### Żarłok

Gdy ropa się kończyła, koncerny wyhodowały bakterię do sprzątania wycieków. Wymknęła się
z laboratoriów i zmutowała. Żarłok zjada wszystko, co magazynuje energię: paliwo w baku
gnije w kilka dni, a baterie puchną i wybuchają. Elektrownie stanęły, bo nie było czym
dowieźć części ani jak przechować prądu.

Działa tylko energia zużyta w tej samej sekundzie, w której powstała. Jedyny napęd, który
przetrwał, to mięsień → generator → silnik. Kto nie kręci, ten stoi. Kto stoi, tego zasypie
piasek albo znajdzie gang.

### Waty to status

Ludzi nie pyta się o imię, tylko „ile ciągniesz?”. FTP to ranga: decyduje, do jakiego
konwoju cię wezmą, na jakie tereny wpuszczą i kto usiądzie obok ciebie przy ognisku.
Test FTP to rytuał przejścia, który odbywa się publicznie i na oczach całej osady.

### Tłuści

Watażkowie pustkowi sami nie pedałują. Ich machiny wojenne napędzają dziesiątki skutych
niewolników na galerach pedałowych: im większa machina, tym więcej ludzi w łańcuchach pod
pokładem. Tłuści to bossowie. Rozbicie machiny uwalnia pedalarzy, a część z nich może
dołączyć do załogi gracza.

### Czyste paliwo

Zaplombowane kanistry sprzed zarazy są święte i bezcenne. Po otwarciu Żarłok dobiera się
do nich w kilka godzin, więc nikt nie spala ich w silniku. Służą za walutę, a w walce
do miotaczy ognia i innych jednorazowych broni.

### Burze iskrowe

Piasek niesie ładunek elektryczny. Burza iskrowa to ściana pyłu z wyładowaniami, przez
którą prawie nic nie widać. Kto przez nią przejedzie, ten ładuje kondensatory, dlatego
najodważniejsi wjeżdżają w burzę celowo. W grze burza to interwał, a tarcza bierze się
z trzymania mocy.

### Kościół Świętej Kadencji

Fanatycy wierzą, że świat skończył się, bo ludzkość przestała kręcić. Jeżdżą na stałym
90 obr./min, noszą liczniki kadencji jak relikwie i gardzą każdym, kto „mieli”.
Bywają sojusznikami albo wrogami, zależnie od tego, jak gracz jeździ.

### Jak fabuła tłumaczy mechaniki

| Mechanika | Wyjaśnienie w świecie |
|---|---|
| Moc z nóg = prędkość | jedyny działający napęd, generator pedałowy |
| Tarcza zależna od trzymania mocy | kondensatory ładowane równą pracą generatora |
| Za duża moc szkodzi (widełki) | przegrzanie generatora |
| Interwał = burza piaskowa | burza iskrowa ładuje kondensatory |
| Paliwo jako druga waluta | czyste paliwo w zaplombowanych kanistrach |
| Tereny odblokowane przez FTP | waty to ranga, słabszych nie wpuszcza się dalej |
| Bossowie w kampanii | Tłuści i ich machiny na galerach pedałowych |
| Przegrana nigdy nie kończy jazdy | kto stanie, ten ginie, więc zawsze jedzie się dalej |

## Kierunek graficzny: dzień, burza i noc

Obecna grafika jest za prosta i za bajkowa. Docelowy wygląd łączy trzy nastroje, które
zmieniają się w trakcie gry. Kamera patrzy z góry pod kątem.

| Nastrój | Kiedy | Wygląd |
|---|---|---|
| **Dzień – „Fury Road”** | spokojne odcinki, zbieranie łupu | ostry kontrast pomarańczowego piasku i turkusowych cieni, ściana burzy na horyzoncie, wielkie wybuchy |
| **Burza iskrowa** | interwały, ucieczki, bossowie | mrok, widoczność tylko w świetle reflektorów, błyskawice, sylwetki wrogów z czerwonymi światłami |
| **Noc – „Nocny konwój”** | część wypraw i etapów kampanii | światło księżyca, smugi pocisków, flary, ogień; walki najlepiej widoczne, dobre na OLED |

Wymagania wspólne:

- Pustynia, burza piaskowa, widok z góry, epickie walki.
- Koniec z gładkimi bryłami bez tekstur: prawdziwe tekstury, brud, rdza, kurz, mocne
  światło i cienie.
- Pojazd gracza zawsze czytelny z 3 m na telewizorze, także w burzy i w nocy.
- Trasa z zakrętami i prawdziwymi wzniesieniami w 3D (nie przez pochylanie świata).

Stan wdrożenia (2026-11-21): w grze są tekstury i brud na wszystkich powierzchniach,
zakręty, wzniesienia i wydmy, odcinki kanionu i otwartej pustyni, trzy pory z płynnymi
przejściami, burza z błyskawicami, reflektory i ściana burzy na horyzoncie. Pora jest
do wyboru w garażu: zmienna (start za dnia, w połowie zachód słońca, końcówka nocą),
dzień albo noc. Tarcza nie jest bańką pola siłowego: zablokowany atak to snop iskier.

Pojazdy: wrogowie to seryjne auta (sedan, SUV, pickup) przerobione na tarany – osmalony
lakier, kolczaste zderzaki, zaspawane okna. Buggy gracza ma koła terenowe, łataną blachę,
klatkę, generator z korbą i kierowcę, który naprawdę kręci nogami w tempie kadencji.

Do zrobienia: kampania nie steruje jeszcze porą dnia, ściana burzy na horyzoncie jest
płaska.

## Filary rozgrywki

### 1. Rozwój i ulepszanie pojazdu (największy nacisk)

Pojazd jest głównym bohaterem i główną nagrodą. Każda wyprawa ma przybliżać do kolejnej
części, a każda część ma być widoczna na pojeździe i odczuwalna w jeździe.

- Droga od jednoosiowego buggy do pustynnego pociągu pancernego: kolejne osie, przyczepy,
  wieżyczki, pancerz, zawieszenie, generator, kondensatory.
- Uwolnieni pedalarze jako załoga i źródło nowych możliwości.
- Części zdobywane nie tylko za złom: z napadów, od bossów i za wyniki w kampanii.
- Odblokowania powiązane z realną formą (FTP).

### 2. Decyzje na trasie i zwiad

Gracz wybiera, którędy jedzie i co atakuje, a z daleka widzi, czego się spodziewać.

- Około 500 m przed rozwidleniem cel jest widoczny na horyzoncie. Karta zwiadu pokazuje
  łup, obronę i koszt wysiłku liczony od FTP (np. „3 min na 105%”).
- Obronę widać też w świecie: flagi to gang, reflektory to wieże, dym to osada już
  splądrowana. Lornetka daje dokładniejszy podgląd.
- Wybór lewą gałką w strefie decyzji. Brak wyboru to jazda główną drogą bez kary.
- Napad ma fazy: podjazd pod ostrzałem, wyłom bramy, plądrowanie na czas, ucieczka.
  Przegrana to odparcie i utrata części łupu, nigdy śmierć.
- Bogatsze sterowanie: moduły na LB/RB (taran, dym, miny), zmiana broni, lornetka, hak.

### 3. Trening zawsze w 100%

Nadrzędna zasada z CLAUDE.md zostaje. W trybie treningowym o wysiłku decyduje plan, a gracz
wybiera tylko, co robi w tym czasie: napad wypada na interwał, objazd na regenerację.
W jeździe swobodnej napad to interwał, który gracz sam sobie wybiera. Cel mocy ma widełki:
za mało i za dużo to błąd.
