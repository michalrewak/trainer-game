extends TestCase
## Płynne kierowanie lewą gałką ze wspomaganiem (obok skoku o pas krzyżakiem).

const DT := 1.0 / 60.0


func _steer(l: LaneModel, input: float, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		l.steer(input)
		l.step(DT)
		t += DT


func test_stick_moves_the_vehicle_continuously_between_lanes() -> void:
	var l := LaneModel.new()
	_steer(l, 0.4, 0.4)
	assert_between(l.x_m, 0.6, 1.7, "po chwili pojazd jest między pasami (x = %.2f m)" % l.x_m)
	assert_eq(l.target_lane, 1, "najbliższy pas to wciąż środkowy")
	assert_true(l.free_steering)
	assert_true(l.lateral_velocity_mps > 2.0, "prędkość boczna rośnie z wychyleniem")
	var x_half := l.x_m
	_steer(l, 1.0, 0.25)
	assert_true(l.x_m > x_half + 1.5, "pełne wychylenie skręca szybciej")
	assert_eq(l.target_lane, 2, "po przekroczeniu połowy drogi najbliższy jest prawy pas")


func test_assist_pulls_to_the_nearest_lane_after_release() -> void:
	var l := LaneModel.new()
	_steer(l, 0.6, 0.35)
	var released_at := l.x_m
	assert_true(absf(released_at - l.lane_center(l.current_lane())) > 0.3, "puszczone między pasami")
	var lane := l.current_lane()
	l.steer(0.0)
	l.step(DT)
	assert_true(l.assist_started, "pierwsza klatka po puszczeniu gałki")
	_steer(l, 0.0, 1.2)
	assert_near(l.x_m, l.lane_center(lane), 0.01, "wspomaganie dociągnęło do środka pasa")
	assert_false(l.free_steering)
	assert_false(l.assist_started)
	assert_near(l.lateral_velocity_mps, 0.0, 0.01)


func test_without_assist_the_vehicle_stays_where_it_was_left() -> void:
	var l := LaneModel.new()
	l.assist_enabled = false
	_steer(l, 0.6, 0.35)
	var x := l.x_m
	_steer(l, 0.0, 1.0)
	assert_near(l.x_m, x, 0.001, "bez wspomagania zostaje między pasami")
	assert_eq(l.target_lane, l.current_lane())


func test_road_edges_limit_steering() -> void:
	var l := LaneModel.new()
	_steer(l, -1.0, 3.0)
	assert_near(l.x_m, l.min_x(), 0.001, "lewa krawędź jezdni")
	assert_eq(l.target_lane, 0)
	_steer(l, 1.0, 3.0)
	assert_near(l.x_m, l.max_x(), 0.001, "prawa krawędź jezdni")
	assert_eq(l.target_lane, 2)


func test_dpad_jump_still_works_and_overrides_free_position() -> void:
	var l := LaneModel.new()
	_steer(l, 0.5, 0.3)
	l.steer(0.0)
	assert_true(l.request_change(-1) or l.target_lane == 0, "skok w lewo z pozycji między pasami")
	var want := l.target_lane
	_steer(l, 0.0, 1.0)
	assert_near(l.x_m, l.lane_center(want), 0.01, "skok kończy na środku pasa")
	assert_false(l.free_steering)


func test_assist_prefers_the_lane_without_a_wreck() -> void:
	var sim := RunSimulation.new(600.0, 6)
	sim.generator.wrecks_enabled = false
	sim.generator.crate_every_m = 1e9
	sim.items.clear()
	sim.combat.set_first_encounter(1e9)
	var t := 0.0
	while t < 15.0:
		sim.step(DT, 200.0)
		t += DT
	sim.items.clear()
	# Pojazd między środkowym a prawym pasem, trochę bliżej środkowego – a tam stoi wrak.
	sim.lanes.x_m = 1.2
	sim.lanes.target_lane = 1
	sim.add_items([TrackItem.new(1, TrackItem.Kind.WRECK, 1, sim.vehicle.distance_m + 13.0, 0, 0)] as Array[TrackItem])
	sim.steer(0.3)
	sim.step(DT, 200.0)
	sim.steer(0.0)
	t = 0.0
	while t < 1.5:
		sim.step(DT, 200.0)
		t += DT
	assert_eq(sim.lanes.target_lane, 2, "wspomaganie wybrało wolny pas")
	assert_eq(sim.expedition.collisions, 0, "wrak ominięty")
	assert_near(sim.lanes.x_m, sim.lanes.lane_center(2), 0.05)


func test_analog_dodge_also_counts_as_near_miss() -> void:
	var sim := RunSimulation.new(600.0, 6)
	sim.generator.wrecks_enabled = false
	sim.generator.crate_every_m = 1e9
	sim.items.clear()
	sim.combat.set_first_encounter(1e9)
	var t := 0.0
	while t < 15.0:
		sim.step(DT, 200.0)
		t += DT
	sim.items.clear()
	sim.add_items([TrackItem.new(1, TrackItem.Kind.WRECK, 1, sim.vehicle.distance_m + sim.vehicle.speed_mps * 0.85, 0, 0)] as Array[TrackItem])
	t = 0.0
	while t < 2.0:
		sim.steer(-1.0 if t < 0.45 else 0.0)
		sim.step(DT, 200.0)
		t += DT
	assert_eq(sim.expedition.collisions, 0)
	assert_eq(sim.expedition.near_misses, 1, "unik gałką w ostatniej chwili też się liczy")


func test_stick_curve_has_deadzone_and_keeps_sign() -> void:
	var controller: GDScript = load("res://scripts/run/run_controller.gd")
	assert_near(controller.steer_curve(0.1), 0.0, 1e-6, "drgania gałki w strefie martwej")
	assert_near(controller.steer_curve(-0.15), 0.0, 1e-6)
	assert_near(controller.steer_curve(1.0), 1.0, 1e-6)
	assert_near(controller.steer_curve(-1.0), -1.0, 1e-6)
	assert_true(controller.steer_curve(0.5) > 0.1 and controller.steer_curve(0.5) < 0.5, "łagodny początek")
	assert_true(controller.steer_curve(-0.6) < 0.0)


func test_input_map_separates_stick_from_dpad() -> void:
	for action: StringName in [&"lane_left", &"lane_right"]:
		for e in InputMap.action_get_events(action):
			assert_false(e is InputEventJoypadMotion, "%s: gałka nie skacze już o pas" % action)
	for action: StringName in [&"steer_left", &"steer_right"]:
		var has_axis := false
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadMotion and e.axis == JOY_AXIS_LEFT_X:
				has_axis = true
		assert_true(has_axis, "%s: lewa gałka" % action)


func test_suspension_speeds_up_steering_too() -> void:
	var sim := RunSimulation.new(600.0, 1)
	var base := sim.lanes.steer_speed_mps
	Loadout.new({UpgradeCatalog.SUSPENSION: 2}).apply_to(sim)
	assert_near(sim.lanes.steer_speed_mps, base * 1.6, 0.01, "zawieszenie przyspiesza też jazdę płynną")
