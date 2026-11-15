extends TestCase
## Treningi FIT (profil workout/workout_step): fixture'y, cele mocy, strefy, intensywność,
## czasy, inne cele, powtórzenia, kolejność kroków, odrzucanie złych plików.

const K := WorkoutStep.Kind
const P := preload("res://scripts/workout/workout_fit_parser.gd")
const F := preload("res://tests/fixtures/workout_fixtures.gd")
const FIXTURES := "res://tests/fixtures/workouts"


func _parse(bytes: PackedByteArray, ftp: float = 250.0) -> Dictionary:
	return WorkoutLoader.parse_fit(bytes, ftp)


func _ok(bytes: PackedByteArray, ftp: float = 250.0) -> WorkoutPlan:
	var r := _parse(bytes, ftp)
	assert_eq(r["error"], "", "plik FIT powinien się wczytać:")
	return r["plan"]


func _err(bytes: PackedByteArray, fragment: String) -> String:
	var r := _parse(bytes)
	var message: String = r["error"]
	assert_true(r["plan"] == null, "błędny FIT nie daje planu (%s)" % fragment)
	assert_true(message.contains(fragment), "błąd „%s” powinien zawierać „%s”" % [message, fragment])
	return message


func _warnings(r: Dictionary) -> String:
	return " | ".join(PackedStringArray(r["warnings"]))


## Jeden krok w pliku -> krok planu (null, gdy plan się nie wczytał albo ma inną liczbę kroków).
func _single(step: Dictionary, ftp: float = 250.0) -> WorkoutStep:
	var p := _ok(F.workout_file("t", [step]), ftp)
	if p == null:
		return null
	assert_eq(p.step_count(), 1, "jeden krok")
	return p.steps[0] if p.step_count() == 1 else null


func _timed(seconds: float, extra: Dictionary) -> Dictionary:
	var step := {"duration_type": P.DUR_TIME, "duration_value": roundi(seconds * 1000.0)}
	step.merge(extra, true)
	return step


func _kinds(p: WorkoutPlan) -> Array[int]:
	var out: Array[int] = []
	for s in p.steps:
		out.append(s.kind)
	return out


func test_kanion_fit_fixture() -> void:
	var r := WorkoutLoader.load_file(FIXTURES + "/kanion_4x4.fit")
	assert_eq(r["error"], "")
	assert_true((r["warnings"] as Array).is_empty(), "bez ostrzeżeń: %s" % _warnings(r))
	var p: WorkoutPlan = r["plan"]
	if p == null:
		return
	assert_eq(p.name, "Kanion 4x4")
	assert_eq(p.source_format, "fit")
	assert_near(p.reference_ftp, 0.0, 1e-9, "same % FTP – plan względny")
	assert_eq(p.step_count(), 10, "powtórzenie 4x rozwinięte")
	assert_near(p.total_duration_s(), 2880.0, 1e-6)
	assert_eq(_kinds(p), [K.WARMUP, K.WORK, K.RECOVERY, K.WORK, K.RECOVERY, K.WORK, K.RECOVERY, K.WORK, K.RECOVERY, K.COOLDOWN] as Array[int])
	assert_near(p.steps[0].power_start, 0.5, 1e-9, "zakres rozgrzewki -> rampa od dołu")
	assert_near(p.steps[0].power_end, 0.75, 1e-9, "do góry zakresu")
	assert_eq(p.steps[0].label, "Rozgrzewka")
	assert_near(p.steps[1].power_start, 1.05, 1e-9)
	assert_near(p.steps[1].cadence_rpm, 95.0, 1e-9, "drugi cel: kadencja")
	assert_eq(p.steps[1].label, "Interwał 4 min")
	assert_near(p.steps[2].power_start, 0.55, 1e-9)
	assert_near(p.steps[9].power_start, 0.65, 1e-9, "schłodzenie od góry zakresu")
	assert_near(p.steps[9].power_end, 0.45, 1e-9, "do dołu zakresu")


