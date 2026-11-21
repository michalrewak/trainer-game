extends TestCase


func _store_with(scrap: int, fuel: int, kj: int = 0, upgrades: Dictionary = {}) -> ProgressStore:
	var s := ProgressStore.new("user://test_saves/%d/progression.json" % OS.get_process_id())
	s.data["total_scrap"] = scrap
	s.data["fuel"] = fuel
	s.data["total_energy_kj"] = kj
	s.data["upgrades"] = upgrades
	return s


func test_catalog_has_chassis_and_seven_modules_with_costs() -> void:
	assert_eq(UpgradeCatalog.ORDER.size(), 8)
	assert_eq(UpgradeCatalog.ORDER[0], UpgradeCatalog.CHASSIS)
	for id in UpgradeCatalog.ORDER:
		assert_true(UpgradeCatalog.max_level(id) >= 2, "%s ma poziomy" % id)
		var c := UpgradeCatalog.next_cost(id, 0)
		assert_true(int(c["scrap"]) > 0, "%s kosztuje złom" % id)
		assert_true(UpgradeCatalog.next_cost(id, UpgradeCatalog.max_level(id)).is_empty(), "%s: brak kosztu po maksimum" % id)
		var costs: Array = UpgradeCatalog.DEFS[id]["costs"]
		assert_eq(costs.size(), UpgradeCatalog.max_level(id), "%s: koszt dla każdego poziomu" % id)
		for i in range(1, costs.size()):
			assert_true(int(costs[i][0]) > int(costs[i - 1][0]), "%s: kolejne poziomy są droższe" % id)


func test_buy_deducts_currency_and_raises_level() -> void:
	var s := _store_with(1000, 10)
	assert_true(s.buy(UpgradeCatalog.GENERATOR), "kupno poz. 1")
	assert_eq(s.upgrade_level(UpgradeCatalog.GENERATOR), 1)
	assert_eq(s.total_scrap(), 880)
	assert_true(s.buy(UpgradeCatalog.GENERATOR), "kupno poz. 2 (generator ma wyższy limit na buggy)")
	assert_eq(s.total_scrap(), 580)
	assert_eq(s.fuel(), 8)


func test_cannot_buy_without_funds() -> void:
	var s := _store_with(100, 0)
	assert_false(s.buy(UpgradeCatalog.GENERATOR), "za mało złomu")
	assert_eq(s.total_scrap(), 100, "nic nie pobrano")
	assert_true(s.block_reason(UpgradeCatalog.GENERATOR).contains("20 złomu"), "powód: ile brakuje")
	var s2 := _store_with(1000, 0)
	assert_false(s2.buy(UpgradeCatalog.CAPACITOR), "kondensator wymaga paliwa")
	assert_true(s2.block_reason(UpgradeCatalog.CAPACITOR).contains("paliwa"))


func test_small_chassis_limits_module_levels() -> void:
	var rich := _store_with(100000, 100, 100000)
	for i in 10:
		rich.buy(UpgradeCatalog.ARMOR)
	assert_eq(rich.upgrade_level(UpgradeCatalog.ARMOR), 1, "buggy udźwignie pancerz tylko poz. 1")
	assert_true(rich.block_reason(UpgradeCatalog.ARMOR).contains("podwozia"))
	assert_true(rich.buy(UpgradeCatalog.CHASSIS), "druga oś")
	for i in 10:
		rich.buy(UpgradeCatalog.ARMOR)
	assert_eq(rich.upgrade_level(UpgradeCatalog.ARMOR), 2, "łazik: do poz. 2")
	assert_true(rich.buy(UpgradeCatalog.CHASSIS), "trzecia oś")
	for i in 10:
		rich.buy(UpgradeCatalog.ARMOR)
	assert_eq(rich.upgrade_level(UpgradeCatalog.ARMOR), UpgradeCatalog.max_level(UpgradeCatalog.ARMOR), "krążownik: maksimum")
	assert_eq(rich.block_reason(UpgradeCatalog.ARMOR), "Maksymalny poziom.")


