extends TestCase
## Mechanizmy, które mają trzymać gracza przy grze: passa, unik o włos, zlecenia,
## skrzynie z niespodzianką, rekordy i dni z rzędu.

const DT := 1.0 / 60.0

var _events: Array = []


func _quiet_sim() -> RunSimulation:
	var sim := RunSimulation.new(1800.0, 21)
	sim.generator.wrecks_enabled = false
	sim.generator.crate_every_m = 1e9
	sim.items.clear()
	sim.combat.set_first_encounter(1e9)
	_events = []
	var t := 0.0
	while t < 20.0:
		sim.step(DT, 200.0)
		t += DT
	sim.items.clear()
	sim.streak.reset()
	sim.streak.points = 0
	return sim


func _run(sim: RunSimulation, seconds: float, power_w: float = 200.0) -> void:
	var t := 0.0
	while t < seconds:
		sim.step(DT, power_w)
		t += DT


func _put(sim: RunSimulation, kind: TrackItem.Kind, lane: int, ahead_m: float, value: int = 1) -> TrackItem:
	var item := TrackItem.new(900_000 + sim.items.size(), kind, lane, sim.vehicle.distance_m + ahead_m, value, 0)
	sim.add_items([item] as Array[TrackItem])
	return item


# --- Passa -----------------------------------------------------------------------

func test_streak_tiers_timer_and_reset() -> void:
	var s := Streak.new()
	s.tier_changed.connect(func(tier: int, up: bool) -> void: _events.append([tier, up]))
	s.broken.connect(func(points: int) -> void: _events.append(["koniec", points]))
	_events = []
	assert_near(s.multiplier(), 1.0, 1e-6)
	s.add(4)
	assert_eq(s.tier(), 0, "cztery punkty to jeszcze nie próg")
	s.add(1)
	assert_near(s.multiplier(), 1.2, 1e-6, "pięć punktów = ×1,2")
	assert_eq(_events, [[1, true]])
	s.add(10)
	assert_near(s.multiplier(), 1.5, 1e-6)
	assert_near(s.progress_to_next(), 0.0, 1e-6, "początek nowego progu")
	assert_near(s.time_ratio(), 1.0, 1e-6, "każdy punkt odnawia zegar")
	s.step(Streak.HOLD_S + 0.1)
	assert_near(s.multiplier(), 1.2, 1e-6, "zegar minął: spadek o jeden próg, nie do zera")
	assert_eq(_events[2], [1, false])
	s.reset()
	assert_eq(s.points, 0, "wpadka zeruje passę")
	assert_eq(_events[3], ["koniec", 5])
	assert_eq(s.best_tier, 2, "najlepszy próg zostaje w pamięci")
	s.add(500)
	assert_near(s.multiplier(), 3.0, 1e-6, "mnożnik ma sufit ×3")


func test_clean_collecting_multiplies_scrap_and_crash_ends_it() -> void:
	var sim := _quiet_sim()
	var before := sim.expedition.scrap
	for i in 30:
		_put(sim, TrackItem.Kind.SCRAP, sim.lanes.target_lane, 6.0 + i * 3.0)
	_run(sim, 13.0)
	var got := sim.expedition.scrap - before
	# 5 × 1,0 + 10 × 1,2 + 15 × 1,5 = 39,5
	assert_between(float(got), 38.0, 40.0, "30 zębatek z passą daje ok. 39 złomu (jest %d)" % got)
	assert_near(sim.streak.multiplier(), 2.0, 1e-6, "30 punktów = ×2")
	assert_near(sim.expedition.best_streak, 2.0, 1e-6)
	_put(sim, TrackItem.Kind.WRECK, sim.lanes.target_lane, 5.0)
	_run(sim, 1.5)
	assert_eq(sim.streak.points, 0, "zderzenie z wrakiem przerywa passę")
	assert_near(sim.expedition.best_streak, 2.0, 1e-6, "rekord wyprawy zostaje")


func test_streak_can_be_switched_off_for_exact_counts() -> void:
	var sim := _quiet_sim()
	sim.streak_enabled = false
	var before := sim.expedition.scrap
	for i in 20:
		_put(sim, TrackItem.Kind.SCRAP, sim.lanes.target_lane, 6.0 + i * 3.0)
	_run(sim, 10.0)
	assert_eq(sim.expedition.scrap - before, 20)


