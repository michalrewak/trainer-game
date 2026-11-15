extends TestCase


func _run(model: ManualPowerModel, seconds: float, trigger: float, dt: float = 1.0 / 60.0) -> void:
	var t := 0.0
	while t < seconds:
		model.step(dt, trigger)
		t += dt


func test_full_trigger_reaches_350w_smoothly() -> void:
	var m := ManualPowerModel.new()
	m.step(1.0 / 60.0, 1.0)
	assert_true(m.get_power() < 50.0, "wygładzanie: po jednej klatce moc nie skacze do 350 W")
	_run(m, 4.0, 1.0)
	assert_near(m.get_power(), 350.0, 1.0, "pełny trigger")


func test_half_trigger_is_175w() -> void:
	var m := ManualPowerModel.new()
	_run(m, 5.0, 0.5)
	assert_near(m.get_power(), 175.0, 1.0, "pół triggera")


func test_released_trigger_decays_to_zero() -> void:
	var m := ManualPowerModel.new()
	_run(m, 4.0, 1.0)
	_run(m, 5.0, 0.0)
	assert_near(m.get_power(), 0.0, 0.5, "po puszczeniu")


func test_cruise_locks_current_power() -> void:
	var m := ManualPowerModel.new()
	_run(m, 5.0, 0.6)
	m.toggle_cruise()
	assert_true(m.cruise_locked)
	assert_near(m.cruise_watts, 210.0, 0.01, "zablokowana moc zaokrąglona do 5 W")
	_run(m, 5.0, 0.0)
	assert_near(m.get_power(), 210.0, 0.5, "tempomat trzyma moc bez triggera")


func test_trigger_can_push_above_cruise() -> void:
	var m := ManualPowerModel.new()
	_run(m, 5.0, 0.4)
	m.toggle_cruise()
	_run(m, 5.0, 1.0)
	assert_near(m.get_power(), 350.0, 1.0, "docisk triggera ponad tempomat")
	_run(m, 5.0, 0.0)
	assert_near(m.get_power(), m.cruise_watts, 0.5, "po puszczeniu wraca do tempomatu")


func test_unlock_returns_to_trigger() -> void:
	var m := ManualPowerModel.new()
	_run(m, 5.0, 0.6)
	m.toggle_cruise()
	m.toggle_cruise()
	assert_false(m.cruise_locked)
	_run(m, 5.0, 0.0)
	assert_near(m.get_power(), 0.0, 0.5, "bez tempomatu i triggera moc spada do 0")


func test_nudge_engages_cruise_and_steps_10w() -> void:
	var m := ManualPowerModel.new()
	m.nudge(1)
	assert_true(m.cruise_locked, "W włącza tempomat")
	assert_near(m.cruise_watts, 10.0, 0.01)
	for i in 19:
		m.nudge(1)
	assert_near(m.cruise_watts, 200.0, 0.01)
	m.nudge(-1)
	assert_near(m.cruise_watts, 190.0, 0.01)
	_run(m, 5.0, 0.0)
	assert_near(m.get_power(), 190.0, 0.5)


func test_nudge_clamps_to_limits() -> void:
	var m := ManualPowerModel.new()
	m.nudge(-1)
	assert_near(m.cruise_watts, 0.0, 0.01, "nie schodzimy poniżej 0 W")
	for i in 200:
		m.nudge(1)
	assert_near(m.cruise_watts, m.max_watts, 0.01, "górny limit")


func test_trigger_input_is_clamped() -> void:
	var m := ManualPowerModel.new()
	_run(m, 5.0, 3.0)
	assert_near(m.get_power(), 350.0, 1.0)
	_run(m, 5.0, -2.0)
	assert_near(m.get_power(), 0.0, 0.5)


func test_trigger_band_reaches_full_power_before_hardware_max() -> void:
	assert_near(GamepadPowerSource.band(0.0), 0.0, 1e-6, "spoczynek")
	assert_near(GamepadPowerSource.band(0.03), 0.0, 1e-6, "martwa strefa")
	assert_near(GamepadPowerSource.band(0.97), 1.0, 1e-6, "pełna moc przed 1.0")
	assert_near(GamepadPowerSource.band(1.0), 1.0, 1e-6)
	assert_near(GamepadPowerSource.band(0.505), 0.5, 0.001, "środek pasma")


func test_digital_trigger_ramp_raises_cruise_and_holds() -> void:
	var m := ManualPowerModel.new()
	m.ramp(2.0, 40.0)
	assert_true(m.cruise_locked, "rampa włącza tempomat")
	assert_near(m.cruise_watts, 80.0, 0.01)
	_run(m, 5.0, 0.0)
	assert_near(m.get_power(), 80.0, 0.5, "po puszczeniu moc zostaje")
	m.ramp(100.0, 40.0)
	assert_near(m.cruise_watts, 350.0, 0.01, "rampa nie przekracza zakresu triggera")


func test_cadence_is_zero_without_power_and_plausible_at_200w() -> void:
	var m := ManualPowerModel.new()
	_run(m, 5.0, 0.0)
	assert_eq(m.get_cadence(), 0.0, "kadencja bez mocy")
	_run(m, 10.0, 200.0 / 350.0)
	assert_between(m.get_cadence(), 75.0, 95.0, "kadencja przy 200 W")
