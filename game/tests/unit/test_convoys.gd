extends TestCase

const DT := 1.0 / 60.0

var _events: Array = []


## Wyprawa z konwojem na samym początku: bez wraków, zwykłych potyczek i eskorty.
func _sim() -> RunSimulation:
	var sim := RunSimulation.new(1800.0, 11)
	sim.generator.wrecks_enabled = false
	sim.items.clear()
	sim.combat.set_first_encounter(1e9)
	sim.combat.auto_fire = true
	sim.convoys.enabled = true
	sim.convoys.escorts_enabled = false
	sim.convoys.ftp_w = 200.0
	sim.convoys.set_first_at(1.0)
	_events = []
	return sim


func _ride(sim: RunSimulation, seconds: float, power: Variant, each: Callable = Callable(), until: Callable = Callable()) -> void:
	var t := 0.0
	while t < seconds and not sim.expedition.finished:
		if each.is_valid():
			each.call(sim)
		sim.combat.target_power_w = sim.convoys.target_w() if sim.convoys.is_active() else 200.0
		var w: float = float(power.call(sim)) if power is Callable else float(power)
		sim.step(DT, w)
		t += DT
		if until.is_valid() and until.call(sim):
			return


## Moc trzymająca pełne zasilanie działka w każdej fazie konwoju.
func _fire_power(sim: RunSimulation) -> float:
	return maxf(sim.convoys.target_w(), 60.0)


## Dojeżdża do konwoju i zaczyna walkę (stan ENGAGED).
func _engage(sim: RunSimulation) -> ConvoyDirector:
	var c := sim.convoys
	_ride(sim, 90.0, 260.0, Callable(), func(s: RunSimulation) -> bool: return s.convoys.state == ConvoyDirector.State.ENGAGED)
	assert_eq(c.state, ConvoyDirector.State.ENGAGED, "konwój dogoniony")
	return c


## Ustawia gracza na bocznym pasie na wysokości podanej części (jak po idealnej jeździe).
func _beside(sim: RunSimulation, part: RaiderModel, offset_m: float = 0.0) -> void:
	sim.lanes.target_lane = 0
	sim.lanes.x_m = sim.lanes.lane_center(0)
	sim.vehicle.distance_m = part.d + offset_m


func _cut(sim: RunSimulation, front: bool) -> void:
	var c := sim.convoys
	var hitch := c.hitch_front if front else c.hitch_rear
	_ride(sim, 30.0, _fire_power, func(s: RunSimulation) -> void: _beside(s, hitch),
		func(_s: RunSimulation) -> bool: return not hitch.is_alive())
	assert_false(hitch.is_alive(), "sprzęg %s przestrzelony" % ("przedni" if front else "tylny"))


func _board(sim: RunSimulation) -> void:
	_ride(sim, 20.0, 40.0, func(s: RunSimulation) -> void:
		if s.convoys.galley != null:
			_beside(s, s.convoys.galley),
		func(s: RunSimulation) -> bool: return not s.convoys.is_active())


func test_convoy_is_sighted_ahead_and_caught_with_power() -> void:
	var sim := _sim()
	var c := sim.convoys
	_ride(sim, 3.0, 200.0)
	assert_eq(c.state, ConvoyDirector.State.CHASE, "konwój widać po czasie startu")
	assert_near(c.gap_m(), ConvoyDirector.SIGHT_GAP_M, 15.0, "pojawia się daleko z przodu")
	assert_eq(sim.combat.live_raiders().size(), 5, "ciągnik, galera, ogon i dwa sprzęgi")
	var gap0 := c.gap_m()
	_ride(sim, 8.0, 260.0)
	assert_true(c.gap_m() < gap0 - 15.0, "mocna jazda zmniejsza odstęp (%.0f -> %.0f m)" % [gap0, c.gap_m()])
	_engage(sim)
	assert_true(c.pace_fast, "po dogonieniu konwój dodaje gazu")


func test_convoy_escapes_when_power_is_too_low() -> void:
	var sim := _sim()
	sim.convoys.finished.connect(func(_i: Dictionary, r: Dictionary) -> void: _events.append(r["outcome"]))
	_ride(sim, 120.0, 110.0, Callable(), func(s: RunSimulation) -> bool: return not _events.is_empty())
	assert_eq(_events, [ConvoyDirector.Outcome.OUTRUN], "za mało mocy – konwój uciekł")
	assert_eq(sim.expedition.convoys_lost, 1)
	assert_eq(sim.combat.live_raiders().size(), 0, "po ucieczce nic nie zostaje na drodze")


