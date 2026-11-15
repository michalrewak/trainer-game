extends TestCase


func test_defaults() -> void:
	var o := LaunchOptions.parse(PackedStringArray())
	assert_near(o.minutes, 15.0, 0.001, "domyślnie 15 min")
	assert_false(o.autostart)
	assert_false(o.autopilot)
	assert_near(o.duration_s(), 900.0, 0.001)


func test_parse_flags() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--minutes=2", "--autostart", "--autopilot", "--time-scale=8", "--seed=77", "--quit-on-finish", "--save=user://x.json", "--shot-times=1,5.5"]))
	assert_near(o.minutes, 2.0, 0.001)
	assert_true(o.minutes_from_cli)
	assert_true(o.autostart and o.autopilot and o.quit_on_finish)
	assert_near(o.time_scale, 8.0, 0.001)
	assert_eq(o.seed_value, 77)
	assert_eq(o.save_path, "user://x.json")
	assert_eq(o.shot_times.size(), 2)
	assert_near(o.shot_times[1], 5.5, 0.001)


func test_test_flag_is_two_minutes_and_garbage_is_ignored() -> void:
	var o := LaunchOptions.parse(PackedStringArray(["--test", "--minutes=abc", "--whatever"]))
	assert_near(o.minutes, 2.0, 0.001)


func test_factory_returns_power_sources() -> void:
	var pad := PowerSourceFactory.create(PowerSourceFactory.KIND_GAMEPAD)
	assert_true(pad is PowerSource and pad is GamepadPowerSource)
	var auto := PowerSourceFactory.create(PowerSourceFactory.KIND_AUTOPILOT)
	assert_true(auto is PowerSource and auto is ScriptedPowerSource)
	assert_eq(auto.get_status(), PowerSource.Status.ACTIVE)


func test_scripted_source_produces_power_and_cadence() -> void:
	var s := ScriptedPowerSource.new(200.0, 0.0)
	s.update(1.0)
	assert_near(s.get_power_watts(), 200.0, 0.001)
	assert_between(s.get_cadence(), 70.0, 95.0)