func test_chassis_needs_real_work_in_kilojoules() -> void:
	var s := _store_with(100000, 100, 399)
	assert_false(s.buy(UpgradeCatalog.CHASSIS), "samym złomem się nie da")
	assert_true(s.block_reason(UpgradeCatalog.CHASSIS).contains("400 kJ"))
	var e := Expedition.new(60.0)
	e.tick(60.0, 200.0, 8.0, 500.0)
	s.record_run(e.to_summary(true))
	assert_eq(s.total_energy_kj(), 411, "praca z wyprawy dolicza się do sumy (12 kJ)")
	assert_true(s.buy(UpgradeCatalog.CHASSIS), "po wyjeżdżeniu kJ można kupić")


func test_old_save_recovers_work_from_run_history() -> void:
	var s := _store_with(0, 0)
	var path := s.path
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "total_scrap": 5, "runs": [{"energy_kj": 120}, {"energy_kj": 80}]}))
	f.close()
	var r := ProgressStore.new(path)
	assert_true(r.load_data())
	assert_eq(r.total_energy_kj(), 200)


func test_next_goal_names_what_to_aim_for() -> void:
	var poor := _store_with(50, 0)
	assert_true(poor.next_goal().contains("Generator"), "najtańszy cel: generator (%s)" % poor.next_goal())
	assert_true(poor.next_goal().contains("70 złomu"), "i ile brakuje (%s)" % poor.next_goal())
	var ok := _store_with(130, 0)
	assert_true(ok.next_goal().begins_with("Stać cię na"), ok.next_goal())


func test_upgrades_survive_save_and_load() -> void:
	var s := _store_with(1000, 10)
	s.data["upgrades"] = {"trailer": 2}
	s.buy(UpgradeCatalog.GRABBER)
	assert_true(s.save_data())
	var r := ProgressStore.new(s.path)
	assert_true(r.load_data())
	assert_eq(r.upgrade_level(UpgradeCatalog.GRABBER), 1)
	assert_eq(r.fuel(), 9)
	assert_false((r.data["upgrades"] as Dictionary).has("trailer"), "usunięty moduł znika ze starego zapisu")


func test_loadout_changes_the_ride() -> void:
	var base := RunSimulation.new(900.0, 1)
	var tuned := RunSimulation.new(900.0, 1)
	Loadout.new({UpgradeCatalog.GENERATOR: 5, UpgradeCatalog.ARMOR: 3, UpgradeCatalog.TURRET: 3, UpgradeCatalog.CAPACITOR: 1, UpgradeCatalog.SUSPENSION: 2, UpgradeCatalog.GRABBER: 2}).apply_to(tuned)
	assert_true(tuned.vehicle.steady_state_speed(200.0) > base.vehicle.steady_state_speed(200.0) * 1.06, "generator przyspiesza")
	assert_true(tuned.combat.fire_interval_s() < base.combat.fire_interval_s(), "wieżyczka strzela szybciej")
	assert_eq(tuned.combat.projectile_damage, 2, "ciężkie pociski")
	assert_true(tuned.lanes.max_lateral_speed_mps > base.lanes.max_lateral_speed_mps * 1.5, "zawieszenie: szybsza zmiana pasa")
	tuned.expedition.add_scrap(100)
	base.expedition.add_scrap(100)
	var lost_tuned := tuned.expedition.lose_scrap_on_hit()
	var lost_base := base.expedition.lose_scrap_on_hit()
	assert_true(lost_tuned < lost_base, "pancerz zmniejsza straty (%d < %d)" % [lost_tuned, lost_base])