func test_hitch_is_exposed_only_from_the_side_and_up_close() -> void:
	var sim := _sim()
	var c := _engage(sim)
	_beside(sim, c.hitch_rear)
	sim.step(DT, 200.0)
	assert_true(c.hitch_rear.exposed, "z boku, na wysokości sprzęgu – widać go")
	assert_eq(c.open_window(), 1)
	assert_false(c.hitch_front.exposed, "przedni sprzęg jest dalej z przodu")
	_beside(sim, c.hitch_rear, -ConvoyDirector.WINDOW_BACK_M - 3.0)
	sim.step(DT, 200.0)
	assert_false(c.hitch_rear.exposed, "za daleko z tyłu – ogon zasłania sprzęg")
	_beside(sim, c.hitch_rear, ConvoyDirector.WINDOW_FRONT_M + 2.0)
	sim.step(DT, 200.0)
	assert_false(c.hitch_rear.exposed, "za daleko z przodu – sprzęg został za plecami")
	_beside(sim, c.hitch_rear, -ConvoyDirector.WINDOW_BACK_M - 3.0)
	sim.step(DT, 200.0)
	assert_true(c.guard.exposed, "za to ogon można ostrzeliwać")
	assert_false(c.tractor.exposed, "ciągnik jest poza zasięgiem")
	assert_false(c.galley.exposed, "automat nigdy nie celuje w klatkę z ludźmi")
	_beside(sim, c.hitch_front)
	sim.step(DT, 200.0)
	assert_eq(c.open_window(), 2, "na wysokości przedniego sprzęgu otwiera się przednie okno")


func test_cutting_rear_hitch_drops_the_guard_and_stops_mines() -> void:
	var sim := _sim()
	var c := _engage(sim)
	c.guard_lost.connect(func(destroyed: bool) -> void: _events.append(destroyed))
	_cut(sim, false)
	sim.step(DT, 200.0)
	assert_eq(_events, [false], "ogon odczepiony, nie rozbity")
	assert_false(c.guard_attached)
	assert_eq(c.clean_cuts, 1)
	assert_eq(c.galley.hits_taken, 0, "żaden pocisk nie poszedł w klatkę")
	assert_eq(c.state, ConvoyDirector.State.ENGAGED, "ciągnik dalej ciągnie galerę")
	var guard := c.guard
	var gap_before := c.galley.d - guard.d
	_ride(sim, 2.0, 200.0, func(s: RunSimulation) -> void: _beside(s, s.convoys.galley))
	assert_true(c.galley.d - guard.d > gap_before + 5.0, "odczepiony ogon zostaje w tyle")
	c.mine_dropped.connect(func(_m: Dictionary) -> void: _events.append("mina"))
	_ride(sim, 12.0, 200.0, func(s: RunSimulation) -> void:
		s.lanes.target_lane = 0
		s.lanes.x_m = s.lanes.lane_center(0)
		s.vehicle.distance_m = s.convoys.galley.d - 30.0)
	assert_false(_events.has("mina"), "bez ogona nikt nie zrzuca min")


func test_front_hitch_frees_the_galley_and_boarding_pays_out() -> void:
	var sim := _sim()
	var c := _engage(sim)
	c.capture_started.connect(func(jackpot: bool) -> void: _events.append(jackpot))
	c.finished.connect(func(_i: Dictionary, r: Dictionary) -> void: _events.append(r))
	_cut(sim, true)
	sim.step(DT, 200.0)
	assert_eq(c.state, ConvoyDirector.State.CAPTURE, "galera odcięta – czas na przesiadkę")
	assert_eq(_events, [false])
	var scrap_before := sim.expedition.scrap
	_board(sim)
	var result: Dictionary = _events[1]
	assert_eq(result["outcome"], ConvoyDirector.Outcome.CAPTURED)
	assert_true(result["guard_hangs"], "droga na skróty: ogon dalej wisi na zdobyczy")
	assert_eq(int(result["scrap"]), 105, "70% łupu z cysterny (150)")
	assert_eq(sim.expedition.scrap - scrap_before, 105)
	assert_eq(sim.expedition.fuel, 3)
	assert_eq(sim.expedition.pedalers_freed, 2)
	assert_eq(sim.expedition.convoys_captured, 1)
	assert_false(sim.combat.wall_active, "po konwoju środkowy pas znów jest wolny")