func test_garmin_repeats_and_watts() -> void:
	var r := WorkoutLoader.load_file(FIXTURES + "/garmin_powtorzenia_waty.fit")
	assert_eq(r["error"], "")
	var p: WorkoutPlan = r["plan"]
	if p == null:
		return
	assert_eq(p.name, "Garmin: waty i powtórzenia")
	var block: Array[int] = [K.STEADY, K.WORK, K.RECOVERY, K.WORK, K.RECOVERY, K.WORK, K.RECOVERY, K.WORK, K.FREERIDE, K.WORK, K.FREERIDE]
	var expected: Array[int] = [K.FREERIDE]
	expected.append_array(block)
	expected.append_array(block)
	expected.append(K.COOLDOWN)
	assert_eq(_kinds(p), expected, "zagnieżdżone powtórzenia")
	assert_near(p.total_duration_s(), 2760.0, 1e-6)
	var s := p.steps
	assert_near(s[0].duration_s, P.OPEN_STEP_S, 1e-9, "„do Lap” = 5 min")
	assert_eq(s[0].label, "Rozgrzewka")
	assert_near(s[1].power_start, 0.70, 1e-9, "150–200 W przy FTP 250 -> środek 175 W")
	assert_false(s[1].is_ramp())
	assert_eq(s[1].label, "Tempo")
	assert_near(s[2].power_start, 1.24, 1e-9, "300–320 W -> 310 W")
	assert_near(s[2].cadence_rpm, 95.0, 1e-9, "kadencja 90–100")
	assert_near(s[3].power_start, P.POWER_ZONE_FRACTIONS[1], 1e-9, "strefa mocy 1")
	assert_eq(s[3].label, "Luz", "etykieta z notatki kroku")
	assert_near(s[8].power_start, P.POWER_ZONE_FRACTIONS[6], 1e-9, "strefa mocy 6")
	assert_eq(s[9].label, "Regeneracja – bez celu mocy")
	assert_near(s[9].duration_s, 90.0, 1e-9)
	assert_near(s[23].power_start, P.HR_ZONE_FRACTIONS[2], 1e-9, "tętno strefa 2 -> szacunek mocy")
	assert_eq(s[23].label, "Schłodzenie (cel: tętno strefa 2)")
	assert_eq((r["warnings"] as Array).size(), 1, "tylko krok „do Lap”: %s" % _warnings(r))
	assert_true(_warnings(r).contains("Lap"))
	var watts := p.target_watts_at(p.step_start_s(2) + 5.0, 250.0)
	assert_near(watts, 310.0, 1e-6, "waty z pliku zostają przy FTP gracza")


func test_watts_follow_ftp_argument() -> void:
	var bytes := FileAccess.get_file_as_bytes(FIXTURES + "/garmin_powtorzenia_waty.fit")
	for ftp: float in [200.0, 300.0]:
		var p := _ok(bytes, ftp)
		if p == null:
			continue
		assert_near(p.reference_ftp, ftp, 1e-9)
		assert_near(p.steps[1].power_start, 175.0 / ftp, 1e-9, "175 W / FTP %d" % ftp)
		assert_near(p.target_watts_at(p.step_start_s(1) + 1.0, ftp), 175.0, 1e-6, "przy FTP %d" % ftp)
		assert_near(p.steps[3].power_start, P.POWER_ZONE_FRACTIONS[1], 1e-9, "strefy nie zależą od FTP")
	var fallback := _ok(bytes, 0.0)
	if fallback != null:
		assert_near(fallback.reference_ftp, WorkoutLoader.DEFAULT_FTP, 1e-9, "FTP <= 0 -> 250")


