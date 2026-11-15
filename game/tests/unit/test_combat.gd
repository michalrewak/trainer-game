extends TestCase

const DT := 1.0 / 60.0


## Wyprawa bez wraków i bez automatycznych potyczek – wrogów dodajemy ręcznie.
func _quiet_sim(power_w: float = 200.0) -> RunSimulation:
	var sim := RunSimulation.new(900.0, 5)
	sim.generator.wrecks_enabled = false
	sim.items.clear()
	sim.combat.set_first_encounter(1e9)
	sim.combat.target_power_w = 200.0
	_run(sim, 20.0, power_w)
	return sim


func _run(sim: RunSimulation, seconds: float, power_w: float, on_step: Callable = Callable()) -> void:
	var t := 0.0
	while t < seconds:
		if on_step.is_valid():
			on_step.call(sim)
		sim.step(DT, power_w)
		t += DT


func test_supply_and_shield_follow_power() -> void:
	var sim := _quiet_sim(200.0)
	assert_near(sim.combat.supply_ratio(), 1.0, 0.02, "zasilanie przy mocy docelowej")
	assert_near(sim.combat.shield, 1.0, 0.001, "pełna tarcza po chwili trzymania mocy")
	sim.combat.shield = 0.2
	_run(sim, 10.0, 0.0)
	assert_true(sim.combat.supply_ratio() < 0.05, "bez mocy brak zasilania")
	assert_true(sim.combat.shield < 0.35, "bez mocy tarcza prawie się nie ładuje")


func test_fire_interval_scales_with_supply() -> void:
	var sim := _quiet_sim(200.0)
	var base := CombatModel.BASE_FIRE_INTERVAL_S
	sim.combat.supply = 1.0
	assert_near(sim.combat.fire_interval_s(), base, 0.001, "pełna moc = najszybszy ogień")
	sim.combat.supply = 0.5
	assert_near(sim.combat.fire_interval_s(), base * 2.0, 0.001)
	sim.combat.supply = 0.05
	assert_near(sim.combat.fire_interval_s(), base / 0.35, 0.001, "nawet bez mocy da się strzelać")


func _await_outcome(sim: RunSimulation, seconds: float, power_w: float, on_warning: Callable = Callable()) -> Array:
	var outcomes: Array = []
	sim.combat.ram_resolved.connect(func(_r: RaiderModel, outcome: int, lost: int) -> void: outcomes.append([outcome, lost]))
	if on_warning.is_valid():
		sim.combat.raider_warning.connect(func(r: RaiderModel) -> void: on_warning.call(r))
	var t := 0.0
	while t < seconds and outcomes.is_empty():
		sim.step(DT, power_w)
		t += DT
	return outcomes


func test_ram_pushes_player_and_steals_scrap() -> void:
	var sim := _quiet_sim(200.0)
	sim.expedition.add_scrap(50)
	sim.combat.shield = 0.0
	sim.combat.spawn_raider(-1)
	var lane_before := sim.lanes.target_lane
	var outcomes := _await_outcome(sim, 20.0, 0.0)
	assert_eq(outcomes.size(), 1, "jedna próba taranowania")
	if outcomes.is_empty():
		return
	assert_eq(outcomes[0][0], CombatModel.RamOutcome.HIT, "gracz został trafiony")
	assert_eq(outcomes[0][1], 5, "rabunek 10% z 50")
	assert_eq(sim.expedition.scrap, 45)
	assert_eq(sim.lanes.target_lane, lane_before + 1, "zepchnięty o pas od napastnika z lewej")
	assert_false(sim.expedition.finished, "potyczka nie kończy wyprawy")


func test_changing_lane_after_warning_dodges() -> void:
	var sim := _quiet_sim(200.0)
	sim.combat.shield = 0.0
	sim.combat.spawn_raider(-1)
	var outcomes := _await_outcome(sim, 20.0, 200.0, func(r: RaiderModel) -> void: sim.request_lane_change(-r.side))
	assert_eq(outcomes.size(), 1)
	if not outcomes.is_empty():
		assert_eq(outcomes[0][0], CombatModel.RamOutcome.DODGED, "zmiana pasa po ostrzeżeniu = unik")


