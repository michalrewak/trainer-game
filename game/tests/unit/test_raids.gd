extends TestCase

const DT := 1.0 / 60.0


## Wyprawa z włączonymi napadami: bez wraków, bez gangów z harmonogramu i bez wyzwań.
func _sim(first_fork_m: float = 600.0) -> RunSimulation:
	var sim := RunSimulation.new(1800.0, 9)
	sim.generator.wrecks_enabled = false
	sim.items.clear()
	sim.combat.set_first_encounter(1e9)
	sim.raids.enabled = true
	sim.raids.ftp_w = 200.0
	sim.raids.set_first_fork(first_fork_m)
	return sim


func _ride(sim: RunSimulation, seconds: float, power: Callable, each: Callable = Callable()) -> void:
	var t := 0.0
	while t < seconds and not sim.expedition.finished:
		if each.is_valid():
			each.call(sim)
		sim.step(DT, float(power.call(sim)))
		t += DT


func _target_power(sim: RunSimulation) -> float:
	return sim.raids.target_w() if sim.raids.is_raiding() else 200.0


## Jedzie do zwiadu, ustawia się na pasie zjazdu i dojeżdża do rozwidlenia.
func _reach_raid(sim: RunSimulation) -> void:
	_ride(sim, 200.0, _target_power, func(s: RunSimulation) -> void:
		if s.raids.state == RaidDirector.State.SCOUTING:
			var exit := s.raids.exit_lane()
			if s.lanes.target_lane != exit:
				s.request_lane_change(signi(exit - s.lanes.target_lane))
		if s.raids.is_raiding():
			s.expedition.finished = s.expedition.finished)
	assert_true(sim.raids.is_raiding() or sim.raids.raids_done > 0, "napad rozpoczęty")


func test_scouting_shows_settlement_500m_before_the_exit() -> void:
	var sim := _sim()
	var seen: Array = []
	sim.raids.scouted.connect(func(s: Dictionary) -> void: seen.append(s))
	_ride(sim, 30.0, _target_power)
	assert_eq(seen.size(), 1, "zwiad po dojechaniu na 500 m przed zjazdem")
	if seen.is_empty():
		return
	var s: Dictionary = seen[0]
	for key in ["name", "towers", "guards", "loot_scrap", "duration_s", "ftp", "side", "fork_d"]:
		assert_true(s.has(key), "karta zwiadu ma pole %s" % key)
	assert_between(sim.raids.distance_to_next_m(), 300.0, 500.0, "dystans do zjazdu")
	assert_near(sim.raids.target_w(), 200.0 * float(s["ftp"]), 2.5, "koszt wysiłku liczony od FTP")


func test_staying_on_the_road_skips_without_penalty() -> void:
	var sim := _sim()
	sim.expedition.add_scrap(50)
	var events: Array[String] = []
	sim.raids.skipped.connect(func(_s: Dictionary) -> void: events.append("skip"))
	sim.raids.started.connect(func(_s: Dictionary) -> void: events.append("start"))
	_ride(sim, 90.0, _target_power, func(s: RunSimulation) -> void:
		# Trzymamy środkowy pas – to nigdy nie jest pas zjazdu.
		if s.lanes.target_lane != 1:
			s.request_lane_change(signi(1 - s.lanes.target_lane)))
	assert_eq(events, ["skip"] as Array[String], "brak wyboru = jazda główną drogą")
	assert_true(sim.expedition.scrap >= 50, "bez kary")
	assert_eq(sim.raids.state, RaidDirector.State.IDLE)


func test_exit_lane_starts_the_raid() -> void:
	var sim := _sim()
	var started: Array = []
	sim.raids.started.connect(func(s: Dictionary) -> void: started.append(s))
	_ride(sim, 90.0, _target_power, func(s: RunSimulation) -> void:
		if s.raids.state == RaidDirector.State.SCOUTING and s.lanes.target_lane != s.raids.exit_lane():
			s.request_lane_change(signi(s.raids.exit_lane() - s.lanes.target_lane)))
	assert_eq(started.size(), 1, "skrajny pas od strony osady = napad")
	assert_true(sim.raids.is_raiding() or sim.raids.raids_done == 1)


func _full_raid(power: Callable, shoot_gate: bool) -> Dictionary:
	var sim := _sim()
	sim.combat.shield = 1.0
	var out := {"gate": [], "loot": -1, "fuel": -1, "repelled": false, "looting": 0, "sim": sim}
	sim.raids.gate_broken.connect(func(how: int) -> void: (out["gate"] as Array).append(how))
	sim.raids.looting_started.connect(func(_s: Dictionary) -> void: out["looting"] = int(out["looting"]) + 1)
	sim.raids.finished.connect(func(_s: Dictionary, loot: int, fuel: int, repelled: bool) -> void:
		out["loot"] = loot
		out["fuel"] = fuel
		out["repelled"] = repelled)
	_ride(sim, 400.0, power, func(s: RunSimulation) -> void:
		if s.raids.state == RaidDirector.State.SCOUTING and s.lanes.target_lane != s.raids.exit_lane():
			s.request_lane_change(signi(s.raids.exit_lane() - s.lanes.target_lane))
		s.combat.fire_held = shoot_gate and s.raids.is_raiding()
		if int(out["loot"]) >= 0:
			s.raids.enabled = false)
	return out


