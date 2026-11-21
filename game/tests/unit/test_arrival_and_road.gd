extends TestCase
## Koniec wyprawy w osadzie (zamiast „mety”) i różne nawierzchnie drogi.

const DT := 1.0 / 60.0


func test_gate_appears_near_the_end_and_tracks_the_riders_speed() -> void:
	var a := Arrival.new()
	a.step(DT, 120.0, 1000.0, 9.0)
	assert_false(a.is_visible(), "daleko od końca osady nie widać")
	a.step(DT, Arrival.SHOW_S - 0.1, 1000.0, 9.0)
	assert_true(a.is_visible())
	assert_true(a.just_sighted, "pierwsze pojawienie się na horyzoncie")
	assert_near(a.gate_d, 1000.0 + 9.0 * (Arrival.SHOW_S - 0.1), 1.0, "brama tam, dokąd dojedzie gracz")
	a.step(DT, Arrival.SHOW_S - 0.2, 1001.0, 9.0)
	assert_false(a.just_sighted, "sygnał tylko raz")
	# Gracz zwalnia o połowę: osada przesuwa się bliżej.
	var t := 40.0
	var d := 1100.0
	while t > 30.0:
		a.step(DT, t, d, 4.5)
		d += 4.5 * DT
		t -= DT
	assert_near(a.gate_d, d + 4.5 * t, 6.0, "brama dopasowała się do wolniejszej jazdy")
	# Ostatnie sekundy: pozycja zablokowana, nawet gdy gracz nagle przyspieszy.
	a.step(DT, Arrival.LOCK_S - 0.5, d, 4.5)
	var locked := a.gate_d
	a.step(DT, Arrival.LOCK_S - 1.0, d, 20.0)
	assert_near(a.gate_d, locked, 0.001, "tuż przed końcem brama już nie pływa")
	assert_near(a.distance_left_m(locked - 10.0), 10.0, 0.001)


func test_expedition_ends_at_the_settlement_gate() -> void:
	var sim := RunSimulation.new(90.0, 13)
	sim.combat.set_first_encounter(1e9)
	var sighted := 0
	var t := 0.0
	while not sim.expedition.finished and t < 100.0:
		sim.step(DT, 200.0)
		if sim.arrival.just_sighted:
			sighted += 1
		t += DT
	assert_eq(sighted, 1, "osada pojawiła się raz, pod koniec czasu")
	assert_true(sim.arrival.is_visible())
	assert_near(sim.vehicle.distance_m, sim.arrival.gate_d, 12.0, "koniec czasu zastaje gracza przy bramie (%.0f m od niej)" % absf(sim.vehicle.distance_m - sim.arrival.gate_d))
	assert_false(sim.generator.wrecks_enabled, "przed osadą nie pojawiają się nowe wraki")
	for item in sim.items:
		if item.is_wreck() and not item.consumed:
			assert_true(item.distance_m <= sim.arrival.gate_d - Arrival.CLEAR_BEFORE_M + 0.01, "brak wraków w bramie i na placu")


func test_uneven_riding_still_arrives_close_to_the_gate() -> void:
	var sim := RunSimulation.new(120.0, 14)
	sim.combat.set_first_encounter(1e9)
	sim.generator.wrecks_enabled = false
	sim.items.clear()
	var t := 0.0
	while not sim.expedition.finished and t < 130.0:
		# Szarpana jazda: 20 s mocno, 20 s słabo.
		sim.step(DT, 280.0 if int(t / 20.0) % 2 == 0 else 90.0)
		t += DT
	assert_near(sim.vehicle.distance_m, sim.arrival.gate_d, 25.0, "nawet przy szarpaniu osada jest tuż obok")


func test_road_surface_changes_by_section() -> void:
	assert_eq(TrackView.road_surface(0), TrackView.Surface.ASPHALT, "start zawsze na asfalcie")
	assert_eq(TrackView.road_surface(4), TrackView.Surface.ASPHALT)
	var seen := {}
	var changes := 0
	var prev := -1
	for section in range(1, 120):
		var s := TrackView.road_surface(section * 5)
		for k in 5:
			assert_eq(TrackView.road_surface(section * 5 + k), s, "cały odcinek 200 m ma jedną nawierzchnię")
		seen[s] = int(seen.get(s, 0)) + 1
		if s != prev:
			changes += 1
		prev = s
	assert_eq(seen.size(), 4, "asfalt, szuter, beton i stalowe maty")
	for s: int in seen:
		assert_true(int(seen[s]) >= 8, "%s pojawia się regularnie (%d razy)" % [TrackView.surface_name(s), int(seen[s])])
	assert_true(changes > 60, "nawierzchnia zmienia się często (%d zmian na 119 odcinków)" % changes)


func test_every_surface_builds_a_road() -> void:
	var view := TrackView.new()
	view._ready()
	var built := {}
	var idx := 5
	while built.size() < 4 and idx < 2000:
		var s := TrackView.road_surface(idx)
		if not built.has(s):
			var seg := Node3D.new()
			var rng := RandomNumberGenerator.new()
			rng.seed = idx
			view._build_road(seg, idx, rng)
			assert_true(seg.get_child_count() > 8, "%s: jezdnia z detalami (%d elementów)" % [TrackView.surface_name(s), seg.get_child_count()])
			built[s] = true
			seg.free()
		idx += 5
	assert_eq(built.size(), 4)
	view.free()


func test_settlement_view_shows_departure_and_arrival() -> void:
	var sim := RunSimulation.new(60.0, 15)
	var view := SettlementView.new()
	view.sync(sim, 0.1)
	assert_eq(view.get_child_count(), 1, "na starcie stoi brama wyjazdowa osady")
	sim.vehicle.distance_m = 400.0
	view.sync(sim, 0.1)
	sim.arrival.gate_d = 700.0
	view.sync(sim, 0.1)
	var arriving := 0
	for child in view.get_children():
		if not child.is_queued_for_deletion():
			arriving += 1
	assert_eq(arriving, 1, "pod koniec widać bramę osady docelowej")
	view.free()