func test_shield_blocks_ram() -> void:
	var sim := _quiet_sim(200.0)
	sim.expedition.add_scrap(30)
	sim.combat.shield = 1.0
	var r := sim.combat.spawn_raider(1)
	var outcomes := _await_outcome(sim, 20.0, 0.0)
	assert_eq(outcomes.size(), 1)
	if outcomes.is_empty():
		return
	assert_eq(outcomes[0][0], CombatModel.RamOutcome.BLOCKED, "tarcza zatrzymuje atak")
	assert_eq(sim.expedition.scrap, 30, "złom nietknięty")
	assert_true(sim.combat.shield < 0.7, "tarcza zużyta")
	assert_eq(r.hp, r.max_hp - 1, "napastnik obrywa od tarczy")


func test_turret_destroys_raider_and_drops_scrap() -> void:
	var sim := _quiet_sim(200.0)
	sim.combat.shield = 1.0
	sim.combat.fire_held = true
	var destroyed: Array = []
	sim.combat.raider_destroyed.connect(func(_r: RaiderModel, dropped: int, cause: int) -> void: destroyed.append([dropped, cause]))
	sim.combat.spawn_raider(-1)
	var items_before := sim.items.size()
	_run(sim, 12.0, 200.0)
	assert_eq(destroyed.size(), 1, "wróg zestrzelony")
	if destroyed.is_empty():
		return
	assert_eq(destroyed[0][1], CombatModel.DestroyCause.SHOT)
	assert_true(int(destroyed[0][0]) >= 3, "wypada złom")
	assert_true(sim.items.size() >= items_before + 3, "złom pojawia się na trasie")
	assert_eq(sim.expedition.raiders_destroyed, 1)


func test_raider_alongside_crashes_into_wreck() -> void:
	var sim := _quiet_sim(200.0)
	var destroyed: Array = []
	sim.combat.raider_destroyed.connect(func(_r: RaiderModel, _dropped: int, cause: int) -> void: destroyed.append(cause))
	var r := sim.combat.spawn_raider(-1)
	r.d = sim.vehicle.distance_m
	r.x = sim.lanes.lane_center(0)
	r.set_state(RaiderModel.State.SHADOW)
	sim.add_items([TrackItem.new(555, TrackItem.Kind.WRECK, 0, sim.vehicle.distance_m + 6.0, 0, 0)] as Array[TrackItem])
	_run(sim, 2.0, 200.0)
	assert_eq(destroyed, [CombatModel.DestroyCause.WRECK], "wróg rozbija się o wrak w swoim pasie")


func test_aim_picks_raider_in_stick_direction() -> void:
	var sim := _quiet_sim(200.0)
	var left := sim.combat.spawn_raider(-1)
	var right := sim.combat.spawn_raider(1)
	for r in [left, right]:
		r.d = sim.vehicle.distance_m + 2.0
		r.set_state(RaiderModel.State.SHADOW)
	left.x = -3.6
	right.x = 3.6
	sim.combat.aim = Vector2(1.0, 0.0)
	assert_eq(sim.combat.current_target(), right, "gałka w prawo = cel po prawej")
	sim.combat.aim = Vector2(-1.0, 0.0)
	assert_eq(sim.combat.current_target(), left, "gałka w lewo = cel po lewej")


func test_encounters_happen_and_never_end_the_run() -> void:
	var sim := RunSimulation.new(240.0, 77)
	sim.combat.target_power_w = 200.0
	var spawned := [0]
	sim.combat.raider_spawned.connect(func(_r: RaiderModel) -> void: spawned[0] += 1)
	var t := 0.0
	while not sim.expedition.finished and t < 300.0:
		sim.step(1.0 / 30.0, 120.0)
		t += 1.0 / 30.0
	assert_true(spawned[0] >= 1, "w 4 minuty pojawia się gang (%d)" % spawned[0])
	assert_true(sim.expedition.finished, "wyprawa kończy się po czasie mimo przegranych potyczek")
	assert_true(sim.expedition.scrap >= 0, "złom nigdy ujemny")