func test_power_zones() -> void:
	for zone in range(1, 8):
		var s := _single(_timed(60, {"target_type": P.TGT_POWER, "target_value": zone, "intensity": P.INT_ACTIVE}))
		if s != null:
			assert_near(s.power_start, P.POWER_ZONE_FRACTIONS[zone], 1e-9, "strefa %d" % zone)
			assert_eq(s.kind, WorkoutStep.kind_for_power(P.POWER_ZONE_FRACTIONS[zone]), "rodzaj dla strefy %d" % zone)
	for t: int in [P.TGT_POWER_3S, P.TGT_POWER_10S, P.TGT_POWER_30S, P.TGT_POWER_LAP]:
		var s := _single(_timed(60, {"target_type": t, "target_value": 4}))
		if s != null:
			assert_near(s.power_start, P.POWER_ZONE_FRACTIONS[4], 1e-9, "wariant celu mocy %d" % t)
	var r := _parse(F.workout_file("t", [_timed(60, {"target_type": P.TGT_POWER, "target_value": 9})]))
	assert_eq(r["error"], "")
	var p: WorkoutPlan = r["plan"]
	if p != null:
		assert_eq(p.steps[0].kind, K.FREERIDE, "nieznana strefa bez zakresu -> jazda swobodna")
	assert_true(_warnings(r).contains("strefa mocy 9"), _warnings(r))


func test_custom_power_ranges() -> void:
	var cases := [
		[P.INT_ACTIVE, 70, 80, K.STEADY, 0.75, 0.75],
		[P.INT_ACTIVE, 95, 105, K.WORK, 1.0, 1.0],
		[P.INT_WARMUP, 40, 70, K.WARMUP, 0.4, 0.7],
		[P.INT_COOLDOWN, 40, 70, K.COOLDOWN, 0.7, 0.4],
		[P.INT_ACTIVE, 90, 70, K.STEADY, 0.8, 0.8],
		[P.INT_ACTIVE, 1200, 1300, K.WORK, 1.0, 1.0],
		[P.INT_ACTIVE, 90, 1250, K.WORK, 0.95, 0.95],
		[P.INT_ACTIVE, 80, null, K.STEADY, 0.8, 0.8],
		[P.INT_ACTIVE, null, 60, K.STEADY, 0.6, 0.6],
		[P.INT_ACTIVE, 1001, 1001, K.STEADY, 1.0 / 250.0, 1.0 / 250.0],
	]
	for c: Array in cases:
		var s := _single(_timed(120, {"target_type": P.TGT_POWER, "target_value": 0, "low": c[1], "high": c[2], "intensity": c[0]}))
		if s == null:
			continue
		var label := "zakres %s–%s (intensity %d)" % [str(c[1]), str(c[2]), c[0]]
		assert_eq(s.kind, c[3], label)
		assert_near(s.power_start, c[4], 1e-9, label + " start")
		assert_near(s.power_end, c[5], 1e-9, label + " koniec")
	var r := _parse(F.workout_file("t", [_timed(60, {"target_type": P.TGT_POWER, "target_value": 0, "low": 500, "high": 1000})]))
	var p: WorkoutPlan = r["plan"]
	if p != null:
		assert_near(p.steps[0].power_start, P.MAX_FRACTION, 1e-9, "ponad 300% FTP przycięte")
	assert_true(_warnings(r).contains("300%"), _warnings(r))
	r = _parse(F.workout_file("t", [_timed(60, {"target_type": P.TGT_POWER, "target_value": 0, "low": 0, "high": 0})]))
	p = r["plan"]
	if p != null:
		assert_eq(p.steps[0].kind, K.FREERIDE, "zakres 0–0 = brak celu")
	assert_true(_warnings(r).contains("bez wartości"), _warnings(r))


func test_intensity_mapping() -> void:
	var cases := [
		[P.INT_ACTIVE, 60, K.STEADY], [P.INT_ACTIVE, 95, K.WORK], [P.INT_REST, 60, K.RECOVERY],
		[P.INT_RECOVERY, 60, K.RECOVERY], [P.INT_WARMUP, 60, K.WARMUP], [P.INT_COOLDOWN, 60, K.COOLDOWN],
		[P.INT_INTERVAL, 60, K.WORK], [P.INT_OTHER, 60, K.STEADY], [null, 60, K.STEADY], [null, 100, K.WORK], [9, 60, K.STEADY],
	]
	for c: Array in cases:
		var s := _single(_timed(60, {"target_type": P.TGT_POWER, "target_value": 0, "low": c[1], "high": c[1], "intensity": c[0]}))
		if s != null:
			assert_eq(s.kind, c[2], "intensity %s przy %d%%" % [str(c[0]), c[1]])
			assert_near(s.power_start, c[1] / 100.0, 1e-9)


