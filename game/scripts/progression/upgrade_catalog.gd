class_name UpgradeCatalog
extends RefCounted
## Katalog ulepszeń pojazdu (etap 3). Każde ulepszenie to moduł widoczny na buggy.
## Koszty w złomie i paliwie; efekty liczone przez Loadout. Czysta logika (bez sceny).

const GENERATOR := "generator"
const ARMOR := "armor"
const CAPACITOR := "capacitor"
const TURRET := "turret"
const TRAILER := "trailer"

const ORDER: Array[String] = [GENERATOR, ARMOR, CAPACITOR, TURRET, TRAILER]

## id -> definicja. costs[i] = koszt kupna poziomu i+1: [złom, paliwo].
const DEFS := {
	GENERATOR: {
		"name": "Generator",
		"desc": "Mocniejsze uzwojenia: ta sama moc z nóg daje większą prędkość.",
		"levels": ["+6% prędkości", "+12% prędkości", "+18% prędkości"],
		"costs": [[120, 0], [320, 2], [700, 5]],
	},
	ARMOR: {
		"name": "Pancerz",
		"desc": "Blachy na burtach: mniej złomu traconego przy zderzeniach i rabunkach.",
		"levels": ["-30% strat złomu", "-55% strat złomu"],
		"costs": [[150, 0], [450, 3]],
	},
	CAPACITOR: {
		"name": "Kondensator tarczy",
		"desc": "Szybsze ładowanie tarczy przy trzymaniu mocy.",
		"levels": ["+35% ładowania tarczy", "+70% ładowania tarczy"],
		"costs": [[180, 1], [500, 4]],
	},
	TURRET: {
		"name": "Wieżyczka",
		"desc": "Lepsze działko: szybszy ogień, na 2. poziomie podwójna lufa.",
		"levels": ["+25% szybkości ognia", "podwójna lufa: +60% szybkości ognia"],
		"costs": [[200, 1], [550, 4]],
	},
	TRAILER: {
		"name": "Przyczepa na złom",
		"desc": "Więcej miejsca na łup: część zebranego złomu liczy się podwójnie.",
		"levels": ["+15% złomu z drogi", "druga oś: +30% złomu z drogi"],
		"costs": [[250, 2], [600, 5]],
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
