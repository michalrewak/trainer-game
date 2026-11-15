extends TestCase


func test_timer_and_finish() -> void:
	var e := Expedition.new(120.0)
	e.tick(60.0, 200.0, 8.0, 480.0)
	assert_near(e.time_left_s(), 60.0, 0.001)
	assert_near(e.progress(), 0.5, 0.001)
	assert_false(e.finished)
	e.tick(100.0, 200.0, 8.0, 1200.0)
	assert_true(e.finished)
	assert_near(e.elapsed_s, 120.0, 0.001, "czas nie przekracza zadanego")


func test_average_power_and_energy() -> void:
	var e := Expedition.new(900.0)
	e.tick(100.0, 100.0, 6.0, 600.0)
	e.tick(100.0, 300.0, 10.0, 1600.0)
	assert_near(e.average_power_w(), 200.0, 0.001)
	assert_near(e.energy_j, 40000.0, 0.001)
	assert_near(e.max_power_w, 300.0, 0.001)


func test_scrap_loss_rule() -> void:
	var e := Expedition.new(900.0)
	assert_eq(e.lose_scrap_on_hit(), 0, "bez złomu nic nie tracimy")
	e.add_scrap(2)
	assert_eq(e.lose_scrap_on_hit(), 2, "nie tracimy więcej niż mamy")
	e.add_scrap(100)
	assert_eq(e.lose_scrap_on_hit(), 15, "15% w górę")
	assert_eq(e.scrap, 85)
	assert_eq(e.scrap_lost, 17)
	assert_eq(e.collisions, 3)


func test_summary_fields() -> void:
	var e := Expedition.new(120.0)
	e.add_scrap(12)
	e.tick(120.0, 180.0, 8.0, 960.0)
	var s := e.to_summary(true)
	for key in ["completed", "duration_s", "distance_m", "scrap", "scrap_lost", "collisions", "avg_power_w", "max_power_w", "avg_speed_kmh"]:
		assert_true(s.has(key), "pole %s" % key)
	assert_eq(s["scrap"], 12)
	assert_eq(s["distance_m"], 960)
	assert_near(float(s["avg_speed_kmh"]), 28.8, 0.05)