func test_durations() -> void:
	var power := {"target_type": P.TGT_POWER, "target_value": 0, "low": 80, "high": 80}
	var s := _single(_timed(90, power))
	assert_true(s != null and is_equal_approx(s.duration_s, 90.0), "TIME w ms")
	var rep := power.duplicate()
	rep.merge({"duration_type": P.DUR_REPETITION_TIME, "duration_value": 30000}, true)
	s = _single(rep)
	assert_true(s != null and is_equal_approx(s.duration_s, 30.0), "REPETITION_TIME jak czas")
	var cases := [
		[P.DUR_OPEN, null, 300.0, "Lap"],
		[P.DUR_DISTANCE, 500000, 600.0, "dystans 5.0 km"],
		[P.DUR_CALORIES, 100, 500.0, "100 kcal"],
		[P.DUR_HR_LESS_THAN, 140, 300.0, "tętno poniżej"],
		[P.DUR_POWER_GREATER_THAN, 1300, 300.0, "moc powyżej"],
		[40, 1, 300.0, "typ 40"],
	]
	for c: Array in cases:
		var step := power.duplicate()
		step.merge({"duration_type": c[0], "duration_value": c[1]}, true)
		var r := _parse(F.workout_file("t", [step]))
		var p: WorkoutPlan = r["plan"]
		if p == null:
			fail("czas typu %d: %s" % [c[0], r["error"]])
			continue
		assert_near(p.steps[0].duration_s, c[2], 1e-6, "czas typu %d" % c[0])
		assert_near(p.steps[0].power_start, 0.8, 1e-9, "cel zostaje przy czasie typu %d" % c[0])
		assert_true(_warnings(r).contains(c[3]), "ostrzeżenie „%s”: %s" % [c[3], _warnings(r)])
	var no_target := _single({"duration_type": P.DUR_CALORIES, "duration_value": 100, "target_type": P.TGT_OPEN})
	assert_true(no_target != null and is_equal_approx(no_target.duration_s, 1000.0), "kalorie bez celu mocy liczone przy 100 W")
	var missing_type := _single({"duration_value": 60000, "target_type": P.TGT_OPEN})
	assert_true(missing_type != null and is_equal_approx(missing_type.duration_s, P.OPEN_STEP_S), "brak typu czasu -> jak „do Lap”")
	var r := _parse(F.workout_file("t", [_timed(0, power), power.merged({"duration_type": P.DUR_TIME}), _timed(60, power)]))
	var p: WorkoutPlan = r["plan"]
	assert_true(p != null and p.step_count() == 1, "kroki bez czasu pominięte")
	assert_eq((r["warnings"] as Array).size(), 2, _warnings(r))
	_err(F.workout_file("t", [_timed(0, power)]), "żadnego kroku")
	_err(F.workout_file("t", [_timed(13 * 3600, power)]), "12 h")


