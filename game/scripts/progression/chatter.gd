class_name Chatter
extends RefCounted
## Gadające głowy: postacie ze świata gry (docs/swiat.md) komentują to, co się dzieje.
## Tutaj jest tylko obsada i kwestie; okienko z popiersiem rysuje TalkingHead.
## Kwestie są krótkie – mają się dać przeczytać z 3 metrów w trakcie jazdy.

const BARON := "baron"
const SLAVE := "slave"
const MECH := "mech"
const PRIEST := "priest"
const RAIDER := "raider"

const CAST := {
	BARON: {"name": "BARON SMALEC", "role": "Tłusty. Sam nie pedałuje.", "color": Color("ff6a55")},
	SLAVE: {"name": "CHUDY", "role": "pedalarz z galery", "color": Color("ffd98a")},
	MECH: {"name": "ZĘBATKA", "role": "mechaniczka z twojej osady", "color": Color("5ff0e0")},
	PRIEST: {"name": "BRAT OBRÓT", "role": "Kościół Świętej Kadencji", "color": Color("d8c9ff")},
	RAIDER: {"name": "ISKRA", "role": "gang z pustkowi", "color": Color("ff9a4a")},
}

## zdarzenie -> lista [kto, kwestia]. Kolejne wywołania biorą kolejne kwestie.
const LINES := {
	"start": [
		[MECH, "Radio działa? Dobra. Kręć równo, ja pilnuję reszty."],
		[MECH, "Pamiętaj: kto stoi, tego zasypie piasek. Jedziemy."],
		[PRIEST, "Nowy dzień, nowe obroty. Niech kadencja będzie z tobą."],
	],
	"lore": [
		[MECH, "Żarłok zjadł ropę i baterie. Zostały nogi. Twoje."],
		[MECH, "Prądu nie da się schować. Co wykręcisz teraz, tym jedziesz teraz."],
		[PRIEST, "Świat stanął, bo ludzie przestali kręcić. Nie powtarzaj ich błędu."],
		[MECH, "Tu nikt nie pyta o imię. Pytają: ile ciągniesz?"],
		[BARON, "Podobno ktoś tu pedałuje SAM. Żałosne. Ja mam od tego ludzi."],
		[MECH, "Czystego paliwa się nie pali. No, chyba że w dopalaczu. Krótko."],
		[PRIEST, "Dziewięćdziesiąt obrotów, synu. Kto mieli, ten grzeszy."],
		[MECH, "Burza iskrowa ładuje kondensatory. Odważni wjeżdżają w nią celowo."],
		[SLAVE, "Na galerze Smalca kręci się po dwanaście godzin. Bez przerwy na wodę."],
		[MECH, "Większe FTP, większa ranga. Słabych nie wpuszczają za góry."],
		[BARON, "Każdy wat w tych pustkowiach jest mój. Twoje też będą."],
		[MECH, "Kilodżule to jedyna waluta, której nie da się ukraść."],
	],
	"crew": [
		[SLAVE, "Kręcimy z tobą, szefie. Lepszy wikt niż u Smalca."],
		[SLAVE, "Załoga na ławkach. Dokładamy swoje waty!"],
	],
	"convoy_sighted": [
		[MECH, "Konwój Smalca przed tobą! Dogoń go, zanim zniknie za wydmą."],
		[MECH, "Widzę galerę. Pełna klatka ludzi i kanistrów. Gazu!"],
	],
	"convoy_engaged": [
		[BARON, "Kto to się tam wlecze? Rozjechać go! GAZU, chudzielce!"],
		[BARON, "Znowu ty? Straż! Beczki na drogę!"],
	],
	"convoy_hint": [
		[MECH, "Nie strzelaj w klatkę! Zrównaj się ze sprzęgiem i wal w sworzeń."],
		[MECH, "Odetnij ogon, potem ciągnik. Galera zostanie nasza."],
	],
	"pace_fast": [
		[BARON, "GAZU! Kto zwolni, ten idzie na smar!"],
		[BARON, "Szybciej, patyki! Bat lubi leniwych!"],
		[SLAVE, "On nas pogania! Trzymaj się nas, nie odpuszczaj!"],
		[BARON, "Kręcić! Płacę wam przecież powietrzem!"],
	],
	"pace_slow": [
		[BARON, "PO HAMULCACH! Niech się wyłoży na naszym zderzaku!"],
		[SLAVE, "Hamujemy! Odpuść, bo nas miniesz!"],
		[BARON, "Stać! Niech przeleci bokiem jak głupi!"],
		[SLAVE, "Zwalniamy... nogi mi odpadają..."],
	],
	"window": [
		[MECH, "Jesteś przy sprzęgu! Teraz! Ogień!"],
		[SLAVE, "Tu, tu! W ten żółty sworzeń! Wal!"],
	],
	"hitch_rear": [
		[MECH, "Ogon odcięty! Miny z głowy. Teraz przedni sprzęg."],
		[BARON, "Moja straż! Kto mi odda moją straż?!"],
	],
	"hitch_front": [
		[SLAVE, "Jesteśmy wolni! HAMUJ, HAMUJ, zabierz nas!"],
		[BARON, "MOJA GALERA! Zapłacisz mi za każdy łańcuch!"],
	],
	"guard_destroyed": [
		[MECH, "Ogon w drzazgi! Trochę złomu się zmarnowało, ale ładnie."],
		[BARON, "To był mój ulubiony strażnik! Miałem drugiego. Też go rozbiłeś."],
	],
	"tractor_destroyed": [
		[BARON, "Mój tron! Mój ciągnik! Moje... aaa!"],
		[MECH, "Rozwaliłeś ciągnik Barona?! Łup razy półtora. Szalony jesteś."],
	],
	"cage_hit": [
		[SLAVE, "NIE W NAS, BARANIE! W sprzęg!"],
		[SLAVE, "Au! Celuj w sworzeń, nie w ludzi!"],
		[MECH, "Trafiasz w klatkę! Każdy ranny to wolne ręce mniej w załodze."],
	],
	"mine": [
		[BARON, "Beczka dla gościa! Smacznego!"],
		[RAIDER, "Łap prezent, pedałku!"],
	],
	"bump": [
		[BARON, "Ha! Pocałował mój zderzak!"],
		[MECH, "Nie wjeżdżaj w nich! Trzymaj boczny pas."],
	],
	"capture": [
		[MECH, "Galera stoi! Zwolnij poniżej 18 km/h i trzymaj się wagonu."],
		[SLAVE, "Podjedź bliżej! Skaczemy na pokład!"],
	],
	"captured": [
		[SLAVE, "Wolni! Od dziś kręcimy dla ciebie!"],
		[MECH, "Galera nasza. Ludzie na pokład, kanistry do skrzyni. Pięknie."],
		[SLAVE, "Myślałem, że umrę przy tej korbie. Dzięki, szefie."],
	],
	"captured_clean": [
		[MECH, "Czyste cięcie, oba sprzęgi! Chirurg, nie kierowca."],
	],
	"partial": [
		[MECH, "Przeleciałeś! Wagon został w tyle. Zgarnęliśmy tylko resztki."],
		[SLAVE, "Hej! Wracaj! ...Pojechał. No pięknie."],
	],
	"outrun": [
		[BARON, "Pa, pa, chudzielcu! Popracuj nad nogami!"],
		[MECH, "Uciekli. Za mało watów. Następnym razem dociśnij albo użyj dopalacza."],
	],
	"fortress": [
		[BARON, "Brama zamknięta! Wróć, jak urośniesz."],
		[MECH, "Dojechali do twierdzy. Za długo to trwało."],
	],
	"passed": [
		[MECH, "Wyprzedziłeś ich o kilometr. Konwój skręcił i tyle go widzieli."],
	],
	"escort": [
		[RAIDER, "Baron płaci za twój złom. Oddawaj!"],
		[RAIDER, "Zjedź z drogi, to konwój Smalca!"],
	],
	"raider": [
		[RAIDER, "Ładny wózek. Zaraz będzie mój."],
		[RAIDER, "Hej, pedałku! Zostaw trochę złomu dla Iskry!"],
		[RAIDER, "Mam cię na celowniku zderzaka!"],
	],
	"raider_destroyed": [
		[RAIDER, "Mój lakier! Dopiero co osmaliłem!"],
		[MECH, "Jeden mniej. Zbieraj to, co z niego wypadło."],
		[RAIDER, "Aaa! To nie fair, ty masz działko!"],
	],
	"ram_hit": [
		[RAIDER, "Dzięki za złom, frajerze!"],
		[MECH, "Zepchnął cię! Trzymaj moc, to tarcza się naładuje."],
	],
	"ram_blocked": [
		[RAIDER, "Co to za iskry?! Mój zderzak!"],
	],
	"boost": [
		[MECH, "Wtrysk! Trzymaj kierownicę!"],
		[SLAVE, "Czyste paliwo! Czuć je aż tutaj!"],
		[MECH, "Dopalacz poszedł. Wykorzystaj każdą sekundę."],
	],
	"boost_empty": [
		[MECH, "Dopalacz pusty. Zbierz kanister z drogi."],
	],
	"overheat": [
		[MECH, "Za mocno! Spalisz uzwojenia. Zejdź w widełki."],
		[PRIEST, "Pycha kroczy przed przegrzaniem, synu."],
	],
	"weak": [
		[MECH, "Zasilanie siada. Dociśnij do widełek."],
		[PRIEST, "Lenistwo to pierwszy stopień do postoju. A kto stoi..."],
	],
	"cadence_low": [
		[PRIEST, "Mielisz, synu. Zrzuć bieg i kręć szybciej."],
		[PRIEST, "Słyszę, jak cierpi twój łańcuch. Wyższa kadencja!"],
	],
	"cadence_good": [
		[PRIEST, "Dziewięćdziesiąt obrotów. Kościół patrzy z uznaniem."],
		[PRIEST, "Równo jak w zegarku. Błogosławiona noga."],
	],
	"raid_scout": [
		[MECH, "Osada przy zjeździe. Zerknij na kartę zwiadu i zdecyduj."],
	],
	"raid_start": [
		[MECH, "Wieże cię widzą! Zmieniaj pasy i wal w bramę."],
	],
	"raid_done": [
		[MECH, "Łup w magazynie. Będzie z czego spawać."],
	],
	"last_minute": [
		[MECH, "Ostatnia minuta! Zostaw na drodze wszystko, co masz."],
		[PRIEST, "Ostatnie obroty są najświętsze."],
	],
	"finish": [
		[MECH, "Dobra robota. Wracaj do garażu, coś ci przykręcę."],
	],
}

var _counts: Dictionary = {}


## Następna kwestia dla zdarzenia: {"who", "name", "role", "color", "text"} albo {} gdy brak.
func line(event: String) -> Dictionary:
	var pool: Array = LINES.get(event, [])
	if pool.is_empty():
		return {}
	var n: int = int(_counts.get(event, 0))
	_counts[event] = n + 1
	var entry: Array = pool[n % pool.size()]
	return make(str(entry[0]), str(entry[1]))


static func make(who: String, text: String) -> Dictionary:
	var c: Dictionary = CAST[who]
	return {"who": who, "name": c["name"], "role": c["role"], "color": c["color"], "text": text}


## Ile sekund kwestia ma wisieć na ekranie (czas na przeczytanie z daleka).
static func read_time_s(text: String) -> float:
	return clampf(2.2 + text.length() * 0.05, 3.0, 7.0)
