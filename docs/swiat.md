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
do nich w kilka godzin, więc nikt nie jeździ na nich na co dzień. Służą za walutę, a w walce
do miotaczy ognia, dopalaczy i innych jednorazowych zastosowań. Dopalacz to wtrysk
otwartego właśnie kanistra prosto do silnika: kilka sekund potężnej mocy i po paliwie.

### Burze iskrowe

Piasek niesie ładunek elektryczny. Burza iskrowa to ściana pyłu z wyładowaniami, przez
którą prawie nic nie widać. Kto przez nią przejedzie, ten ładuje kondensatory, dlatego
najodważniejsi wjeżdżają w burzę celowo. W grze burza to interwał, a obrona pojazdu bierze się
z trzymania mocy.

### Kościół Świętej Kadencji

Fanatycy wierzą, że świat skończył się, bo ludzkość przestała kręcić. Jeżdżą na stałym
90 obr./min, noszą liczniki kadencji jak relikwie i gardzą każdym, kto „mieli”.
Bywają sojusznikami albo wrogami, zależnie od tego, jak gracz jeździ.

### Wyprawa: z osady do osady

Nie ma „mety”. Każda jazda to kurs między osadami, a jej długość wynika z treningu:

- **Jazda swobodna** to wypad po złom w oknie między burzami. Okno trwa tyle, ile gracz
  wybrał w garażu (15–60 min).
- **Trening** to kurs z rozkładem: plan (interwały, regeneracja) jest rozkładem jazdy,
  którego trzeba się trzymać. Interwał to burza iskrowa, regeneracja to spokojny odcinek.
- W obu przypadkach wyprawa zaczyna się wyjazdem przez bramę własnej osady (Zębatka żegna
  przez radio), a pod koniec czasu na horyzoncie pojawia się osada docelowa. Stoi tam,
  dokąd gracz dojedzie w chwili, gdy czas się skończy, więc każdy trening kończy się
  wjazdem na plac, niezależnie od tempa. Ludzie machają, płoną ogniska, łup idzie do
  magazynu.
- Przerwanie jazdy to „powrót przed czasem”: zebrany łup też się zapisuje.


Słaby jeździ sam i oddaje złom każdemu, kto go dogoni. Żeby to zmienić, trzeba trzech
rzeczy naraz, i wszystkie biorą się z nóg:

- **Ranga (FTP).** Waty to status. Wyższe FTP to wyższa ranga (Piechur → Kręciciel →
  Ciągnik → Lokomotywa → Turbina → Reaktor → Legenda Pustkowi), wstęp na dalsze tereny
  i szacunek osady. FTP nie da się kupić za złom, trzeba je wyjeździć.
- **Praca (kilodżule).** Większego podwozia nie udźwignie ktoś, kto mało jeździ: rama
  wymaga wypracowanych kilodżuli. To jedyna waluta, której nie da się ukraść.
- **Ludzie.** Każda rozbita galera to uwolnieni pedalarze. Siadają na ławkach twojego
  pojazdu i dokładają swoje waty. Baron Smalec ma setki skutych nóg, ty masz na razie
  dwie. Każda wyprawa zmienia ten rachunek.

Cel na horyzoncie: zebrać załogę i machinę, przed którą Tłuści zamykają bramy, i rozbić
twierdzę Barona.

### Postacie (gadające głowy)

Zdarzenia w grze komentują postacie w okienku z popiersiem. Mówią krótko, żeby dało się
to przeczytać z 3 metrów. Kwestie: `game/scripts/progression/chatter.gd`.