func test_other_targets() -> void:
	var cases := [
		[{"target_type": P.TGT_HEART_RATE, "target_value": 3}, P.INT_ACTIVE, 0.80, "Cel: tętno strefa 3", 0.0],
		[{"target_type": P.TGT_HEART_RATE, "target_value": 0, "low": 240, "high": 250}, P.INT_ACTIVE, 0.70, "Cel: tętno 140–150 ud./min", 0.0],
		[{"target_type": P.TGT_HEART_RATE, "target_value": 0, "low": 70, "high": 80}, P.INT_ACTIVE, 0.70, "Cel: tętno 70–80% HRmax", 0.0],
		[{"target_type": P.TGT_HEART_RATE_LAP, "target_value": 5}, P.INT_INTERVAL, 1.05, "Cel: tętno strefa 5", 0.0],
		[{"target_type": P.TGT_SPEED, "target_value": 0, "low": 8333, "high": 9722}, P.INT_ACTIVE, 0.70, "Cel: prędkość 30.0–35.0 km/h", 0.0],
		[{"target_type": P.TGT_SPEED, "target_value": 2}, P.INT_ACTIVE, 0.70, "Cel: prędkość strefa 2", 0.0],
		[{"target_type": P.TGT_CADENCE, "target_value": 0, "low": 85, "high": 95}, P.INT_INTERVAL, 0.90, "Cel: kadencja 85–95 obr./min", 90.0],
		[{"target_type": P.TGT_CADENCE, "target_value": 0, "low": 100}, P.INT_REST, 0.50, "Cel: kadencja 100 obr./min", 100.0],
		[{"target_type": P.TGT_GRADE}, P.INT_WARMUP, 0.55, "Cel: nachylenie", 0.0],
		[{"target_type": P.TGT_RESISTANCE}, P.INT_COOLDOWN, 0.50, "Cel: opór", 0.0],
		[{"target_type": 77}, P.INT_ACTIVE, 0.70, "Cel: typ 77", 0.0],
	]
	for c: Array in cases:
		var step := _timed(60, c[0])
		step["intensity"] = c[1]
		var s := _single(step)
		if s == null:
			continue
		assert_near(s.power_start, c[2], 1e-9, "szacunek mocy dla %s" % c[3])
		assert_eq(s.label, c[3])
		assert_near(s.cadence_rpm, c[4], 1e-9, "kadencja dla %s" % c[3])
		assert_true(s.has_target(), "inny cel to wciąż cel mocy (szacowany)")
	var named := _single(_timed(60, {"name": "Tempo", "target_type": P.TGT_HEART_RATE, "target_value": 2}))
	assert_true(named != null and named.label == "Tempo (cel: tętno strefa 2)", "nazwa + cel")


func test_secondary_targets() -> void:
	var hr_power := _single(_timed(60, {"target_type": P.TGT_HEART_RATE, "target_value": 2, "secondary_type": P.TGT_POWER, "secondary_low": 1250, "secondary_high": 1250}))
	if hr_power != null:
		assert_near(hr_power.power_start, 1.0, 1e-9, "moc z drugiego celu, gdy główny to tętno")
		assert_eq(hr_power.kind, K.WORK)
	var cadence := _single(_timed(60, {"target_type": P.TGT_POWER, "target_value": 0, "low": 90, "high": 90, "secondary_type": P.TGT_CADENCE, "secondary_low": 100, "secondary_high": 110}))
	if cadence != null:
		assert_near(cadence.cadence_rpm, 105.0, 1e-9, "kadencja z drugiego celu")
		assert_near(cadence.power_start, 0.9, 1e-9)
	var open_cadence := _single(_timed(60, {"target_type": P.TGT_OPEN, "secondary_type": P.TGT_CADENCE, "secondary_low": 90, "secondary_high": 90}))
	if open_cadence != null:
		assert_eq(open_cadence.kind, K.FREERIDE)
		assert_near(open_cadence.cadence_rpm, 90.0, 1e-9, "jazda swobodna z kadencją")


