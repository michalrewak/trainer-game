# Gra na trenażer rowerowy - analiza rynku i kierunek produktu

## 1. Czy taki rynek już istnieje?

Tak, rynek istnieje, ale jest zagospodarowany glownie przez aplikacje treningowe i symulatory jazdy, a nie przez "gre" w klasycznym sensie.

Przyklady:

- Zwift - najbardziej znany wirtualny swiat do jazdy na trenażerze; nacisk na trening, wyscigi, avatar i elementy MMO.
- ROUVY - jazda po rzeczywistych trasach wideo z automatyczna zmiana oporu; bardziej realizm i trening niz gra.
- FulGaz - podobnie, nacisk na realistyczne trasy i odwzorowanie jazdy.
- Wahoo SYSTM / podobne platformy - bardziej treningi i plany niz gameplay.
- Istnialy tez projekty bardziej growe lub fitness-gamingowe, ale ten segment jest wyraznie mniejszy niz segment treningowy.

Wniosek:

- Jest popyt na jazde indoor z gamifikacja.
- Rynek jest potwierdzony.
- Nadal jest miejsce na produkt bardziej "game-first" niz "training-first".
- Najwieksza luka wydaje sie w grach, ktore maja mocna petle progresji, eksploracji i zbierania zasobow, a nie tylko trasy, wyscigi lub workouty.

## 2. Proponowany kierunek produktu

### Etap 1: POC na PC

To ma sens z kilku powodow:

- latwiejsze podlaczenie urzadzen przez ANT+ i Bluetooth,
- szybsze debugowanie sprzetu,
- latwiejszy development gameplayu i UI,
- prostsze testy z roznymi typami trenażerow i czujnikow.

Na etapie POC warto zalozyc:

- platforma: PC,
- wejscie sprzetowe: ANT+ jako priorytet, opcjonalnie Bluetooth,
- minimalny gameplay: poruszanie, tempo zalezne od mocy/kadencji, podstawowa progresja,
- zapis sesji i prosty system ulepszen.

### Etap 2: iOS / Android

Docelowo mobile ma duzy sens, ale warto traktowac to jako drugi etap, bo:

- parowanie urzadzen i ograniczenia systemowe sa trudniejsze,
- trzeba rozwiazac roznice miedzy ANT+ i Bluetooth na roznych platformach,
- UX mobilny musi byc uproszczony,
- trzeba przemyslec czy telefon jest ekranem glownym, czy companion appka.

Najbardziej realne podejscie:

- najpierw PC jako glowna gra,
- potem iOS/Android jako port albo companion app,
- ewentualnie mobile jako prostsza wersja gry o mniejszej zlozonosci sterowania.

## 3. Propozycje, co mozna zrobic

Najciekawszy kierunek to nie "kolejny Zwift", tylko gra wykorzystujaca wysilek fizyczny jako paliwo do eksploracji i rozwoju.

Mozliwe kierunki:

### A. Survival / exploration

- gracz jedzie przez swiat,
- zbiera zasoby,
- wraca do bazy,
- ulepsza pojazd,
- odblokowuje nowe biom y i zagrozenia,
- kazda sesja daje realny postep.

### B. Transport / economy

- gracz przewozi ladunki,
- energia jazdy zasila pojazd,
- trzeba planowac trase, zuzycie energii i ladownosc,
- ulepszenia zwiekszaja zasieg, predkosc i efektywnosc.

### C. Roguelite expedition

- jedna sesja = jedna wyprawa,
- po drodze losowe zdarzenia, znajdzki, awarie, decyzje,
- po powrocie meta-progresja,
- dobra petla dla krotszych treningow 20-40 min.

### D. Builder / colony support

- krecenie generuje energie dla bazy,
- podczas wypraw zdobywasz materialy,
- rozbudowujesz osade, statek, podwodna stacje lub kopalnie,
- postep jest bardzo czytelny i motywujacy.

## 4. Pomysl nr 1: pojazd na pustyni

### Core fantasy

Gracz porusza sie pojazdem po pustyni. Krecenie na trenażerze produkuje energie do jazdy. W trakcie wyprawy zbiera zasoby, omija zagrozenia i wraca do bazy, aby rozbudowac pojazd oraz infrastrukture.

### Petla gry