| Postać | Kim jest | Kiedy się odzywa |
|---|---|---|
| **Baron Smalec** | Tłusty, watażka. Sam nie pedałuje, jeździ na tronie na ciągniku. | pogania i hamuje konwój, drwi, rozpacza po stracie galery |
| **Chudy** | pedalarz przykuty do korby na galerze, głos całej klatki | ostrzega przed tempem, krzyczy, gdy strzelasz w klatkę, woła o przesiadkę |
| **Zębatka** | mechaniczka z osady gracza, głos w radiu | podpowiada taktykę, komentuje dopalacz i widełki, opowiada o świecie |
| **Brat Obrót** | kaznodzieja Kościoła Świętej Kadencji | ocenia kadencję: gani mielenie, chwali równe 90 obr./min |
| **Iskra** | gangster z pustkowi | zaczepia, gdy nadjeżdża gang albo eskorta, lamentuje po rozbiciu |

### Jak fabuła tłumaczy mechaniki

| Mechanika | Wyjaśnienie w świecie |
|---|---|
| Moc z nóg = prędkość | jedyny działający napęd, generator pedałowy |
| Obrona zależna od trzymania mocy | kondensatory ładowane równą pracą generatora; naładowane oddają wyładowanie, które odrzuca napastnika i detonuje miny przed maską |
| Za duża moc szkodzi (widełki) | przegrzanie generatora |
| Interwał = burza piaskowa | burza iskrowa ładuje kondensatory |
| Paliwo jako druga waluta | czyste paliwo w zaplombowanych kanistrach |
| Tereny odblokowane przez FTP | waty to ranga, słabszych nie wpuszcza się dalej |
| Bossowie w kampanii | Tłuści i ich machiny na galerach pedałowych; interwał w widełkach = obrażenia |
| Test FTP ustawia rangę | Rytuał Progu: publiczny test narastający na koniec kampanii |
| Przegrana nigdy nie kończy jazdy | kto stanie, ten ginie, więc zawsze jedzie się dalej |
| Wyprawa na czas, bez mety | okno między burzami albo rozkład kursu; na końcu czeka osada |
| Dopalacz (chwilowy zastrzyk mocy) | wtrysk świeżo otwartego kanistra czystego paliwa |
| Załoga jako stały mnożnik mocy | uwolnieni pedalarze kręcą razem z tobą |
| Konwój na zmianę ucieka i hamuje | Baron pogania skutych pedalarzy albo każe im stanąć, żebyś się wyłożył |
| Trening liczy tylko moc z nóg | paliwo i załoga pomagają pojazdowi, nie twojej formie |

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
- Droga nie może być jednym asfaltem: nawierzchnia zmienia się co odcinek (asfalt, szuter
  z koleinami, betonowe płyty, stalowe maty).

Stan wdrożenia (2026-11-21): w grze są tekstury i brud na wszystkich powierzchniach,
zakręty, wzniesienia i wydmy, odcinki kanionu i otwartej pustyni, trzy pory z płynnymi
przejściami, burza z błyskawicami, reflektory i ściana burzy na horyzoncie. Pora jest
do wyboru w garażu: zmienna (start za dnia, w połowie zachód słońca, końcówka nocą),
dzień albo noc. Nie ma „tarczy” ani pól siłowych: obroną są kondensatory, a odparty atak to wyładowanie i snop iskier.

Pojazdy: wrogowie to seryjne auta (sedan, SUV, pickup) przerobione na tarany – osmalony
lakier, kolczaste zderzaki, zaspawane okna. Buggy gracza ma koła terenowe, łataną blachę,
klatkę, generator z korbą i kierowcę, który naprawdę kręci nogami w tempie kadencji.

Do zrobienia: kampania nie steruje jeszcze porą dnia, ściana burzy na horyzoncie jest
płaska.

## Filary rozgrywki

### 1. Rozwój i ulepszanie pojazdu (największy nacisk)

Pojazd jest głównym bohaterem i główną nagrodą. Każda wyprawa ma przybliżać do kolejnej
części, a każda część ma być widoczna na pojeździe i odczuwalna w jeździe.

- Droga od jednoosiowego buggy do pustynnej machiny pancernej: kolejne osie, wieżyczki,
  pancerz, zawieszenie, generator, kondensatory, dopalacz. Przyczepy nie ciąga się na
  stałe: to tymczasowe zadanie („dowieź łup”) po napadzie.
