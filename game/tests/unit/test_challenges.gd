extends TestCase

const DT := 1.0 / 30.0


func _free_ride(duration_s: float = 600.0) -> RunSimulation:
	var sim := RunSimulation.new(duration_s, 21)
	sim.combat.enabled = false
	sim.challenges.enabled = true
	sim.challenges.ftp_w = 200.0
	sim.challenges.set_first_after(10.0)
	return sim


func _ride(sim: RunSimulation, seconds: float, power: Callable) -> void:
	var t := 0.0
	while t < seconds and not sim.expedition.finished:
		sim.step(DT, float(power.call(sim)))
		t += DT


func _first_kind(sim: RunSimulation) -> int:
	return int(sim.challenges.current.get("kind", -1))


func test_challenge_is_announced_then_started() -> void:
	var sim := _free_ride()
	var events: Array[String] = []
	sim.challenges.announced.connect(func(_c: Dictionary) -> void: events.append("announce"))
	sim.challenges.started.connect(func(_c: Dictionary) -> void: events.append("start"))
	_ride(sim, 9.0, func(_s: RunSimulation) -> float: return 150.0)
	assert_eq(events.size(), 0, "nic przed czasem")
	_ride(sim, 2.0, func(_s: RunSimulation) -> float: return 150.0)
	assert_eq(events, ["announce"] as Array[String], "zapowiedź")
	_ride(sim, ChallengeDirector.ANNOUNCE_S, func(_s: RunSimulation) -> float: return 150.0)
	assert_eq(events, ["announce", "start"] as Array[String], "start po odliczaniu")
	assert_true(sim.challenges.is_active())


func test_holding_power_wins_reward() -> void:
	var sim := _free_ride()
	var results: Array = []
	sim.challenges.finished.connect(func(c: Dictionary, ok: bool) -> void: results.append([int(c["kind"]), ok]))
	# Dokładnie w celu wyzwania (w widełkach ±8%).
	_ride(sim, 120.0, func(s: RunSimulation) -> float: return s.challenges.target_w() if s.challenges.is_active() else 150.0)
	assert_true(results.size() >= 1, "wyzwanie zakończone")
	if results.is_empty():
		return
	assert_true(results[0][1], "utrzymana moc = sukces")
	assert_true(sim.expedition.challenges_completed >= 1)
	assert_true(sim.expedition.fuel >= 2 or sim.expedition.scrap >= 10, "nagroda trafia do wyprawy")


func test_low_power_fails_and_escape_failure_brings_the_gang() -> void:
	var sim := _free_ride()
	sim.combat.enabled = true
	sim.combat.set_first_encounter(1e9)
	var results: Array = []
	sim.challenges.finished.connect(func(c: Dictionary, ok: bool) -> void: results.append([int(c["kind"]), ok]))
	_ride(sim, 600.0, func(_s: RunSimulation) -> float: return 60.0)
	assert_true(results.size() >= 2, "kilka wyzwań w 10 min (%d)" % results.size())
	for r in results:
		assert_false(r[1], "za mała moc = porażka")
	var escape_failed := results.any(func(r: Array) -> bool: return r[0] == ChallengeDirector.Kind.ESCAPE)
	assert_true(escape_failed, "była nieudana ucieczka")
	assert_true(sim.combat.raiders_destroyed + sim.combat.live_raiders().size() + sim.combat.rams_taken + sim.combat.rams_dodged + sim.combat.rams_blocked > 0, "gang dogonił gracza")


func test_too_much_power_is_not_holding_the_target() -> void:
	var sim := _free_ride()
	var results: Array = []
	sim.challenges.finished.connect(func(c: Dictionary, ok: bool) -> void: results.append([int(c["kind"]), ok]))
	# 25% ponad cel – poza widełkami (podjazd i ucieczka nie są zaliczane).
	_ride(sim, 200.0, func(s: RunSimulation) -> float: return s.challenges.target_w() * 1.25 if s.challenges.is_active() else 150.0)
	assert_true(results.size() >= 1)
	for r in results:
		if r[0] != ChallengeDirector.Kind.SPRINT:
			assert_false(r[1], "za mocno = poza widełkami = niezaliczone")