1. Start w bazie.
2. Wyjazd na wyprawe.
3. Krecenie = ruch do przodu i produkcja energii.
4. Zbieranie surowcow i odkrywanie punktow na mapie.
5. Ryzyko: burze, przegrzanie, brak energii, uszkodzenia.
6. Powrot do bazy.
7. Ulepszenia pojazdu i odblokowanie kolejnych stref.

### Co daje krecenie na trenażerze

- kadencja lub moc przeklada sie na predkosc jazdy,
- sprint moze dawac chwilowy boost,
- rowna jazda moze byc premiowana efektywnoscia,
- zbyt niska moc moze oznaczac zatrzymanie albo spadek napiecia systemu,
- dluzsza regularna jazda moze ladowac dodatkowe systemy pojazdu.

### Ulepszenia pojazdu

- akumulator / magazyn energii,
- wydajnosc napedu,
- pancerz,
- chlodzenie,
- radar / skaner zasobow,
- lepszy chwyt na podlozu,
- wiekszy ladunek,
- autopilot lub stabilizacja jazdy.

## 5. Alternatywy dla pustyni

Ten sam model gameplayu mozna osadzic w innych swiatach.

### Ocean

- pojazd: lodz, poduszkowiec, lodz podwodna albo mini-okret,
- energia z pedalowania napedza silnik i systemy,
- zasoby: wraki, plankton energetyczny, minera ly z dna,
- zagrozenia: sztormy, prady, potwory, uszkodzenia kadluba.

### Kosmos

- pojazd: ladowik, lowca zlomu, statek zwiadowczy,
- energia z pedalowania zasila naped, tarcze, skanery,
- zasoby: wraki, ruda, artefakty,
- zagrozenia: promieniowanie, mikrometeoryty, awarie systemow.

### Podziemia

- pojazd: wiertnica, crawler, wagonik ekspedycyjny,
- energia z pedalowania napedza wiercenie i transport,
- zasoby: rudy, kryszta ly, starozytna technologia,
- zagrozenia: zawaly, gaz, lawa, agresywna fauna.

### Inna planeta

- najlepszy kompromis miedzy swoboda artystyczna a czytelnoscia,
- mozna laczyc survival, eksploracje i science fiction,
- latwiej uzasadnic dowolne zasoby, biome i zagrozenia.

Wniosek:

- pustynia jest najprostsza do zrobienia w POC,
- ocean i kosmos sa bardzo atrakcyjne fantasy,
- inna planeta daje najwieksza swobode designerska.

## 6. Jak sterowac kierunkiem jazdy?

To jest jedna z najwazniejszych decyzji, bo na trenażerze gracz nie skreca fizycznie kierownica w naturalny sposob.

Mozliwe rozwiazania:

### Opcja 1. Tor jazdy prawie automatyczny

- gracz glownie jedzie do przodu,
- na rozgalezieniach wybiera kierunek przyciskiem,
- reszta sterowania jest uproszczona.

Zalety:

- najprostsze do POC,
- najmniej frustracji,
- dobrze pasuje do workoutu.

Wady:

- mniejsza swoboda,
- bardziej przypomina interactive route niz pelna gre.

### Opcja 2. Sterowanie klawiatura / padem

- pedalowanie odpowiada za naped,
- klawiatura albo pad odpowiadaja za kierunek,
- mozna tez dodac hamowanie lub akcje kontekstowe.

Zalety:

- najlatwiejsze technicznie,
- duza kontrola,
- dobre na PC.

Wady:

- czesc graczy moze nie chciec uzywac dodatkowego sterowania podczas treningu.

### Opcja 3. Sterowanie cialem lub balansem

- wykrywanie skretu przez dodatkowy kontroler,
- ewentualnie czujnik na kierownicy albo specjalne akcesorium.

Zalety:

- najbardziej imersyjne.

Wady:

- trudne sprzetowo,
- slabe do POC,
- duzo ryzyka integracyjnego.

### Opcja 4. Decyzje zamiast precyzyjnego skretu

- zamiast ciagle skrecac, gracz wybiera: lewo / prawo / ryzyko / bezpieczna trasa,
- decyzje pojawiaja sie co kilka-kilkanascie sekund.

Zalety:

- bardzo dobre do treningu,
- latwo zrobic czytelna petle gry,
- nie odrywa mocno od pedalowania.

