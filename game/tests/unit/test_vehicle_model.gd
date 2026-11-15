extends TestCase


func _settle(v: VehicleModel, power_w: float, seconds: float, dt: float = 1.0 / 60.0) -> void:
	var t := 0.0
	while t < seconds:
		v.step(dt, power_w)
		t += dt


func test_steady_state_speed_table() -> void:
	var v := VehicleModel.new()
	# Wartości z rozwiązania równania P = (0.5*rho*CdA*v^2 + Crr*m*g) * v (km/h).
	var expected := {50: 16.7, 100: 23.2, 150: 27.5, 200: 30.9, 250: 33.7, 300: 36.2, 350: 38.4}
	for p in expected:
		assert_near(v.steady_state_speed(float(p)) * 3.6, expected[p], 0.15, "%d W" % p)


func test_simulation_converges_to_steady_state() -> void:
	var v := VehicleModel.new()
	_settle(v, 200.0, 60.0)
	assert_near(v.speed_mps, v.steady_state_speed(200.0), 0.05, "po 60 s przy 200 W")


func test_response_time_is_game_friendly() -> void:
	var v := VehicleModel.new()
	_settle(v, 200.0, 60.0)
	var target := v.steady_state_speed(300.0)
	var start := v.speed_mps
	var t := 0.0
	while v.speed_mps < start + 0.9 * (target - start) and t < 30.0:
		v.step(1.0 / 60.0, 300.0)
		t += 1.0 / 60.0
	assert_between(t, 2.5, 7.0, "czas do 90% nowej prędkości po 200->300 W [s]")


func test_more_power_is_faster() -> void:
	var v := VehicleModel.new()
	var last := 0.0
	for p in [25.0, 50.0, 100.0, 200.0, 300.0, 350.0, 600.0]:
		var s := v.steady_state_speed(p)
		assert_true(s > last, "monotoniczność przy %d W" % p)
		last = s


func test_coasting_slows_down_and_never_goes_negative() -> void:
	var v := VehicleModel.new()
	_settle(v, 200.0, 30.0)
	var before := v.speed_mps
	_settle(v, 0.0, 10.0)
	assert_true(v.speed_mps < before * 0.6, "toczenie się bez mocy zwalnia")
	_settle(v, 0.0, 200.0)
	assert_true(v.speed_mps >= 0.0, "prędkość nigdy ujemna")
	assert_near(v.speed_mps, 0.0, 0.05, "w końcu staje")


func test_distance_integrates_speed() -> void:
	var v := VehicleModel.new()
	_settle(v, 200.0, 60.0)
	var d0 := v.distance_m
	_settle(v, 200.0, 10.0)
	assert_near(v.distance_m - d0, v.speed_mps * 10.0, 0.5, "dystans = prędkość * czas")


func test_large_time_step_is_stable() -> void:
	var v := VehicleModel.new()
	v.step(5.0, 350.0)
	assert_true(v.speed_mps > 0.0 and v.speed_mps < v.steady_state_speed(350.0) + 0.01, "duży krok nie wybucha")


func test_impact_reduces_speed() -> void:
	var v := VehicleModel.new()
	_settle(v, 200.0, 60.0)
	var s := v.speed_mps
	v.apply_impact(0.35)
	assert_near(v.speed_mps, s * 0.35, 0.001)


func test_engine_multiplier_and_grade_hooks() -> void:
	var v := VehicleModel.new()
	var flat := v.steady_state_speed(200.0)
	v.engine_multiplier = 1.5
	assert_true(v.steady_state_speed(200.0) > flat, "ulepszenie silnika przyspiesza")
	v.engine_multiplier = 1.0
	v.grade = 0.05
	assert_true(v.steady_state_speed(200.0) < flat * 0.7, "podjazd 5% wyraźnie zwalnia")
