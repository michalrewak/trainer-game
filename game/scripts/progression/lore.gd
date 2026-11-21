class_name Lore
extends RefCounted
## Świat w pigułce (docs/swiat.md): rangi kolarzy pustkowi liczone z FTP oraz hasła,
## które przypominają, po co się rozwijać. W tym świecie waty to pozycja społeczna:
## kto ciągnie więcej, tego wpuszczą dalej i temu oddadzą cięższą maszynę.

## Rangi: [próg FTP w watach, nazwa, opis].
const RANKS: Array[Array] = [
	[0, "Piechur", "Jeszcze nikt nie wie, ile ciągniesz."],
	[120, "Kręciciel", "Utrzymasz własny buggy w ruchu."],
	[160, "Ciągnik", "Uciągniesz ładunek, wezmą cię do konwoju."],
	[200, "Lokomotywa", "Za tobą jadą inni."],
	[240, "Turbina", "Burza iskrowa to dla ciebie ładowarka."],
	[280, "Reaktor", "Tłuści zaczynają pytać o twoje imię."],
	[320, "Legenda Pustkowi", "O takich śpiewa Kościół Świętej Kadencji."],
]

const SLOGANS: Array[String] = [
	"Kto nie kręci, ten stoi. Kto stoi, tego zasypie piasek.",
	"Nikt nie pyta o imię. Pytają: ile ciągniesz?",
	"FTP nie kupisz za złom. Trzeba je wyjeździć.",
	"Tłuści nie pedałują. Dlatego kiedyś przegrają.",
	"Równa moc to pełna tarcza. Szarpanie to przegrzany generator.",
	"Burza ładuje kondensatory tym, którzy trzymają moc.",
	"Każdy kilodżul to krok dalej od Żarłoka.",
	"Większa maszyna potrzebuje mocniejszych nóg.",
	"Regeneracja to też trening. Zbieraj złom i oddychaj.",
	"Dziś interwał, jutro o jedną osadę dalej.",
	"Żarłok zjada paliwo. Nóg nie zje.",
	"Próg to nie ściana. To brama, którą się przesuwa.",
]


## Ranga dla danego FTP: {"name", "desc", "next_name", "next_at"} (next_at = 0 na szczycie).
static func rank(ftp_w: float) -> Dictionary:
	var index := 0
	for i in RANKS.size():
		if ftp_w >= float(RANKS[i][0]):
			index = i
	var out := {"name": str(RANKS[index][1]), "desc": str(RANKS[index][2]), "next_name": "", "next_at": 0}
	if index + 1 < RANKS.size():
		out["next_name"] = str(RANKS[index + 1][1])
		out["next_at"] = int(RANKS[index + 1][0])
	return out


## Hasło o danym numerze (zawija się) – np. numer wyprawy albo dzień roku.
static func slogan(index: int) -> String:
	return SLOGANS[posmod(index, SLOGANS.size())]
