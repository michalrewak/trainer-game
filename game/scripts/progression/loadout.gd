class_name Loadout
extends RefCounted
## Zestaw zamontowanych modułów i wynikające z nich parametry jazdy.
## Jedno miejsce, które tłumaczy poziomy ulepszeń na liczby w symulacji.

var levels: Dictionary = {}


func _init(p_levels: Dictionary = {}) -> void:
	for id in UpgradeCatalog.ORDER:
		levels[id] = clampi(int(p_levels.get(id, 0)), 0, UpgradeCatalog.max_level(id))


func level(id: String) -> int:
	return int(levels.get(id, 0))


func engine_multiplier() -> float:
	return 1.0 + 0.06 * level(UpgradeCatalog.GENERATOR)


## Mnożnik strat złomu (zderzenia z wrakami i rabunki).
func scrap_loss_factor() -> float:
	match level(UpgradeCatalog.ARMOR):
		1:
			return 0.7
		2:
			return 0.45
	return 1.0


## Utrata prędkości przy zderzeniu: pancerz trochę łagodzi uderzenie.
func impact_speed_factor() -> float:
	return 0.35 + 0.1 * level(UpgradeCatalog.ARMOR)


func shield_regen_multiplier() -> float:
	return 1.0 + 0.35 * level(UpgradeCatalog.CAPACITOR)


func fire_rate_multiplier() -> float:
	match level(UpgradeCatalog.TURRET):
		1:
			return 1.25
		2:
			return 1.6
	return 1.0


func twin_barrels() -> bool:
	return level(UpgradeCatalog.TURRET) >= 2


## Premia za złom zebrany z drogi (część sztuk liczy się podwójnie).
func scrap_bonus() -> float:
	return 0.15 * level(UpgradeCatalog.TRAILER)


## Zapisuje parametry do świeżej symulacji wyprawy.
func apply_to(sim: RunSimulation) -> void:
	sim.vehicle.engine_multiplier = engine_multiplier()
	sim.impact_speed_factor = impact_speed_factor()
	sim.expedition.scrap_loss_factor = scrap_loss_factor()
	sim.expedition.scrap_bonus = scrap_bonus()
	sim.combat.shield_regen_multiplier = shield_regen_multiplier()
	sim.combat.fire_rate_multiplier = fire_rate_multiplier()
