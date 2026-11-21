class_name Loadout
extends RefCounted
## Zestaw zamontowanych modułów i wynikające z nich parametry jazdy.
## Jedno miejsce, które tłumaczy poziomy ulepszeń na liczby w symulacji.

var levels: Dictionary = {}
## Uwolnieni pedalarze w magazynie; na pokład wchodzi tylu, ile jest ławek.
var crew := 0


func _init(p_levels: Dictionary = {}) -> void:
	for id in UpgradeCatalog.ORDER:
		levels[id] = clampi(int(p_levels.get(id, 0)), 0, UpgradeCatalog.max_level(id))


func level(id: String) -> int:
	return int(levels.get(id, 0))


func engine_multiplier() -> float:
	return 1.0 + 0.05 * level(UpgradeCatalog.GENERATOR)


## Ławki dla załogi: buggy zabiera dwóch pedalarzy, każda kolejna oś – dwóch więcej.
func crew_seats() -> int:
	return 2 + 2 * level(UpgradeCatalog.CHASSIS)


func active_crew() -> int:
	return clampi(crew, 0, crew_seats())


## Dopalacz: liczba ładunków, zysk mocy i czas działania.
func boost_charges() -> int:
	return [1, 2, 3, 4][level(UpgradeCatalog.BOOSTER)]


func boost_gain() -> float:
	return [0.25, 0.35, 0.45, 0.55][level(UpgradeCatalog.BOOSTER)]


func boost_duration_s() -> float:
	return [6.0, 8.0, 9.0, 10.0][level(UpgradeCatalog.BOOSTER)]


## Stały mnożnik mocy na kołach: generator × załoga (bez dopalacza).
func accelerator_multiplier() -> float:
	return engine_multiplier() * (1.0 + PowerTrain.CREW_BONUS_EACH * active_crew())


## Mnożnik strat złomu (zderzenia z wrakami i rabunki).
func scrap_loss_factor() -> float:
	return [1.0, 0.7, 0.5, 0.35][level(UpgradeCatalog.ARMOR)]


## Część prędkości zostająca po zderzeniu: pancerz i dobre zawieszenie łagodzą uderzenie.
func impact_speed_factor() -> float:
	var soft := 0.15 if level(UpgradeCatalog.SUSPENSION) >= 2 else 0.0
	return minf(0.85, 0.35 + 0.08 * level(UpgradeCatalog.ARMOR) + soft)


func capacitor_regen_multiplier() -> float:
	return [1.0, 1.35, 1.7, 2.1][level(UpgradeCatalog.CAPACITOR)]


func fire_rate_multiplier() -> float:
	return [1.0, 1.25, 1.6, 1.6][level(UpgradeCatalog.TURRET)]


func projectile_damage() -> int:
	return 2 if level(UpgradeCatalog.TURRET) >= 3 else 1


func twin_barrels() -> bool:
	return level(UpgradeCatalog.TURRET) >= 2


## Mnożnik szybkości zmiany pasa.
func lane_speed_multiplier() -> float:
	return 1.0 + 0.3 * level(UpgradeCatalog.SUSPENSION)


## Połowa szerokości, z jakiej pojazd zgarnia złom i paliwo [m].
func pickup_half_width_m() -> float:
	return [1.2, 1.9, 4.0][level(UpgradeCatalog.GRABBER)]


## Czas ładowania tarana [s]; 0 = brak tarana.
func ram_cooldown_s() -> float:
	return [0.0, 30.0, 12.0][level(UpgradeCatalog.RAM)]


func ram_keeps_speed() -> bool:
	return level(UpgradeCatalog.RAM) >= 2


## Zapisuje parametry do świeżej symulacji wyprawy.
func apply_to(sim: RunSimulation) -> void:
	sim.vehicle.engine_multiplier = engine_multiplier()
	sim.power_train.crew = active_crew()
	sim.power_train.max_charges = boost_charges()
	sim.power_train.charges = boost_charges()
	sim.power_train.boost_gain = boost_gain()
	sim.power_train.boost_duration_s = boost_duration_s()
	sim.convoys.base_tier = level(UpgradeCatalog.CHASSIS)
	sim.impact_speed_factor = impact_speed_factor()
	sim.expedition.scrap_loss_factor = scrap_loss_factor()
	sim.combat.capacitor_regen_multiplier = capacitor_regen_multiplier()
	sim.combat.fire_rate_multiplier = fire_rate_multiplier()
	sim.combat.projectile_damage = projectile_damage()
	sim.lanes.max_lateral_speed_mps *= lane_speed_multiplier()
	sim.lanes.settle_tau_s /= lane_speed_multiplier()
	sim.lanes.steer_speed_mps *= lane_speed_multiplier()
	sim.lanes.assist_speed_mps *= lane_speed_multiplier()
	sim.scrap_half_width_m = pickup_half_width_m()
	sim.ram_cooldown_s = ram_cooldown_s()
	sim.ram_keeps_speed = ram_keeps_speed()