func test_shooting_the_gate_and_holding_power_gives_full_loot() -> void:
	var out := _full_raid(_target_power, true)
	var sim: RunSimulation = out["sim"]
	assert_eq(out["gate"], [RaidDirector.GateBreak.SHOT], "brama rozstrzelana z dystansu")
	assert_eq(out["looting"], 1, "wjazd do osady")
	assert_false(out["repelled"])
	var base := int(sim.raids.current["loot_scrap"])
	assert_true(int(out["loot"]) >= base, "pełny skarbiec (+ premia za bramę): %d z %d" % [out["loot"], base])
	assert_eq(sim.expedition.raids_done, 1)
	assert_false(sim.expedition.finished, "napad nie kończy wyprawy")
	assert_false(sim.raids.is_towing(), "po dowiezieniu łupu przyczepa znika")


func test_loot_rides_on_a_trailer_and_a_ram_spills_part_of_it() -> void:
	var sim := _sim()
	sim.combat.enabled = false
	var events: Array = []
	sim.raids.escape_started.connect(func(_s: Dictionary, scrap: int, _fuel: int) -> void: events.append(["escape", scrap]))
	sim.raids.loot_spilled.connect(func(lost: int) -> void: events.append(["spill", lost]))
	sim.raids.finished.connect(func(_s: Dictionary, scrap: int, _fuel: int, _r: bool) -> void: events.append(["bank", scrap]))
	var scrap_before := [0]
	_ride(sim, 400.0, _target_power, func(s: RunSimulation) -> void:
		if s.raids.state == RaidDirector.State.SCOUTING and s.lanes.target_lane != s.raids.exit_lane():
			s.request_lane_change(signi(s.raids.exit_lane() - s.lanes.target_lane))
		if s.raids.is_towing() and events.size() == 1:
			# Pościg taranuje pojazd z przyczepą.
			scrap_before[0] = s.raids.pending_scrap
			s.combat.ram_resolved.emit(RaiderModel.new(), CombatModel.RamOutcome.HIT, 0)
		if events.size() >= 3:
			s.raids.enabled = false)
	assert_eq(events.size(), 3, "ucieczka -> wysypany ładunek -> dowiezienie")
	if events.size() < 3:
		return
	assert_eq(events[0][0], "escape")
	assert_true(int(events[0][1]) > 0, "łup czeka na przyczepie, jeszcze nie w magazynie")
	assert_eq(events[1][0], "spill")
	assert_eq(int(events[1][1]), ceili(scrap_before[0] * RaidDirector.SPILL_FRACTION), "taranowanie wysypuje ćwierć ładunku")
	assert_eq(int(events[2][1]), scrap_before[0] - int(events[1][1]), "do magazynu trafia reszta")


func test_crashing_the_gate_costs_speed_and_sloppy_power_halves_loot() -> void:
	var out := _full_raid(func(_s: RunSimulation) -> float: return 320.0, false)
	var sim: RunSimulation = out["sim"]
	assert_eq(out["gate"], [RaidDirector.GateBreak.CRASH], "brama wyłamana na siłę")
	var base := int(sim.raids.current["loot_scrap"])
	assert_between(float(out["loot"]), base * 0.45, base * 0.6, "moc poza widełkami = pół skarbca")


func test_too_slow_means_repelled_with_no_loot() -> void:
	var out := _full_raid(func(s: RunSimulation) -> float: return 0.0 if s.raids.is_raiding() else 200.0, false)
	assert_true(out["repelled"], "nie dojechałeś do bramy = odparty")
	assert_eq(out["loot"], 0)
	assert_eq((out["sim"] as RunSimulation).expedition.raids_done, 0)


func test_tower_shells_can_be_dodged_or_blocked() -> void:
	var sim := _sim()
	sim.expedition.add_scrap(100)
	var landed: Array = []
	sim.raids.shell_landed.connect(func(_s: Dictionary, hit: bool, blocked: bool, lost: int) -> void: landed.append([hit, blocked, lost]))
	# Stoimy w miejscu na pasie zjazdu – pociski spadają przed nami (unik „z definicji”).
	_ride(sim, 90.0, _target_power, func(s: RunSimulation) -> void:
		s.combat.shield = 0.0
		if s.raids.state == RaidDirector.State.SCOUTING and s.lanes.target_lane != s.raids.exit_lane():
			s.request_lane_change(signi(s.raids.exit_lane() - s.lanes.target_lane)))
	var hits := landed.filter(func(l: Array) -> bool: return l[0])
	assert_true(landed.size() >= 2, "wieże strzelają (%d pocisków)" % landed.size())
	assert_true(hits.size() >= 1, "jazda prosto w ostrzał kończy się trafieniem")
	var unshielded := hits.filter(func(l: Array) -> bool: return not l[1])
	assert_true(unshielded.size() >= 1 and int(unshielded[0][2]) > 0, "bez tarczy trafienie kosztuje złom")


func test_no_settlement_when_the_run_is_about_to_end() -> void:
	var sim := RunSimulation.new(100.0, 9)
	sim.raids.enabled = true
	sim.raids.set_first_fork(300.0)
	var seen := [0]
	sim.raids.scouted.connect(func(_s: Dictionary) -> void: seen[0] += 1)
	_ride(sim, 110.0, _target_power)
	assert_eq(seen[0], 0, "za mało czasu na napad – brak zwiadu")
	assert_true(sim.expedition.finished)