Wady:

- mniej zręcznosciowy charakter.

### Rekomendacja na POC

Najlepszy start:

- pedalowanie = naped,
- klawiatura lub pad = kierunek,
- alternatywnie bardzo uproszczone wybory na rozwidleniach.

To minimalizuje ryzyko i pozwala szybko sprawdzic, czy petla gry dziala.

## 7. O czym trzeba pomyslec?

### A. Sprzet i integracje

- ANT+ czy Bluetooth czy oba od poczatku,
- jakie typy urzadzen wspierasz: smart trainer, czujnik kadencji, miernik mocy,
- co robisz, gdy gracz ma tylko czujnik kadencji bez mocy,
- jak liczysz predkosc w grze na podstawie danych ze sprzetu,
- jak obslugujesz rozlaczenia i bledy transmisji.

### B. Mapping danych z trenażera na gameplay

- czy liczy sie kadencja, moc, tetno, czy kombinacja,
- jak uniknac sytuacji, w ktorej najmocniejsi gracze zawsze wygrywaja,
- jak zrobic balans miedzy fitnessem a funem,
- czy sprint ma byc akcja specjalna,
- jak nagradzac regularnosc zamiast tylko maksymalnej mocy.

### C. Bezpieczenstwo i ergonomia

- gracz jest zmeczony i spocony, wiec UI musi byc bardzo czytelne,
- nie mozna wymagac zbyt wielu szybkich interakcji,
- wazny jest duzy tekst, prosty HUD i mocny kontrast,
- sesje powinny miec sens przy 15, 30 i 45 minutach.

### D. Projekt sesji

- czy gra ma byc endless, run-based czy mission-based,
- jak wyglada porazka,
- czy zawsze da sie wrocic z sesji z jakims postepem,
- jak utrzymac motywacje przez wiele treningow.

### E. Meta-progresja

- odblokowania,
- nowe strefy,
- nowe klasy pojazdu,
- crafting,
- baza,
- drzewko technologii,
- wydarzenia dzienne i tygodniowe.

### F. Model produktu

- jednorazowy zakup czy subskrypcja,
- solo czy tez wyzwania asynchroniczne,
- czy chcesz elementy spolecznosciowe,
- czy gra ma byc bardziej indie premium, czy live product.

### G. Produkcja i scope

- POC musi byc bardzo male,
- jedna mapa,
- jeden pojazd,
- jeden podstawowy loop,
- jeden sposob sterowania,
- prosty styl graficzny,
- najwazniejsze jest sprawdzenie: czy pedalowanie + progresja daje frajde.

## 8. Najbardziej sensowna wersja POC

Jesli celem jest szybkie sprawdzenie pomyslu, to sugeruje taki zakres:

- platforma: PC,
- integracja: ANT+ dla kadencji i/lub mocy,
- setting: pustynia albo obca planeta,
- sterowanie: pedalowanie + klawiatura/pad,
- gameplay: 15-20 minutowa wyprawa po zasoby,
- meta: 3-5 ulepszen pojazdu,
- cel testu: czy gracze chca wracac na kolejna sesje.

## 9. Ocena pomyslu

Pomysl jest sensowny, bo:

- odchodzi od zatloczonej kategorii realistycznych tras,
- daje mocny powod, zeby "krecic jeszcze chwile",
- dobrze laczy wysilek fizyczny z czytelna nagroda w grze,
- ma potencjal na bardzo wyrazne pozycjonowanie.

Najwieksze ryzyko:

- sterowanie i ergonomia,
- zly balans miedzy treningiem a zabawa,
- zbyt duzy scope na starcie.

Najwieksza szansa:

- stworzenie pierwszej naprawde game-first gry na trenażer, a nie kolejnej aplikacji treningowej z lekkimi elementami gry.

## 10. Co warto doprecyzowac dalej

Kolejne pytania produktowe:

- kto jest glownym graczem: cyclist hobby, gamer fitness, czy oba segmenty,
- czy gra ma byc bardziej chill exploration czy bardziej survival,
- czy jazda ma byc ciagla, czy podzielona na segmenty decyzji,
- czy celem POC jest fun, retencja, czy wiarygodnosc technologiczna ANT+,
- jaki silnik wybrac na start: Unity, Godot czy Unreal.
