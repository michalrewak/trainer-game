extends TestCase


func _place_wreck_ahead(sim: RunSimulation, lane: int, ahead_m: float) -> TrackItem:
	sim.items.clear()
	var w := TrackItem.new(9001, TrackItem.Kind.WRECK, lane, sim.vehicle.distance_m + ahead_m, 0, 0)
	sim.items.append(w)
	return w


func _cruise(sim: RunSimulation, seconds: float, power_w: float, dt: float = 1.0 / 60.0) -> void:
	var t := 0.0
	while t < seconds:
		sim.step(dt, power_w)
		t += dt


func test_wreck_in_my_lane_costs_speed_and_scrap_but_not_the_run() -> void:
	var sim := RunSimulation.new(900.0, 1)
	sim.generator.warmup_m = 1e9
	_cruise(sim, 20.0, 200.0)
	sim.expedition.scrap = 0
	sim.expedition.add_scrap(40)
	var speed_before := sim.vehicle.speed_mps
	var hits: Array[int] = []
	sim.wreck_hit.connect(func(_item: TrackItem, lost: int) -> void: hits.append(lost))
	_place_wreck_ahead(sim, sim.lanes.target_lane, 3.0)
	sim.step(0.5, 200.0)
	assert_eq(hits.size(), 1, "jedno zderzenie")
	assert_eq(hits[0], 6, "utrata 15% z 40 (w górę)")
	assert_eq(sim.expedition.scrap, 34)
	assert_true(sim.vehicle.speed_mps < speed_before * 0.5, "utrata prędkości")
	assert_false(sim.expedition.finished, "zderzenie nie kończy wyprawy")


func test_wreck_in_other_lane_is_missed() -> void:
	var sim := RunSimulation.new(900.0, 1)
	_cruise(sim, 20.0, 200.0)
	var hits := [0]
	sim.wreck_hit.connect(func(_i: TrackItem, _l: int) -> void: hits[0] += 1)
	_place_wreck_ahead(sim, 0, 3.0)
	sim.step(0.5, 200.0)
	assert_eq(hits[0], 0, "wrak na sąsiednim pasie nie trafia")


func test_large_step_cannot_tunnel_through_wreck() -> void:
	var sim := RunSimulation.new(900.0, 1)
	_cruise(sim, 20.0, 300.0)
	var hits := [0]
	sim.wreck_hit.connect(func(_i: TrackItem, _l: int) -> void: hits[0] += 1)
	_place_wreck_ahead(sim, 1, 6.0)
	sim.step(2.0, 300.0)
	assert_eq(hits[0], 1, "przemiatanie łapie wrak przy dużym kroku")


func test_invulnerability_after_hit() -> void:
	var sim := RunSimulation.new(900.0, 1)
	_cruise(sim, 20.0, 200.0)
	var hits := [0]
	sim.wreck_hit.connect(func(_i: TrackItem, _l: int) -> void: hits[0] += 1)
	_place_wreck_ahead(sim, 1, 2.0)
	sim.step(0.2, 200.0)
	var second := TrackItem.new(9002, TrackItem.Kind.WRECK, 1, sim.vehicle.distance_m + 1.0, 0, 0)
	sim.items.append(second)
	sim.step(0.2, 200.0)
	assert_eq(hits[0], 1, "chwila nietykalności po zderzeniu")


func test_scrap_pickup_adds_value() -> void:
	var sim := RunSimulation.new(900.0, 1)
	_cruise(sim, 10.0, 200.0)
	sim.items.clear()
	sim.items.append(TrackItem.new(77, TrackItem.Kind.SCRAP_BIG, 1, sim.vehicle.distance_m + 2.0, 5, 0))
	var before := sim.expedition.scrap
	sim.step(0.5, 200.0)
	assert_eq(sim.expedition.scrap, before + 5, "duży złom = 5")


func test_run_ends_by_time_only() -> void:
	var sim := RunSimulation.new(120.0, 3)
	var done := [false]
	sim.finished.connect(func() -> void: done[0] = true)
	_cruise(sim, 119.0, 0.0, 0.25)
	assert_false(sim.expedition.finished, "bez mocy nadal jedziemy (stoimy), nie przegrywamy")
	_cruise(sim, 2.0, 200.0, 0.25)
	assert_true(done[0], "koniec po zadanym czasie")
	assert_near(sim.expedition.elapsed_s, 120.0, 0.001)


func test_full_15_minute_autopilot_run() -> void:
	var sim := RunSimulation.new(900.0, 12345)
	var pilot := Autopilot.new()
	var power := ScriptedPowerSource.new(210.0, 25.0)
	var dt := 1.0 / 30.0
	var t := 0.0
	while not sim.expedition.finished and t < 1000.0:
		power.update(dt)
		var dir := pilot.decide(sim, dt)
		if dir != 0:
			sim.request_lane_change(dir)
		sim.step(dt, power.get_power_watts())
		t += dt
	var s := sim.expedition.to_summary(true)
	assert_true(sim.expedition.finished, "wyprawa zakończona")
	assert_between(float(s["distance_m"]), 7000.0, 8600.0, "dystans 15 min przy ~210 W")
	assert_true(int(s["scrap"]) > 100, "autopilot zbiera złom (%d)" % int(s["scrap"]))
	assert_true(int(s["collisions"]) <= 15, "autopilot zwykle omija wraki (%d zderzeń)" % int(s["collisions"]))
	assert_true(sim.items.size() < 200, "obiekty za pojazdem są usuwane (%d)" % sim.items.size())