func test_repeat_edge_cases() -> void:
	var a := _timed(60, {"name": "A", "target_type": P.TGT_POWER, "target_value": 0, "low": 100, "high": 100})
	var b := _timed(120, {"name": "B", "target_type": P.TGT_POWER, "target_value": 0, "low": 50, "high": 50})
	var r := _parse(F.workout_file("t", [a, F.repeat_step(5, 2)]))
	assert_true(r["plan"] != null and (r["plan"] as WorkoutPlan).step_count() == 1, "powtórzenie do przodu pominięte")
	assert_true(_warnings(r).contains("nieistniejącego"), _warnings(r))
	r = _parse(F.workout_file("t", [a, F.repeat_step(1, 2)]))
	assert_true(_warnings(r).contains("nieistniejącego"), "powtórzenie samego siebie: %s" % _warnings(r))
	r = _parse(F.workout_file("t", [a, b, {"duration_type": P.DUR_REPEAT_UNTIL_STEPS_CMPLT, "duration_value": 0}]))
	assert_true(r["plan"] != null and (r["plan"] as WorkoutPlan).step_count() == 2, "bez liczby powtórzeń blok raz")
	assert_true(_warnings(r).contains("brak liczby powtórzeń"), _warnings(r))
	_err(F.workout_file("t", [a, F.repeat_step(0, 1000)]), "za dużo")
	r = _parse(F.workout_file("t", [a, b, {"duration_type": P.DUR_REPEAT_UNTIL_TIME, "duration_value": 0, "target_value": 600000}]))
	var p: WorkoutPlan = r["plan"]
	assert_true(p != null and p.step_count() == 8, "do czasu 10 min: 4 x blok 3 min")
	assert_true(_warnings(r).contains("powtarzaj do czasu 10:00"), _warnings(r))
	r = _parse(F.workout_file("t", [a, b, {"duration_type": P.DUR_REPEAT_UNTIL_HR_LESS_THAN, "duration_value": 0, "target_value": 120}]))
	assert_true(r["plan"] != null and (r["plan"] as WorkoutPlan).step_count() == 2, "warunek tętna: blok raz")
	assert_true(_warnings(r).contains("tętno poniżej"), _warnings(r))
	var tiny := _timed(1, {"target_type": P.TGT_OPEN})
	_err(F.workout_file("t", [tiny, F.repeat_step(0, 100), F.repeat_step(0, 100)]), "więcej niż 5000")
	r = _parse(F.workout_file("t", [a, b, F.repeat_step(0, 3)]))
	p = r["plan"]
	if p != null:
		var labels := PackedStringArray()
		for s in p.steps:
			labels.append(s.label)
		assert_eq("".join(labels), "ABABAB", "powtórzenie od pierwszego kroku")
		assert_false(p.steps[0] == p.steps[2], "kopie kroków")


func test_step_order() -> void:
	var steps := [
		_timed(60, {"name": "C", "message_index": 2, "target_type": P.TGT_OPEN}),
		_timed(60, {"name": "A", "message_index": 0, "target_type": P.TGT_OPEN}),
		_timed(60, {"name": "B", "message_index": 1, "target_type": P.TGT_OPEN}),
	]
	var p := _ok(F.workout_file("t", steps))
	if p != null:
		assert_eq(p.steps[0].label + p.steps[1].label + p.steps[2].label, "ABC", "kolejność wg message_index")
	for broken: Array in [[null, null, null], [0, 0, 1]]:
		var copy := []
		for i in 3:
			var s: Dictionary = (steps[i] as Dictionary).duplicate()
			s["message_index"] = broken[i]
			copy.append(s)
		var r := _parse(F.workout_file("t", copy))
		var q: WorkoutPlan = r["plan"]
		if q != null:
			assert_eq(q.steps[0].label + q.steps[1].label + q.steps[2].label, "CAB", "kolejność z pliku przy %s" % str(broken))
		assert_true(_warnings(r).contains("message_index"), _warnings(r))
	var selected := _ok(F.workout_file("t", [_timed(60, {"name": "X", "message_index": 0x8000, "target_type": P.TGT_OPEN}), _timed(60, {"name": "Y", "message_index": 0x8001, "target_type": P.TGT_OPEN}), F.repeat_step(0, 2)]))
	assert_true(selected != null and selected.step_count() == 4, "flaga „selected” w message_index ignorowana")


func test_not_a_workout() -> void:
	var r := WorkoutLoader.load_file(FIXTURES + "/aktywnosc.fit")
	assert_true(r["plan"] == null)
	var message: String = r["error"]
	assert_true(message.begins_with("aktywnosc.fit: "), message)
	assert_true(message.contains("zapis aktywności") and message.contains("workout"), message)
	_err(F.workout_file("t", [], {"file_type": 6}), "trasa")
	_err(F.workout_file("t", [], {"file_type": 99}), "typu 99")