func test_surgical_cut_gives_full_loot_and_extra_pedaler() -> void:
	var sim := _sim()
	var c := _engage(sim)
	c.finished.connect(func(_i: Dictionary, r: Dictionary) -> void: _events.append(r))
	_cut(sim, false)
	_cut(sim, true)
	_board(sim)
	var result: Dictionary = _events[0]
	assert_true(result["clean"], "oba sprzęgi przestrzelone")
	assert_eq(int(result["scrap"]), 150, "pełny łup")
	assert_eq(int(result["freed"]), 3, "dwóch z klatki i jeden za czystą robotę")


func test_destroying_the_tractor_is_a_jackpot() -> void:
	var sim := _sim()
	var c := _engage(sim)
	sim.combat.projectile_damage = 10
	c.finished.connect(func(_i: Dictionary, r: Dictionary) -> void: _events.append(r))
	var tractor := c.tractor
	_ride(sim, 30.0, _fire_power, func(s: RunSimulation) -> void: _beside(s, tractor),
		func(_s: RunSimulation) -> bool: return not tractor.is_alive())
	assert_false(tractor.is_alive(), "ciągnik rozbity")
	sim.step(DT, 200.0)
	assert_true(c.jackpot)
	assert_eq(c.state, ConvoyDirector.State.CAPTURE)
	_board(sim)
	var result: Dictionary = _events[0]
	assert_true(result["jackpot"])
	assert_eq(int(result["scrap"]), roundi(150.0 * 1.5 * 0.7), "łup x1,5, ale ogon wisi")
	assert_eq(int(result["fuel"]), 5, "dwa kanistry z ciągnika ekstra")


func test_shooting_the_cage_costs_freed_pedalers() -> void:
	var sim := _sim()
	var c := _engage(sim)
	c.cage_hit.connect(func(left: int) -> void: _events.append(left))
	assert_eq(c.freed_now(), 2)
	c.galley.hits_taken = 3
	sim.step(DT, 200.0)
	assert_eq(_events, [1], "trzy trafienia w klatkę = jeden uwolniony mniej")
	assert_true(c.galley.is_alive(), "wagonu z ludźmi nie da się rozbić")
	c.galley.hits_taken = 30
	sim.step(DT, 200.0)
	assert_eq(c.freed_now(), 0, "nigdy poniżej zera")


func test_free_shot_into_the_cage_is_counted() -> void:
	var sim := _sim()
	var c := _engage(sim)
	sim.combat.auto_fire = false
	_beside(sim, c.galley)
	# Gałka w prawo: strzał z lewego pasa prosto w klatkę.
	sim.combat.aim = Vector2(1.0, 0.0)
	sim.combat.fire_held = true
	_ride(sim, 2.0, _fire_power, func(s: RunSimulation) -> void: _beside(s, s.convoys.galley))
	assert_true(c.galley.hits_taken > 0, "ręczny strzał w klatkę trafia w ludzi")


func test_pace_alternates_between_sprint_and_braking() -> void:
	var sim := _sim()
	var c := _engage(sim)
	c.pace_changed.connect(func(fast: bool) -> void: _events.append(fast))
	c.pace_warning.connect(func(fast: bool) -> void: _events.append("uwaga:%s" % fast))
	var hold := {"fast": 0.0, "slow": 0.0}
	_ride(sim, 45.0, 200.0, func(s: RunSimulation) -> void:
		s.lanes.target_lane = 0
		s.lanes.x_m = s.lanes.lane_center(0)
		s.vehicle.distance_m = s.convoys.galley.d - 30.0
		if s.convoys.pace_left_s() < 3.0:
			hold["fast" if s.convoys.pace_fast else "slow"] = s.convoys.hold_power_w())
	assert_true(_events.has(false) and _events.has(true), "konwój na zmianę hamuje i ucieka: %s" % str(_events))
	assert_true(_events.find("uwaga:false") < _events.find(false), "ostrzeżenie przychodzi przed zmianą tempa")
	assert_near(hold["fast"], 200.0, 12.0, "sprint konwoju = około FTP na wzorcowym pojeździe")
	assert_near(hold["slow"], 110.0, 10.0, "hamowanie = około 55% FTP")
	assert_true(c.target_w() > 0.0)


func test_accelerators_lower_the_power_needed_to_hold_the_convoy() -> void:
	var sim := _sim()
	var c := _engage(sim)
	var plain := c.hold_power_w()
	sim.vehicle.engine_multiplier = 1.25
	sim.power_train.crew = 4
	assert_near(c.hold_power_w(), plain / (1.25 * 1.08), 0.5, "generator i załoga zdejmują waty z nóg")
	assert_true(sim.trigger_boost())
	assert_true(c.hold_power_w() < plain / (1.25 * 1.08) - 10.0, "dopalacz pomaga jeszcze bardziej")