- Stan wdrożenia (2026-11-21): podwozie w trzech stopniach (buggy, druga oś, trzecia oś)
  i 8 modułów po 2–5 poziomów; podwozie wymaga łącznej pracy w kJ (400 i 2000) i
  ogranicza poziomy modułów. Jest układ napędowy: moc na kołach = moc z nóg ×
  akceleratory (generator, załoga) × dopalacz, a załoga rośnie z każdą przejętą galerą
  (ławki: 2, 4, 6 według podwozia). Do zrobienia: załoga widoczna na pojeździe, części
  z napadów i od bossów.
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
- Kierowanie jest płynne: lewa gałka przesuwa pojazd po całej szerokości jezdni, a
  wspomaganie po puszczeniu gałki dociąga do najbliższego pasa i omija wrak tuż przed
  maską. Krzyżak skacze o cały pas. Pasy zostają jako siatka dla przeszkód i wrogów.

Stan wdrożenia (2026-11-21): zwiad z kartą, zjazd skrajnym pasem, trzy stopnie osad,
ostrzał z wież, brama, plądrowanie i dowiezienie łupu na doczepionej przyczepie – w jeździe
swobodnej. Do zrobienia: lornetka, napady w trybie treningowym.

### 3. Konwoje: walka o tempo i o ludzi

Konwój to najważniejsza walka w grze i jedyna, w której wygrywa się głową i nogami naraz.

- Kolumna jedzie środkowym pasem: **ogon** ze strażnikiem i zrzutnią min, **galera**
  (klatka ze skutymi pedalarzami, którzy napędzają całość, i kanistry czystego paliwa),
  **ciągnik** z tronem Barona. Wagony łączą sprzęgi.
- Celem jest **odczepić galerę**, nie rozstrzelać wszystko. Sprzęg da się trafić tylko
  z bocznego pasa, tuż zza niego. Kto strzela w klatkę, ten rani ludzi i uwalnia mniej.
- **Tempo**: konwój jedzie rytmem liczonym od FTP gracza. Baron na zmianę pogania
  (ok. 100% FTP) i każe hamować (ok. 55% FTP). Żeby utrzymać się przy sprzęgu, trzeba
  naprawdę przyspieszać i zwalniać. Za mało mocy i konwój ucieka. Akceleratory i dopalacz
  zmniejszają waty potrzebne do trzymania tempa.
- **Trzy drogi**: chirurg (tylny sprzęg, potem przedni: pełny łup, jeden uwolniony
  więcej), na skróty (tylko przedni: szybciej, ale ogon zabiera 30% łupu) i rzeźnik
  (rozbić ciągnik: łup ×1,5).
- **Przesiadka**: odcięty wagon wytraca prędkość. Trzeba zwolnić poniżej 18 km/h i zostać
  przy nim kilka sekund. Kto przeleci, zgarnia resztki i nikogo nie uwalnia.
- Zagrożenia: miny z ogona (unik zmianą pasa), wozy eskorty od zewnętrznej strony, zderzak
  kolumny, limit czasu (konwój dojeżdża do twierdzy). Przegrana to utracony łup, nigdy
  koniec jazdy.
- Poziom konwoju rośnie z podwoziem gracza (Cysterna Tłustych, Galera Smalca, Skarbiec
  Barona), a drugi konwój wyprawy jest o stopień cięższy.

Stan wdrożenia (2026-11-21): wszystko powyżej działa w jeździe swobodnej. Do zrobienia:
konwoje jako interwały w trybie treningowym, bossowie kampanii, załoga widoczna na pojeździe.

### 4. Co trzyma przy grze

Gra ma wciągać, a nie tylko towarzyszyć pedałowaniu. Mechanizmy, które za to odpowiadają:

| Mechanizm | Jak działa w grze |
|---|---|
| Zawsze widoczny najbliższy cel | trzy zlecenia na wyprawę z postępem w HUD, nagroda co kilka minut |
| Rosnąca stawka | passa: czysta jazda podbija mnożnik złomu do ×2, wpadka go zeruje |
| Niespodzianka | skrzynie z losową nagrodą |
| Popis umiejętności | unik o włos, celowanie w sprzęg, odcinanie konwoju |
| Łup trzeba zdobyć | złom leży w slalomie, przy krawędzi i w przesmykach obok wraków; wypada z rozbitych wraków i wrogów; zasięg zbierania jest wąski |
| Bicie własnych wyników | rekordy mocy 20 s / 1 min / 5 min / 20 min, komunikat na żywo |
| Powód, żeby wrócić jutro | cel tygodnia w TSS i dni z rzędu w garażu, załoga i kilodżule do podwozia |
| Rytm napięcia i oddechu | potyczki, wyzwania, napady, konwoje na zmianę ze spokojnym zbieraniem |
| Odpowiedź na każdy ruch | dźwięki (nuta rośnie z passą), wstrząsy kamery, komentarze postaci |

Interfejs: stalowe płyty ze ściętymi rogami i pomarańczowy akcent. HUD to deska rozdzielcza
na dole (prędkość, moc, strefy Z1–Z7, wskaźnik widełek, zasilanie, kondensatory), a góra ekranu
zostaje wolna, żeby było widać drogę przed pojazdem.

### 5. Kampanie: droga do twierdzy Barona

Kampania to czterotygodniowy blok treningowy opowiedziany jako pościg za Baronem Smalcem.

- Trzy kampanie z prawdziwych, sprawdzonych protokołów: **Baza Pustkowi** (wytrzymałość
  i tempo), **Droga do Progu** (słodki punkt, nad-i-pod progiem, 2×20 na progu), **Kuźnia
  VO2** (5×3, 4×4, 4×8 Seilera, 30/15 Rønnestada). Po trzy sesje w tygodniu, w tym lekkie
  dni wytrzymałości.
- Każda sesja ma wariant pełny (35–72 min) i krótki (26–40 min): te same intensywności
  i układ interwałów, mniejsza objętość. Postęp kampanii jest wspólny.
- Sesje jedzie się po kolei; każda ma krótkie wprowadzenie Zębatki. Mapa kampanii w garażu
  pokazuje, co zaliczone, co następne i gdzie czekają bossowie.
- **Bossowie** (dwóch na kampanię) to machiny Barona. Walka nie dokłada żadnego wysiłku
  ponad plan: ciężki interwał to natarcie, moc w widełkach to obrażenia, regeneracja to
  chwila, gdy machina odjeżdża. Wygrywa ten, kto zrobi trening tak, jak jest zapisany.
  Nagroda: złom, paliwo i uwolnieni pedalarze. Niedobity boss ucieka ranny.
- **Rytuał Progu** zamyka każdą kampanię: test narastający na oczach osady. Wynik ustawia
  nowe FTP i rangę, a od FTP zależą cele wszystkich kolejnych sesji – ta sama kampania
  przejechana drugi raz jest odpowiednio cięższa.

Stan wdrożenia (2026-11-21): wszystko powyżej działa. Do zrobienia: napady i konwoje
jako interwały, osobna scena twierdzy na finał.

### 6. Trening zawsze w 100%

Nadrzędna zasada z CLAUDE.md zostaje. W trybie treningowym o wysiłku decyduje plan, a gracz
wybiera tylko, co robi w tym czasie: napad wypada na interwał, objazd na regenerację.
W jeździe swobodnej napad to interwał, który gracz sam sobie wybiera. Cel mocy ma widełki:
za mało i za dużo to błąd.

Gra pokazuje wartości treningowe wprost: procent FTP i strefę mocy w HUD, NP, IF, TSS, kJ
i czas w strefach w podsumowaniu, rangę z FTP i trening z ostatnich 7 dni w garażu. Liczą
się zawsze z mocy z nóg, bez akceleratorów i dopalacza.
