class_name UpgradeCatalog
extends RefCounted
## Katalog rozwoju pojazdu: podwozie (kolejne osie) i moduły. Każdy poziom widać na
## pojeździe. Koszty w złomie i paliwie; podwozie wymaga dodatkowo wypracowanych
## kilodżuli – realnej pracy na trenażerze, której nie da się kupić. Większe podwozie
## pozwala montować wyższe poziomy modułów. Efekty liczy Loadout. Czysta logika.

const CHASSIS := "chassis"
const GENERATOR := "generator"
const ARMOR := "armor"
const CAPACITOR := "capacitor"
const TURRET := "turret"
const RAM := "ram"
const SUSPENSION := "suspension"
const GRABBER := "grabber"

const ORDER: Array[String] = [CHASSIS, GENERATOR, ARMOR, CAPACITOR, TURRET, RAM, SUSPENSION, GRABBER]

## id -> definicja. costs[i] = koszt kupna poziomu i+1: [złom, paliwo].
const DEFS := {
	CHASSIS: {
		"name": "Podwozie",
		"desc": "Większa rama udźwignie mocniejsze moduły. Oprócz złomu wymaga wypracowanych kilodżuli – tego nie kupisz, to trzeba wyjeździć.",
		"levels": ["druga oś: moduły do poz. 2, generator do 3", "trzecia oś: wszystkie moduły do maksimum"],
		"costs": [[600, 4], [2000, 12]],
		"requires_kj": [400, 2000],
	},
	GENERATOR: {
		"name": "Generator",
		"desc": "Mocniejsze uzwojenia: ta sama moc z nóg daje większą prędkość.",
		"levels": ["+5% prędkości", "+10% prędkości", "+15% prędkości", "+20% prędkości", "+25% prędkości"],
		"costs": [[120, 0], [300, 2], [650, 4], [1200, 7], [2000, 10]],
	},
	ARMOR: {
		"name": "Pancerz",
		"desc": "Blachy na burtach: mniej złomu traconego przy zderzeniach i rabunkach.",
		"levels": ["-30% strat złomu", "-50% strat złomu", "-65% strat złomu"],
		"costs": [[150, 0], [450, 3], [1000, 6]],
	},
	CAPACITOR: {
		"name": "Kondensator",
		"desc": "Szybsze ładowanie tarczy, gdy trzymasz moc w widełkach.",
		"levels": ["+35% ładowania tarczy", "+70% ładowania tarczy", "+110% ładowania tarczy"],
		"costs": [[180, 1], [500, 4], [1100, 7]],
	},
	TURRET: {
		"name": "Wieżyczka",
		"desc": "Lepsze działko: szybszy ogień, potem podwójna lufa i ciężkie pociski.",
		"levels": ["+25% szybkości ognia", "podwójna lufa: +60% szybkości ognia", "ciężkie pociski: podwójne obrażenia"],
		"costs": [[200, 1], [550, 4], [1300, 8]],
	},
	RAM: {
		"name": "Taran",
		"desc": "Stalowy lemiesz z przodu: naładowany taran rozbija wrak, zamiast się o niego rozbić.",
		"levels": ["rozbija wrak bez straty złomu, raz na 30 s", "raz na 12 s i bez utraty prędkości"],
		"costs": [[220, 1], [700, 5]],
	},
	SUSPENSION: {
		"name": "Zawieszenie",
		"desc": "Resory i amortyzatory: szybsza zmiana pasa i łagodniejsze zderzenia.",
		"levels": ["+30% szybkości zmiany pasa", "+60% szybkości zmiany pasa, łagodniejsze zderzenia"],
		"costs": [[160, 0], [480, 3]],
	},
	GRABBER: {
		"name": "Chwytak",
		"desc": "Wysięgnik z hakiem zgarnia złom i paliwo leżące obok toru jazdy.",
		"levels": ["zbiera z szerszego pasa", "zbiera także z sąsiedniego pasa"],
		"costs": [[200, 1], [650, 4]],
	},
}


static func max_level(id: String) -> int:
	return (DEFS[id]["levels"] as Array).size()


static func display_name(id: String) -> String:
	return str(DEFS[id]["name"])


static func description(id: String) -> String:
	return str(DEFS[id]["desc"])


## Opis efektu danego poziomu (1..max).
static func level_effect(id: String, level: int) -> String:
	var levels: Array = DEFS[id]["levels"]
	if level < 1 or level > levels.size():
		return ""
	return str(levels[level - 1])


## Koszt kupna następnego poziomu: {"scrap": int, "fuel": int} albo {} gdy maks.
static func next_cost(id: String, current_level: int) -> Dictionary:
	var costs: Array = DEFS[id]["costs"]
	if current_level >= costs.size():
		return {}
	var c: Array = costs[current_level]
	return {"scrap": int(c[0]), "fuel": int(c[1])}


## Najwyższy poziom modułu, jaki udźwignie podwozie o danym poziomie (0 = buggy).
static func level_cap(id: String, chassis_level: int) -> int:
	if id == CHASSIS or chassis_level >= 2:
		return max_level(id)
	var base := 1 + chassis_level
	if id == GENERATOR:
		base += 1
	return mini(max_level(id), base)


## Praca (kJ) wymagana do kupna następnego poziomu; 0 = bez wymagania.
static func required_kj(id: String, current_level: int) -> int:
	var req: Array = DEFS[id].get("requires_kj", [])
	return int(req[current_level]) if current_level < req.size() else 0