func test_guard_drops_mines_on_players_lane() -> void:
	var sim := _sim()
	var c := _engage(sim)
	c.mine_dropped.connect(func(m: Dictionary) -> void: _events.append(m))
	var follow := func(s: RunSimulation) -> void:
		s.vehicle.distance_m = s.convoys.guard.d - ConvoyDirector.GUARD_HALF_M - 25.0
	_ride(sim, 8.0, 200.0, follow, func(_s: RunSimulation) -> bool: return not _events.is_empty())
	assert_eq(_events.size(), 1, "strażnik zrzucił minę")
	var mine: Dictionary = _events[0]
	assert_eq(int(mine["lane"]), sim.lanes.target_lane, "mina leci na pas gracza")
	assert_true(float(mine["d"]) > sim.vehicle.distance_m, "ląduje przed graczem")
	# Unik: zmiana pasa przed wybuchem.
	var results: Array = []
	c.mine_exploded.connect(func(_m: Dictionary, hit: bool, blocked: bool, lost: int) -> void: results.append([hit, blocked, lost]))
	sim.request_lane_change(-1)
	_ride(sim, 3.0, 200.0, Callable(), func(_s: RunSimulation) -> bool: return not results.is_empty())
	assert_eq(results[0][0], false, "po zmianie pasa mina wybucha obok")
	# Bez uniku i bez tarczy: mina trafia, zwalnia i zabiera złom.
	sim.expedition.add_scrap(100)
	results.clear()
	c.mines.append({"id": 99, "lane": sim.lanes.target_lane, "d": sim.vehicle.distance_m + 1.0, "t_left": 0.01})
	sim.combat.shield = 0.0
	var v := sim.vehicle.speed_mps
	sim.step(DT, 200.0)
	assert_eq(results[0][0], true)
	assert_true(sim.vehicle.speed_mps < v * 0.7, "wybuch wyhamowuje")
	assert_true(int(results[0][2]) > 0, "i zabiera trochę złomu")
	# Z tarczą: mina zatrzymana.
	results.clear()
	c.mines.append({"id": 100, "lane": sim.lanes.target_lane, "d": sim.vehicle.distance_m + 1.0, "t_left": 0.01})
	sim.combat.shield = 1.0
	sim.step(DT, 200.0)
	assert_eq(results[0][1], true, "tarcza zatrzymuje minę")


func test_ramming_the_tail_slows_the_player() -> void:
	var sim := _sim()
	var c := _engage(sim)
	c.bumped.connect(func(squeezed: bool) -> void: _events.append(squeezed))
	sim.lanes.target_lane = 1
	sim.lanes.x_m = 0.0
	sim.vehicle.distance_m = c.guard.d - ConvoyDirector.GUARD_HALF_M - sim.vehicle_half_length_m + 0.4
	var v := sim.vehicle.speed_mps
	sim.step(DT, 200.0)
	assert_eq(_events, [false], "wjechanie w tył ogona")
	assert_true(sim.vehicle.speed_mps < v * 0.7, "kolce na zderzaku wyhamowują")
	assert_true(c.gap_m() > 0.0, "po zderzeniu pojazdy się nie przenikają")
	# Wciśnięcie się między wagony odbija na boczny pas.
	_events.clear()
	_ride(sim, 2.0, 200.0)
	sim.lanes.target_lane = 1
	sim.lanes.x_m = 0.0
	sim.vehicle.distance_m = c.galley.d
	sim.step(DT, 200.0)
	assert_eq(_events, [true])
	assert_true(sim.lanes.target_lane != 1, "odbity z pasa konwoju")


func test_capture_requires_slowing_down() -> void:
	var sim := _sim()
	var c := _engage(sim)
	c.finished.connect(func(_i: Dictionary, r: Dictionary) -> void: _events.append(r))
	_cut(sim, true)
	sim.step(DT, 200.0)
	assert_eq(c.state, ConvoyDirector.State.CAPTURE)
	# Gracz nie odpuszcza: odjeżdża od stającego wagonu i traci większość łupu.
	_ride(sim, 60.0, 260.0, Callable(), func(_s: RunSimulation) -> bool: return not _events.is_empty())
	var result: Dictionary = _events[0]
	assert_eq(result["outcome"], ConvoyDirector.Outcome.PARTIAL, "za szybko – wagon został w tyle")
	assert_eq(int(result["freed"]), 0)
	assert_eq(int(result["scrap"]), roundi(150.0 * 0.7 * 0.4))


