extends TestCase

const DT := 1.0 / 60.0


func _quiet_sim() -> RunSimulation:
	var sim := RunSimulation.new(900.0, 3)
	sim.generator.wrecks_enabled = false
	sim.items.clear()
	sim.combat.set_first_encounter(1e9)
	return sim


func _run(sim: RunSimulation, seconds: float, power_w: float) -> void:
	var t := 0.0
	while t < seconds:
		sim.step(DT, power_w)
		t += DT


func test_crew_is_a_constant_accelerator() -> void:
	var t := PowerTrain.new()
	assert_near(t.multiplier(), 1.0, 1e-6, "bez załogi i dopalacza moc bez zmian")
	t.crew = 4
	assert_near(t.multiplier(), 1.08, 1e-6, "czterech pedalarzy = +8%")


func test_booster_burns_a_charge_and_lasts_a_while() -> void:
	var t := PowerTrain.new()
	t.max_charges = 2
	t.charges = 2
	t.boost_gain = 0.35
	t.boost_duration_s = 8.0
	var events: Array = []
	t.boost_started.connect(func() -> void: events.append("start"))
	t.boost_ended.connect(func() -> void: events.append("koniec"))
	assert_true(t.trigger())
	assert_eq(t.charges, 1)
	assert_near(t.multiplier(), 1.35, 1e-6)
	assert_false(t.trigger(), "drugi wtrysk dopiero po pierwszym")
	t.step(7.9)
	assert_true(t.is_boosting())
	t.step(0.2)
	assert_false(t.is_boosting())
	assert_near(t.multiplier(), 1.0, 1e-6)
	assert_eq(events, ["start", "koniec"])
	assert_true(t.trigger())
	t.step(9.0)
	assert_false(t.trigger(), "bez ładunków dopalacz milczy")
	assert_eq(t.boosts_used, 2)


func test_refill_is_capped_at_tank_size() -> void:
	var t := PowerTrain.new()
	t.max_charges = 3
	t.charges = 2
	assert_eq(t.refill(1), 1)
	assert_eq(t.refill(2), 0, "pełny bak nie przyjmie więcej")
	assert_eq(t.charges, 3)


func test_booster_adds_speed_but_not_training_load() -> void:
	var plain := _quiet_sim()
	var boosted := _quiet_sim()
	boosted.power_train.boost_gain = 0.5
	boosted.power_train.boost_duration_s = 20.0
	_run(plain, 20.0, 200.0)
	_run(boosted, 20.0, 200.0)
	assert_true(boosted.trigger_boost())
	_run(plain, 15.0, 200.0)
	_run(boosted, 15.0, 200.0)
	assert_true(boosted.vehicle.speed_mps > plain.vehicle.speed_mps * 1.08, "dopalacz przyspiesza (%.1f vs %.1f m/s)" % [boosted.vehicle.speed_mps, plain.vehicle.speed_mps])
	assert_near(boosted.last_wheel_power_w, 300.0, 0.5, "na kołach 200 W × 1,5")
	assert_near(boosted.expedition.energy_j, plain.expedition.energy_j, 1.0, "praca z nóg ta sama – trening liczy nogi, nie paliwo")
	assert_near(boosted.expedition.metrics.normalized_power(), plain.expedition.metrics.normalized_power(), 0.01)
	assert_eq(boosted.expedition.boosts_used, 1)


func test_loadout_sets_booster_crew_and_accelerator() -> void:
	var l := Loadout.new({UpgradeCatalog.BOOSTER: 2, UpgradeCatalog.GENERATOR: 2, UpgradeCatalog.CHASSIS: 1})
	l.crew = 9
	assert_eq(l.crew_seats(), 4, "dwuosiowiec ma cztery ławki")
	assert_eq(l.active_crew(), 4, "nadmiar załogi czeka w osadzie")
	assert_near(l.accelerator_multiplier(), 1.1 * 1.08, 1e-6)
	var sim := _quiet_sim()
	l.apply_to(sim)
	assert_eq(sim.power_train.charges, 3)
	assert_near(sim.power_train.boost_gain, 0.45, 1e-6)
	assert_eq(sim.power_train.crew, 4)
	assert_near(sim.power_multiplier(), 1.1 * 1.08, 1e-6)
	var bare := _quiet_sim()
	Loadout.new().apply_to(bare)
	assert_eq(bare.power_train.charges, 1, "bez modułu jest jeden awaryjny ładunek")
	assert_near(bare.power_train.boost_gain, 0.25, 1e-6)


func test_fuel_canister_refills_the_booster() -> void:
	var sim := _quiet_sim()
	sim.power_train.max_charges = 2
	sim.power_train.charges = 0
	_run(sim, 5.0, 200.0)
	var can := TrackItem.new(777, TrackItem.Kind.FUEL, sim.lanes.target_lane, sim.vehicle.distance_m + 6.0, 1, 0)
	sim.add_items([can] as Array[TrackItem])
	_run(sim, 3.0, 200.0)
	assert_true(can.consumed)
	assert_eq(sim.expedition.fuel, 1, "kanister dalej liczy się jako łup")
	assert_eq(sim.power_train.charges, 1, "i uzupełnia ładunek dopalacza")


func test_freed_pedalers_join_the_crew_in_the_save() -> void:
	var s := ProgressStore.new("user://test_saves/%d/crew.json" % OS.get_process_id())
	assert_eq(s.crew(), 0)
	s.record_run({"scrap": 10, "pedalers_freed": 3})
	s.record_run({"scrap": 10, "pedalers_freed": 2})
	assert_eq(s.crew(), 5)
	assert_eq(s.loadout().crew, 5)
	assert_eq(s.loadout().active_crew(), 2, "buggy zabiera dwóch")
	assert_true(s.save_data())
	var again := ProgressStore.new(s.path)
	assert_true(again.load_data())
	assert_eq(again.crew(), 5, "załoga przetrwała zapis")