func test_target_band_and_overheating() -> void:
	assert_eq(TargetBand.status(190.0, 200.0, 0.05, 0.05), TargetBand.Status.IN_BAND)
	assert_eq(TargetBand.status(185.0, 200.0, 0.05, 0.05), TargetBand.Status.BELOW)
	assert_eq(TargetBand.status(215.0, 200.0, 0.05, 0.05), TargetBand.Status.ABOVE)
	assert_near(TargetBand.supply(200.0, 200.0, 0.05, 0.05), 1.0, 1e-6, "w widełkach pełne zasilanie")
	assert_near(TargetBand.supply(95.0, 200.0, 0.05, 0.05), 0.5, 1e-6, "połowa dolnej granicy")
	assert_true(TargetBand.supply(240.0, 200.0, 0.05, 0.05) < 0.8, "przegrzanie obniża zasilanie")
	assert_near(TargetBand.supply(400.0, 200.0, 0.05, 0.05), TargetBand.OVERHEAT_MIN_SUPPLY, 1e-6, "ale nie do zera")
	assert_eq(TargetBand.range_text(200.0, 0.05, 0.05), "190–210 W")


func test_combat_overheats_above_band() -> void:
	var sim := RunSimulation.new(900.0, 4)
	sim.combat.set_first_encounter(1e9)
	sim.combat.target_power_w = 200.0
	sim.combat.target_low_tol = 0.05
	sim.combat.target_high_tol = 0.05
	_ride(sim, 15.0, func(_s: RunSimulation) -> float: return 300.0)
	assert_true(sim.combat.supply_ratio() < 0.6, "przegrzanie: zasilanie spada (%.2f)" % sim.combat.supply_ratio())
	assert_true(sim.combat.fire_interval_s() > CombatModel.BASE_FIRE_INTERVAL_S * 1.5, "wolniejszy ogień")


func test_course_has_hills_and_valleys() -> void:
	var c := CourseProfile.new(3)
	assert_near(c.grade_at(100.0), 0.0, 1e-9, "płaski start")
	var lo := 1.0
	var hi := -1.0
	var d := 0.0
	while d < 20000.0:
		var g := c.grade_at(d)
		lo = minf(lo, g)
		hi = maxf(hi, g)
		d += 10.0
	assert_true(hi > 0.03, "są podjazdy (maks %.3f)" % hi)
	assert_true(lo < -0.03, "są zjazdy (min %.3f)" % lo)
	assert_true(hi <= 0.061 and lo >= -0.061, "nachylenie w rozsądnym zakresie")
	var sim := RunSimulation.new(900.0, 3)
	sim.course_enabled = true
	sim.vehicle.distance_m = 5000.0
	sim.step(0.1, 200.0)
	assert_near(sim.vehicle.grade, sim.course.grade_at(sim.vehicle.distance_m), 0.002, "pojazd czuje teren")


func test_climb_tilts_the_road_and_resets_after() -> void:
	var sim := _free_ride()
	_ride(sim, 10.5 + ChallengeDirector.ANNOUNCE_S + 1.0, func(_s: RunSimulation) -> float: return 200.0)
	assert_eq(_first_kind(sim), ChallengeDirector.Kind.CLIMB, "pierwsze wyzwanie to podjazd")
	assert_near(sim.vehicle.grade, 0.05, 1e-6, "nachylenie w trakcie")
	_ride(sim, 100.0, func(_s: RunSimulation) -> float: return 200.0)
	assert_near(sim.vehicle.grade, 0.0, 1e-6, "płasko po podjeździe")


func test_no_challenge_in_the_last_half_minute() -> void:
	var sim := _free_ride(40.0)
	sim.challenges.set_first_after(15.0)
	var announced := [0]
	sim.challenges.announced.connect(func(_c: Dictionary) -> void: announced[0] += 1)
	_ride(sim, 45.0, func(_s: RunSimulation) -> float: return 200.0)
	assert_eq(announced[0], 0, "za mało czasu do końca – brak wyzwania")


func test_pad_erg_simulation_restores_cruise() -> void:
	var pad := GamepadPowerSource.new()
	pad.model.nudge(15)
	assert_near(pad.model.cruise_watts, 150.0, 0.01)
	pad.set_erg_target(260.0)
	assert_near(pad.get_erg_target(), 260.0, 0.01, "ERG ustawia moc")
	assert_true(pad.get_hint().begins_with("ERG"))
	pad.set_erg_target(0.0)
	assert_true(pad.model.cruise_locked, "tempomat wraca")
	assert_near(pad.model.cruise_watts, 150.0, 0.01, "z poprzednią mocą")
	assert_near(pad.get_erg_target(), 0.0, 0.01)