func test_easing_off_keeps_the_player_at_the_wagon() -> void:
	var sim := _sim()
	var c := _engage(sim)
	c.finished.connect(func(_i: Dictionary, r: Dictionary) -> void: _events.append(r))
	_cut(sim, true)
	# Prawdziwa jazda (bez przestawiania pozycji): odpuszczenie do 30 W wystarcza na przesiadkę.
	_ride(sim, 40.0, 30.0, Callable(), func(_s: RunSimulation) -> bool: return not _events.is_empty())
	assert_eq(_events.size(), 1, "przesiadka zakończona")
	assert_eq((_events[0] as Dictionary)["outcome"], ConvoyDirector.Outcome.CAPTURED, "zwolnienie = przejęta galera")


func test_convoy_reaches_the_fortress_after_time_limit() -> void:
	var sim := _sim()
	var c := _engage(sim)
	c.finished.connect(func(_i: Dictionary, r: Dictionary) -> void: _events.append(r["outcome"]))
	_ride(sim, ConvoyDirector.ENGAGE_LIMIT_S + 5.0, 200.0, func(s: RunSimulation) -> void:
		if s.convoys.galley != null:
			s.lanes.target_lane = 0
			s.lanes.x_m = s.lanes.lane_center(0)
			s.vehicle.distance_m = s.convoys.galley.d - 45.0,
		func(_s: RunSimulation) -> bool: return not _events.is_empty())
	assert_eq(_events, [ConvoyDirector.Outcome.FORTRESS], "konwój dojechał do twierdzy")


func test_overtaking_far_ahead_loses_the_convoy() -> void:
	var sim := _sim()
	var c := _engage(sim)
	c.finished.connect(func(_i: Dictionary, r: Dictionary) -> void: _events.append(r["outcome"]))
	sim.lanes.target_lane = 0
	sim.lanes.x_m = sim.lanes.lane_center(0)
	sim.vehicle.distance_m = c.galley.d + ConvoyDirector.PASSED_REL_M + 5.0
	sim.step(DT, 200.0)
	assert_eq(_events, [ConvoyDirector.Outcome.PASSED])


func test_convoy_holds_off_raids_challenges_and_gang_encounters() -> void:
	var sim := _sim()
	sim.raids.enabled = true
	sim.raids.set_first_fork(700.0)
	sim.combat.set_first_encounter(20.0)
	var c := _engage(sim)
	_ride(sim, 40.0, 200.0, func(s: RunSimulation) -> void:
		if s.convoys.galley != null:
			s.lanes.target_lane = 0
			s.lanes.x_m = s.lanes.lane_center(0)
			s.vehicle.distance_m = s.convoys.galley.d - 45.0)
	assert_true(c.is_active())
	assert_eq(sim.raids.state, RaidDirector.State.IDLE, "bez zwiadu podczas konwoju")
	var cars := 0
	for r in sim.combat.live_raiders():
		if not r.is_convoy_part():
			cars += 1
	assert_eq(cars, 0, "zwykłe potyczki czekają (eskorta wyłączona w teście)")


func test_escorts_arrive_from_the_outer_side() -> void:
	var sim := _sim()
	sim.convoys.escorts_enabled = true
	var c := _engage(sim)
	_ride(sim, 6.0, 200.0, func(s: RunSimulation) -> void: _beside(s, s.convoys.hitch_rear, -3.0))
	var escorts: Array[RaiderModel] = []
	for r in sim.combat.live_raiders():
		if not r.is_convoy_part():
			escorts.append(r)
	assert_true(escorts.size() >= 1, "eskorta dojechała")
	assert_eq(escorts[0].side, -1, "gracz na lewym pasie – eskorta z lewego pobocza")
	assert_true(c.is_active())


func test_second_convoy_is_a_tier_heavier_and_tier_follows_chassis() -> void:
	var sim := _sim()
	var c := sim.convoys
	c.gap_s = 5.0
	_ride(sim, 3.0, 200.0)
	assert_eq(str(c.info["name"]), "Cysterna Tłustych")
	_ride(sim, 120.0, 100.0, Callable(), func(s: RunSimulation) -> bool: return not s.convoys.is_active())
	_ride(sim, 10.0, 200.0, Callable(), func(s: RunSimulation) -> bool: return s.convoys.is_active())
	assert_eq(int(c.info["tier"]), 1, "drugi konwój wyprawy jest cięższy")
	var big := _sim()
	Loadout.new({UpgradeCatalog.CHASSIS: 2}).apply_to(big)
	_ride(big, 3.0, 200.0)
	assert_eq(int(big.convoys.info["tier"]), 2, "krążownik spotyka Skarbiec Barona")
