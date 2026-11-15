extends TestCase


func _store_with(scrap: int, fuel: int) -> ProgressStore:
	var s := ProgressStore.new("user://test_saves/%d/progression.json" % OS.get_process_id())
	s.data["total_scrap"] = scrap
	s.data["fuel"] = fuel
	return s


func test_catalog_has_five_upgrades_with_costs() -> void:
	assert_eq(UpgradeCatalog.ORDER.size(), 5)
	for id in UpgradeCatalog.ORDER:
		assert_true(UpgradeCatalog.max_level(id) >= 2, "%s ma poziomy" % id)
		var c := UpgradeCatalog.next_cost(id, 0)
		assert_true(int(c["scrap"]) > 0, "%s kosztuje złom" % id)
		assert_true(UpgradeCatalog.next_cost(id, UpgradeCatalog.max_level(id)).is_empty(), "%s: brak kosztu po maksimum" % id)


func test_buy_deducts_currency_and_raises_level() -> void:
	var s := _store_with(1000, 10)
	assert_true(s.buy(UpgradeCatalog.GENERATOR), "kupno poz. 1")
	assert_eq(s.upgrade_level(UpgradeCatalog.GENERATOR), 1)
	assert_eq(s.total_scrap(), 880)
	assert_true(s.buy(UpgradeCatalog.GENERATOR), "kupno poz. 2")
	assert_eq(s.total_scrap(), 560)
	assert_eq(s.fuel(), 8)


func test_cannot_buy_without_funds_or_past_max() -> void:
	var s := _store_with(100, 0)
	assert_false(s.buy(UpgradeCatalog.GENERATOR), "za mało złomu")
	assert_eq(s.total_scrap(), 100, "nic nie pobrano")
	var rich := _store_with(100000, 100)
	for i in 10:
		rich.buy(UpgradeCatalog.ARMOR)
	assert_eq(rich.upgrade_level(UpgradeCatalog.ARMOR), UpgradeCatalog.max_level(UpgradeCatalog.ARMOR), "nie ponad maksimum")
	var s2 := _store_with(1000, 0)
	assert_false(s2.buy(UpgradeCatalog.CAPACITOR), "kondensator wymaga paliwa")


func test_upgrades_survive_save_and_load() -> void:
	var s := _store_with(1000, 10)
	s.buy(UpgradeCatalog.TRAILER)
	assert_true(s.save_data())
	var r := ProgressStore.new(s.path)
	assert_true(r.load_data())
	assert_eq(r.upgrade_level(UpgradeCatalog.TRAILER), 1)
	assert_eq(r.fuel(), 8)


func test_loadout_changes_the_ride() -> void:
	var base := RunSimulation.new(900.0, 1)
	var tuned := RunSimulation.new(900.0, 1)
	Loadout.new({UpgradeCatalog.GENERATOR: 3, UpgradeCatalog.ARMOR: 2, UpgradeCatalog.TURRET: 2, UpgradeCatalog.CAPACITOR: 1, UpgradeCatalog.TRAILER: 2}).apply_to(tuned)
	assert_true(tuned.vehicle.steady_state_speed(200.0) > base.vehicle.steady_state_speed(200.0) * 1.05, "generator przyspiesza")
	assert_true(tuned.combat.fire_interval_s() < base.combat.fire_interval_s(), "wieżyczka strzela szybciej")
	tuned.expedition.add_scrap(100)
	base.expedition.add_scrap(100)
	assert_eq(base.expedition.scrap, 100)
	assert_eq(tuned.expedition.scrap, 130, "przyczepa: +30% złomu")
	var lost_tuned := tuned.expedition.lose_scrap_on_hit()
	var lost_base := base.expedition.lose_scrap_on_hit()
	assert_true(lost_tuned < lost_base, "pancerz zmniejsza straty (%d < %d)" % [lost_tuned, lost_base])


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