# --- Unik o włos -----------------------------------------------------------------

func test_last_moment_dodge_counts_as_near_miss() -> void:
	var sim := _quiet_sim()
	sim.near_miss.connect(func(_item: TrackItem) -> void: _events.append("o włos"))
	_put(sim, TrackItem.Kind.WRECK, sim.lanes.target_lane, sim.vehicle.speed_mps * 0.75)
	assert_true(sim.request_lane_change(-1))
	_run(sim, 2.0)
	assert_eq(sim.expedition.collisions, 0, "unik się udał")
	assert_eq(_events, ["o włos"])
	assert_eq(sim.expedition.near_misses, 1)
	assert_eq(sim.streak.points, 3, "unik o włos daje 3 punkty passy")


func test_early_lane_change_is_not_a_near_miss() -> void:
	var sim := _quiet_sim()
	var lane := sim.lanes.target_lane
	assert_true(sim.request_lane_change(-1))
	_run(sim, 4.0)
	_put(sim, TrackItem.Kind.WRECK, lane, 20.0)
	_put(sim, TrackItem.Kind.WRECK, 2, 20.0)
	_run(sim, 4.0)
	assert_eq(sim.expedition.near_misses, 0, "spokojne ominięcie z daleka się nie liczy")


# --- Zlecenia --------------------------------------------------------------------

func test_board_draws_three_distinct_contracts_scaled_to_the_run() -> void:
	var board := ContractBoard.new()
	board.setup(15.0, 200.0, 5, {"combat": true, "convoys": true, "raids": true})
	assert_eq(board.contracts.size(), 3)
	var kinds := {}
	for c in board.contracts:
		kinds[int(c["kind"])] = true
		assert_true(str(c["text"]).length() > 5 and str(c["text"]).length() <= 34, "krótki opis: %s" % c["text"])
		assert_true(float(c["goal"]) > 0.0 and int(c["reward_scrap"]) >= 40)
		assert_false(bool(c["done"]))
	assert_eq(kinds.size(), 3, "trzy różne zlecenia")
	assert_true([ContractBoard.Kind.IN_BAND, ContractBoard.Kind.ZONE, ContractBoard.Kind.KJ].has(int(board.contracts[0]["kind"])), "pierwsze zlecenie jest treningowe")
	var again := ContractBoard.new()
	again.setup(15.0, 200.0, 5, {"combat": true, "convoys": true, "raids": true})
	assert_eq(again.contracts[1]["text"], board.contracts[1]["text"], "to samo ziarno = te same zlecenia")
	var short_board := ContractBoard.new()
	var long_board := ContractBoard.new()
	short_board.setup(2.0, 200.0, 1, {})
	long_board.setup(60.0, 200.0, 1, {})
	assert_true(float(long_board.contracts[0]["goal"]) > float(short_board.contracts[0]["goal"]) * 5.0, "dłuższa wyprawa = większy cel")


func test_workout_and_feature_flags_limit_the_pool() -> void:
	for seed_value in 30:
		var board := ContractBoard.new()
		board.setup(20.0, 200.0, seed_value, {"combat": false, "convoys": false, "raids": false, "workout": true})
		assert_eq(int(board.contracts[0]["kind"]), ContractBoard.Kind.IN_BAND, "w treningu liczą się widełki planu")
		for c in board.contracts:
			var kind := int(c["kind"])
			assert_false([ContractBoard.Kind.ZONE, ContractBoard.Kind.KJ, ContractBoard.Kind.RAIDERS, ContractBoard.Kind.WRECKS, ContractBoard.Kind.CONVOY, ContractBoard.Kind.RAID].has(kind), "niedostępne zlecenie: %s" % c["text"])


