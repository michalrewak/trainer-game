extends TestCase


func _generate(seed_value: int, until_m: float, difficulty: float = 0.5) -> Array[TrackItem]:
	var g := TrackGenerator.new(seed_value)
	g.difficulty = difficulty
	var all: Array[TrackItem] = []
	var d := 0.0
	while d < until_m:
		d += 50.0
		all.append_array(g.generate_until(d))
	return all


func _rows(items: Array[TrackItem]) -> Dictionary:
	var rows := {}
	for item in items:
		if item.is_wreck():
			var key := snappedf(item.distance_m, 0.001)
			if not rows.has(key):
				rows[key] = []
			rows[key].append(item.lane)
	return rows


func test_deterministic_for_same_seed() -> void:
	var a := _generate(42, 3000.0)
	var b := _generate(42, 3000.0)
	assert_eq(a.size(), b.size(), "ta sama liczba obiektów")
	for i in mini(a.size(), b.size()):
		if a[i].kind != b[i].kind or a[i].lane != b[i].lane or absf(a[i].distance_m - b[i].distance_m) > 1e-6:
			fail("różnica na pozycji %d" % i)
			return


func test_every_row_leaves_a_free_lane() -> void:
	for seed_value in [1, 2, 3, 99, 2024]:
		for difficulty in [0.0, 0.5, 1.0]:
			var rows := _rows(_generate(seed_value, 8000.0, difficulty))
			assert_true(rows.size() > 20, "są rzędy wraków")
			for key in rows:
				var lanes: Array = rows[key]
				if lanes.size() >= 3:
					fail("rząd na %.1f m blokuje wszystkie pasy (seed %d)" % [key, seed_value])
					return


func test_rows_respect_minimum_gap_and_warmup() -> void:
	var rows := _rows(_generate(7, 8000.0, 1.0))
	var keys := rows.keys()
	keys.sort()
	assert_true(float(keys[0]) >= 150.0, "pierwszy wrak po rozgrzewce")
	for i in range(1, keys.size()):
		var gap := float(keys[i]) - float(keys[i - 1])
		if gap < 29.999:
			fail("za mały odstęp %.2f m przed %.1f m" % [gap, keys[i]])
			return


func test_scrap_never_overlaps_wrecks() -> void:
	var items := _generate(5, 8000.0, 1.0)
	var wrecks := items.filter(func(i: TrackItem) -> bool: return i.is_wreck())
	for s in items:
		if not s.is_scrap():
			continue
		for w in wrecks:
			if w.lane == s.lane and absf(w.distance_m - s.distance_m) < 5.99:
				fail("złom %.1f m w pasie %d za blisko wraku %.1f m" % [s.distance_m, s.lane, w.distance_m])
				return


func test_harder_means_denser_rows() -> void:
	var easy := _rows(_generate(11, 6000.0, 0.0)).size()
	var hard := _rows(_generate(11, 6000.0, 1.0)).size()
	assert_true(hard > easy * 1.4, "więcej rzędów przy wyższej trudności (%d vs %d)" % [hard, easy])


func test_scrap_economy_is_reasonable() -> void:
	var items := _generate(3, 7700.0, 0.5)
	var total := 0
	for i in items:
		if i.is_scrap():
			total += i.value
	assert_between(float(total), 300.0, 900.0, "złom dostępny na ~15 min jazdy przy 200 W")