func _cruise(sim: RunSimulation, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		sim.step(1.0 / 60.0, 200.0)
		t += 1.0 / 60.0


func test_ram_smashes_wreck_then_needs_to_recharge() -> void:
	var sim := RunSimulation.new(900.0, 1)
	sim.generator.wrecks_enabled = false
	sim.combat.enabled = false
	Loadout.new({UpgradeCatalog.RAM: 1}).apply_to(sim)
	_cruise(sim, 15.0)
	sim.items.clear()
	sim.expedition.add_scrap(40)
	var rammed := [0]
	var hits := [0]
	sim.wreck_rammed.connect(func(_i: TrackItem) -> void: rammed[0] += 1)
	sim.wreck_hit.connect(func(_i: TrackItem, _l: int) -> void: hits[0] += 1)
	sim.items.append(TrackItem.new(801, TrackItem.Kind.WRECK, 1, sim.vehicle.distance_m + 3.0, 0, 0))
	_cruise(sim, 1.0)
	assert_eq(rammed[0], 1, "naładowany taran rozbija wrak")
	assert_eq(sim.expedition.scrap, 40, "bez straty złomu")
	assert_false(sim.ram_ready(), "taran się ładuje")
	_cruise(sim, 2.0)
	sim.items.append(TrackItem.new(802, TrackItem.Kind.WRECK, 1, sim.vehicle.distance_m + 3.0, 0, 0))
	_cruise(sim, 1.0)
	assert_eq(hits[0], 1, "drugi wrak przed naładowaniem to zwykłe zderzenie")
	assert_true(sim.expedition.scrap < 40)


func test_grabber_collects_from_the_next_lane() -> void:
	var plain := RunSimulation.new(900.0, 1)
	var grab := RunSimulation.new(900.0, 1)
	Loadout.new({UpgradeCatalog.GRABBER: 2}).apply_to(grab)
	var taken := {}
	for sim: RunSimulation in [plain, grab]:
		sim.generator.wrecks_enabled = false
		sim.combat.enabled = false
		_cruise(sim, 5.0)
		var right := TrackItem.new(900, TrackItem.Kind.SCRAP, 2, sim.vehicle.distance_m + 2.0, 1, 0)
		var left := TrackItem.new(901, TrackItem.Kind.SCRAP, 0, sim.vehicle.distance_m + 2.0, 1, 0)
		sim.add_items([right, left] as Array[TrackItem])
		_cruise(sim, 1.0)
		taken[sim] = int(right.consumed) + int(left.consumed)
	assert_eq(taken[plain], 0, "bez chwytaka złom z sąsiednich pasów zostaje")
	assert_eq(taken[grab], 2, "chwytak zgarnia z obu sąsiednich pasów")


func test_city_requires_armor_and_ftp() -> void:
	var none := Loadout.new({})
	var armored := Loadout.new({UpgradeCatalog.ARMOR: 1})
	assert_true(TerrainCatalog.is_unlocked(TerrainCatalog.CANYON, none, 120.0), "kanion zawsze otwarty")
	assert_false(TerrainCatalog.is_unlocked(TerrainCatalog.CITY, none, 250.0), "miasto wymaga pancerza")
	assert_false(TerrainCatalog.is_unlocked(TerrainCatalog.CITY, armored, 140.0), "miasto wymaga FTP")
	assert_true(TerrainCatalog.is_unlocked(TerrainCatalog.CITY, armored, 200.0))
	assert_eq(TerrainCatalog.missing_requirements(TerrainCatalog.CITY, none, 100.0).size(), 2)


func test_fuel_appears_on_track_and_is_collected() -> void:
	var g := TrackGenerator.new(9)
	var items := g.generate_until(5000.0)
	var fuel := items.filter(func(i: TrackItem) -> bool: return i.is_fuel())
	assert_between(float(fuel.size()), 6.0, 20.0, "kanistry co ~420 m na 5 km")
	var sim := RunSimulation.new(900.0, 2)
	sim.items.clear()
	sim.items.append(TrackItem.new(42, TrackItem.Kind.FUEL, 1, sim.vehicle.distance_m + 1.0, 1, 0))
	sim.step(0.5, 200.0)
	assert_eq(sim.expedition.fuel, 1, "paliwo zebrane")
	assert_eq(sim.expedition.to_summary(true)["fuel"], 1)


func test_city_terrain_is_richer_and_more_dangerous() -> void:
	var canyon := RunSimulation.new(900.0, 3)
	var city := RunSimulation.new(900.0, 3)
	TerrainCatalog.apply_to(TerrainCatalog.CITY, city)
	assert_eq(city.terrain, TerrainCatalog.CITY)
	assert_true(city.generator.scrap_gap_easy_m < canyon.generator.scrap_gap_easy_m, "gęściej złomu")
	assert_true(city.combat.encounter_gap_easy_s < canyon.combat.encounter_gap_easy_s, "częściej gangi")