func test_contract_progress_reward_and_full_set_bonus() -> void:
	var sim := _quiet_sim()
	var board := sim.contracts
	board.contracts = [
		{"kind": ContractBoard.Kind.SCRAP, "text": "Zbierz 3 zębatki", "goal": 3.0, "progress": 0.0, "reward_scrap": 50, "reward_fuel": 0, "done": false},
		{"kind": ContractBoard.Kind.SPEED, "text": "Rozpędź się do 20 km/h", "goal": 20.0, "progress": 0.0, "reward_scrap": 40, "reward_fuel": 1, "done": false},
		{"kind": ContractBoard.Kind.IN_BAND, "text": "Jedź 0:02 w widełkach celu", "goal": 2.0, "progress": 0.0, "reward_scrap": 40, "reward_fuel": 0, "done": false},
	] as Array[Dictionary]
	board.completed.connect(func(c: Dictionary) -> void: _events.append(c["text"]))
	sim.combat.target_power_w = 200.0
	var scrap0 := sim.expedition.scrap
	_run(sim, 3.0)
	assert_true(_events.has("Rozpędź się do 20 km/h"), "prędkość zaliczona od razu")
	assert_true(_events.has("Jedź 0:02 w widełkach celu"), "dwie sekundy w widełkach")
	assert_eq(ContractBoard.progress_text(board.contracts[0]), "0/3")
	for i in 3:
		_put(sim, TrackItem.Kind.SCRAP, sim.lanes.target_lane, 6.0 + i * 3.0)
	_run(sim, 2.5)
	assert_true(board.is_all_done(), "komplet zleceń")
	assert_eq(sim.expedition.contracts_done, 3)
	assert_eq(sim.expedition.scrap - scrap0, 3 + 50 + 40 + 40, "zębatki plus nagrody")
	assert_eq(sim.expedition.fuel, 1 + ContractBoard.ALL_DONE_FUEL, "paliwo ze zlecenia i premia za komplet")
	assert_eq(ContractBoard.progress_text({"kind": ContractBoard.Kind.STREAK, "goal": 3.0, "progress": 1.0}), "×1.2/×2.0")
	assert_eq(ContractBoard.progress_text({"kind": ContractBoard.Kind.ZONE, "goal": 180.0, "progress": 80.0}), "1:20/3:00")
	assert_eq(board.to_summary().size(), 3)


# --- Skrzynie --------------------------------------------------------------------

func test_crate_gives_one_of_the_surprises() -> void:
	var seen := {}
	for seed_value in 24:
		var sim := RunSimulation.new(1800.0, seed_value)
		sim.generator.wrecks_enabled = false
		sim.generator.crate_every_m = 1e9
		sim.items.clear()
		sim.combat.set_first_encounter(1e9)
		_run(sim, 5.0)
		sim.items.clear()
		sim.power_train.max_charges = 3
		sim.power_train.charges = 0
		sim.combat.capacitor = 0.0
		var got: Array = []
		sim.crate_opened.connect(func(_item: TrackItem, prize: int, amount: int) -> void: got.append([prize, amount]))
		var scrap0 := sim.expedition.scrap
		_put(sim, TrackItem.Kind.CRATE, sim.lanes.target_lane, 5.0)
		_run(sim, 1.0)
		assert_eq(got.size(), 1, "skrzynia otwarta")
		assert_eq(sim.expedition.crates_opened, 1)
		var prize: int = got[0][0]
		seen[prize] = true
		match prize:
			RunSimulation.Prize.SCRAP_RAIN:
				assert_eq(sim.items_between(sim.vehicle.distance_m, sim.vehicle.distance_m + 60.0).size(), 10, "deszcz zębatek na drodze")
			RunSimulation.Prize.FUEL:
				assert_eq(sim.expedition.fuel, 1)
				assert_eq(sim.power_train.charges, 1)
			RunSimulation.Prize.CHARGE:
				assert_eq(sim.power_train.charges, 3, "pełny dopalacz")
				assert_true(sim.combat.capacitor > 0.95, "pełne kondensatory")
			RunSimulation.Prize.JACKPOT:
				assert_eq(sim.expedition.scrap - scrap0, 25)
	assert_eq(seen.size(), 4, "przy różnych ziarnach wypadają wszystkie cztery nagrody")


func test_generator_places_crates_away_from_wrecks() -> void:
	var gen := TrackGenerator.new(3, 3)
	var items := gen.generate_until(4000.0)
	var crates: Array[TrackItem] = []
	for item in items:
		if item.is_crate():
			crates.append(item)
	assert_true(crates.size() >= 4, "skrzynie pojawiają się regularnie (jest %d)" % crates.size())
	for crate in crates:
		for item in items:
			if item.is_wreck() and item.lane == crate.lane:
				assert_true(absf(item.distance_m - crate.distance_m) > 5.0, "skrzynia nie stoi na wraku")