func test_damaged_files() -> void:
	var r := WorkoutLoader.load_file(FIXTURES + "/zla_suma_kontrolna.fit")
	assert_eq(r["error"], "", "złe CRC pliku: wczytujemy z ostrzeżeniem")
	assert_true(r["plan"] != null and (r["plan"] as WorkoutPlan).step_count() == 10)
	assert_true(_warnings(r).contains("Suma kontrolna pliku FIT się nie zgadza"), _warnings(r))
	r = WorkoutLoader.load_file(FIXTURES + "/uciety.fit")
	assert_true(r["plan"] == null, "ucięty plik odrzucony")
	assert_true(str(r["error"]).contains("ucięty"), str(r["error"]))
	_err(F.workout_file("t", []), "nie zawiera kroków")
	_err(PackedByteArray(), "za krótki")
	_err("to nie jest FIT, tylko tekst w pliku .fit".to_utf8_buffer(), "sygnatury")


func test_header_and_metadata_warnings() -> void:
	var r := _parse(F.workout_file("t", [_timed(60, {"target_type": P.TGT_OPEN})], {"sport": 1, "num_valid_steps": 7}))
	assert_eq(r["error"], "")
	assert_true(_warnings(r).contains("innego sportu"), _warnings(r))
	assert_true(_warnings(r).contains("deklaruje 7"), _warnings(r))
	var w := FitWriter.new()
	w.define(0, P.MESG_WORKOUT_STEP, [[P.STEP_DURATION_TYPE, 1, FitDecoder.BASE_ENUM], [P.STEP_DURATION_VALUE, 4, FitDecoder.BASE_UINT32]])
	w.write(0, [P.DUR_TIME, 60000])
	r = _parse(w.to_bytes())
	assert_eq(r["error"], "", "bez file_id i workout też się da")
	assert_true(_warnings(r).contains("Brak wiadomości file_id"), _warnings(r))
	var plan: WorkoutPlan = r["plan"]
	assert_true(plan != null and plan.name == "", "bez wiadomości workout nazwa pusta (load_file weźmie nazwę pliku)")
	var two := FitWriter.new()
	two.define(0, P.MESG_FILE_ID, [[P.FILE_ID_TYPE, 1, FitDecoder.BASE_ENUM]])
	two.write(0, [null])
	two.define(1, P.MESG_WORKOUT, [[P.WKT_NAME, 4, FitDecoder.BASE_STRING]])
	two.write(1, ["Raz"])
	two.write(1, ["Dwa"])
	two.define(2, P.MESG_WORKOUT_STEP, [[P.STEP_DURATION_TYPE, 1, FitDecoder.BASE_ENUM], [P.STEP_DURATION_VALUE, 4, FitDecoder.BASE_UINT32]])
	two.write(2, [P.DUR_TIME, 60000])
	r = _parse(two.to_bytes())
	plan = r["plan"]
	assert_true(plan != null and plan.name == "Raz", "pierwszy trening z pliku")
	assert_true(_warnings(r).contains("2 treningi"), _warnings(r))
	assert_true(_warnings(r).contains("bez typu pliku"), _warnings(r))


func test_encoding_variants_give_the_same_plan() -> void:
	var reference := _ok(F.kanion_4x4())
	if reference == null:
		return
	for opts: Dictionary in [{"big_endian_steps": true}, {"header_size": 12}, {"header_crc": "zero"}]:
		var p := _ok(F.kanion_4x4(opts))
		if p != null:
			assert_eq(p.describe(), reference.describe(), "ten sam plan przy %s" % str(opts))


func test_fixture_files_are_up_to_date() -> void:
	var files := F.fit_files()
	for file_name: String in files:
		var on_disk := FileAccess.get_file_as_bytes(FIXTURES.path_join(file_name))
		assert_true(on_disk == files[file_name], "%s różni się od WorkoutFixtures – uruchom make_workout_fixtures.gd" % file_name)
