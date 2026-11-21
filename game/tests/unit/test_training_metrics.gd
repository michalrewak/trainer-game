extends TestCase


func _ride(m: TrainingMetrics, seconds: float, power_w: float, dt: float = 0.25) -> void:
	var t := 0.0
	while t < seconds:
		m.tick(dt, power_w)
		t += dt


func test_zones_follow_ftp() -> void:
	assert_eq(TrainingMetrics.zone_index(100.0, 200.0), 0, "50% FTP = Z1")
	assert_eq(TrainingMetrics.zone_index(140.0, 200.0), 1, "70% = Z2")
	assert_eq(TrainingMetrics.zone_index(170.0, 200.0), 2, "85% = Z3")
	assert_eq(TrainingMetrics.zone_index(200.0, 200.0), 3, "100% = Z4 próg")
	assert_eq(TrainingMetrics.zone_index(230.0, 200.0), 4, "115% = Z5")
	assert_eq(TrainingMetrics.zone_index(280.0, 200.0), 5, "140% = Z6")
	assert_eq(TrainingMetrics.zone_index(400.0, 200.0), 6, "200% = Z7")
	assert_eq(TrainingMetrics.zone_index(200.0, 250.0), 2, "ta sama moc przy wyższym FTP to niższa strefa")


func test_one_hour_at_ftp_is_100_tss() -> void:
	var m := TrainingMetrics.new(200.0)
	_ride(m, 3600.0, 200.0, 1.0)
	assert_near(m.normalized_power(), 200.0, 0.5, "NP przy stałej mocy = ta moc")
	assert_near(m.intensity_factor(), 1.0, 0.005)
	assert_near(m.tss(), 100.0, 0.5, "godzina na progu = 100 TSS")
	assert_near(m.zone_s[3], 3600.0, 1.0, "cały czas w Z4")


func test_steady_endurance_ride() -> void:
	var m := TrainingMetrics.new(200.0)
	_ride(m, 1800.0, 140.0, 1.0)
	assert_near(m.intensity_factor(), 0.7, 0.005)
	assert_near(m.tss(), 24.5, 0.3, "30 min na 70% FTP = 0,5 h * 0,49 * 100")


func test_intervals_raise_np_above_average_power() -> void:
	var m := TrainingMetrics.new(200.0)
	for i in 5:
		_ride(m, 240.0, 260.0, 1.0)
		_ride(m, 240.0, 80.0, 1.0)
	var avg := (260.0 + 80.0) / 2.0
	assert_true(m.normalized_power() > avg + 15.0, "NP (%d W) wyższa od średniej (%d W)" % [roundi(m.normalized_power()), roundi(avg)])
	assert_near(m.zone_s[5], 1200.0, 2.0, "20 min w Z6")
	assert_near(m.zone_s[0], 1200.0, 2.0, "20 min w Z1")


func test_expedition_summary_carries_training_values() -> void:
	var e := Expedition.new(600.0)
	e.metrics.ftp_w = 250.0
	e.tick(600.0, 250.0, 9.0, 5400.0)
	var s := e.to_summary(true)
	for key in ["np_w", "intensity_factor", "tss", "zones_s", "ftp_w"]:
		assert_true(s.has(key), "podsumowanie ma pole %s" % key)
	assert_eq(s["np_w"], 250)
	assert_near(float(s["tss"]), 16.7, 0.2, "10 min na progu")
	assert_eq((s["zones_s"] as Array).size(), 7)


func test_ranks_and_slogans() -> void:
	assert_eq(Lore.rank(100.0)["name"], "Piechur")
	assert_eq(Lore.rank(200.0)["name"], "Lokomotywa")
	assert_eq(int(Lore.rank(200.0)["next_at"]), 240, "następna ranga od 240 W")
	assert_eq(int(Lore.rank(400.0)["next_at"]), 0, "na szczycie nie ma następnej")
	assert_true(Lore.slogan(0).length() > 10)
	assert_eq(Lore.slogan(Lore.SLOGANS.size()), Lore.slogan(0), "hasła się zawijają")


func test_recent_stats_count_only_last_week() -> void:
	var s := ProgressStore.new("user://test_saves/%d/week.json" % OS.get_process_id())
	var now := Time.get_datetime_string_from_system(false, true)
	s.record_run({"scrap": 1, "energy_kj": 300, "tss": 40.0, "duration_s": 1800}, now)
	s.record_run({"scrap": 1, "energy_kj": 500, "tss": 60.0, "duration_s": 3600}, "2020-01-01 10:00:00")
	var week := s.recent_stats(7)
	assert_eq(int(week["runs"]), 1, "stara wyprawa się nie liczy")
	assert_near(float(week["tss"]), 40.0, 0.01)
	assert_eq(int(week["kj"]), 300)
	assert_eq(int(week["minutes"]), 30)