# --- Rekordy i dni z rzędu --------------------------------------------------------

func test_best_power_windows() -> void:
	var m := TrainingMetrics.new(200.0)
	for i in 60:
		m.tick(1.0, 100.0)
	for i in 30:
		m.tick(1.0, 300.0)
	for i in 60:
		m.tick(1.0, 100.0)
	assert_near(m.best_power(0), 300.0, 0.5, "najlepsze 20 s")
	assert_near(m.best_power(1), 200.0, 0.5, "najlepsza minuta: 30 s × 300 W i 30 s × 100 W")
	assert_near(m.best_power(2), 0.0, 0.01, "jazda krótsza niż 5 min nie ma rekordu 5 min")
	var s := m.to_summary()
	assert_eq(int(s["best_20s_w"]), 300)
	assert_eq(int(s["best_1min_w"]), 200)


func test_records_per_power_source() -> void:
	var store := ProgressStore.new("user://test_saves/%d/records.json" % OS.get_process_id())
	var first := {"scrap": 100, "energy_kj": 200, "best_1min_w": 220, "best_streak": 1.5, "source": "pad"}
	store.record_run(first)
	assert_eq(first["new_records"], [], "pierwsza wyprawa ustawia poziom odniesienia bez fanfar")
	assert_near(store.record("pad", "best_1min_w"), 220.0, 0.01)
	var worse := {"scrap": 50, "energy_kj": 100, "best_1min_w": 200, "best_streak": 1.2, "source": "pad"}
	store.record_run(worse)
	assert_eq(worse["new_records"], [], "słabszy wynik nie jest rekordem")
	var better := {"scrap": 150, "energy_kj": 150, "best_1min_w": 240, "best_streak": 2.0, "source": "pad"}
	store.record_run(better)
	assert_true((better["new_records"] as Array).has("best_1min_w") and (better["new_records"] as Array).has("scrap") and (better["new_records"] as Array).has("best_streak"))
	assert_false((better["new_records"] as Array).has("energy_kj"))
	var trainer := {"scrap": 10, "best_1min_w": 180, "source": "trainer"}
	store.record_run(trainer)
	assert_near(store.record("trainer", "best_1min_w"), 180.0, 0.01, "trenażer ma własną tabelę")
	assert_near(store.record("pad", "best_1min_w"), 240.0, 0.01)
	store.record_run({"scrap": 9999, "best_1min_w": 999, "source": "auto"})
	assert_near(store.record("pad", "scrap"), 150.0, 0.01, "autopilot nie bije rekordów")
	assert_eq(ProgressStore.record_text("best_1min_w", 240.0), "Moc 1 min: 240 W")
	assert_eq(ProgressStore.record_text("best_streak", 2.0), "Passa: ×2.0")
	assert_true(store.save_data())
	var again := ProgressStore.new(store.path)
	assert_true(again.load_data())
	assert_near(again.record("pad", "best_1min_w"), 240.0, 0.01, "rekordy przetrwały zapis")


func test_day_streak_counts_consecutive_days() -> void:
	var store := ProgressStore.new("user://test_saves/%d/days.json" % OS.get_process_id())
	assert_eq(store.day_streak("2026-11-21"), 0)
	store.record_run({"scrap": 1}, "2026-11-18 18:00:00")
	store.record_run({"scrap": 1}, "2026-11-19 18:00:00")
	store.record_run({"scrap": 1}, "2026-11-20 07:00:00")
	store.record_run({"scrap": 1}, "2026-11-20 19:00:00")
	assert_eq(store.day_streak("2026-11-20"), 3, "trzy dni z rzędu, dwie wyprawy jednego dnia liczą się raz")
	assert_eq(store.day_streak("2026-11-21"), 3, "dziś jeszcze bez jazdy – passa trwa do końca dnia")
	assert_eq(store.day_streak("2026-11-22"), 0, "dzień przerwy zeruje")
	store.record_run({"scrap": 1}, "2026-11-16 18:00:00")
	assert_eq(store.day_streak("2026-11-20"), 3, "luka 17.11 oddziela starszą jazdę")
