extends TestCase
## Pliki Zwift .zwo: odpowiednik planu Kanion 4x4, warianty zapisu, rozwijanie IntervalsT, błędy XML.

const K := WorkoutStep.Kind
const FIXTURES := "res://tests/fixtures/workouts"


func _zwo(workout_body: String, extra: String = "") -> String:
	return "<workout_file><name>t</name>%s<workout>%s</workout></workout_file>" % [extra, workout_body]


func _ok(text: String) -> WorkoutPlan:
	var r := WorkoutLoader.parse_zwo(text)
	assert_eq(r["error"], "", "plik ZWO powinien się wczytać:")
	return r["plan"]


func _err(text: String, fragment: String) -> String:
	var r := WorkoutLoader.parse_zwo(text)
	var message: String = r["error"]
	assert_true(r["plan"] == null, "błędny ZWO nie daje planu (%s)" % fragment)
	assert_true(message.contains(fragment), "błąd „%s” powinien zawierać „%s”" % [message, fragment])
	return message


func _kinds(p: WorkoutPlan) -> Array[int]:
	var out: Array[int] = []
	for s in p.steps:
		out.append(s.kind)
	return out


func test_kanion_zwo_fixture() -> void:
	var r := WorkoutLoader.load_file(FIXTURES + "/kanion_4x4.zwo")
	assert_eq(r["error"], "")
	assert_true((r["warnings"] as Array).is_empty(), "bez ostrzeżeń: %s" % str(r["warnings"]))
	var p: WorkoutPlan = r["plan"]
	if p == null:
		return
	assert_eq(p.name, "Kanion 4x4")
	assert_true(p.description.begins_with("Klasyczne interwały"), "opis")
	assert_eq(p.source_format, "zwo")
	assert_eq(p.step_count(), 10)
	assert_near(p.total_duration_s(), 2880.0, 1e-6)
	assert_eq(_kinds(p), [K.WARMUP, K.WORK, K.RECOVERY, K.WORK, K.RECOVERY, K.WORK, K.RECOVERY, K.WORK, K.RECOVERY, K.COOLDOWN] as Array[int])
	assert_near(p.steps[0].power_start, 0.5, 1e-9)
	assert_near(p.steps[0].power_end, 0.75, 1e-9)
	assert_near(p.steps[1].power_start, 1.05, 1e-9)
	assert_near(p.steps[1].cadence_rpm, 95.0, 1e-9, "Cadence dla części On")
	assert_near(p.steps[2].power_start, 0.55, 1e-9)
	assert_near(p.steps[2].cadence_rpm, 0.0, 1e-9, "bez CadenceResting")
	assert_near(p.steps[9].power_start, 0.65, 1e-9)
	assert_near(p.steps[9].power_end, 0.45, 1e-9)


func test_variants_fixture() -> void:
	var r := WorkoutLoader.load_file(FIXTURES + "/zwift_warianty.zwo")
	assert_eq(r["error"], "")
	var p: WorkoutPlan = r["plan"]
	if p == null:
		return
	assert_eq(p.name, "Warianty & pułapki", "nazwa z CDATA")
	assert_eq(p.description, "Opis z encjami: <mocno> & równo", "encje XML")
	assert_eq(p.step_count(), 19)
	assert_near(p.total_duration_s(), 1455.0, 1e-6)
	assert_eq(_kinds(p), [
		K.WARMUP, K.WARMUP, K.WORK, K.STEADY, K.RECOVERY, K.WORK, K.STEADY,
		K.WORK, K.RECOVERY, K.WORK, K.RECOVERY, K.WORK, K.WORK, K.WORK,
		K.FREERIDE, K.FREERIDE, K.WORK, K.STEADY, K.COOLDOWN,
	] as Array[int])
	var s := p.steps
	assert_near(s[0].power_start, 0.4, 1e-9, "atrybuty małymi literami")
	assert_near(s[0].power_end, 0.7, 1e-9)
	assert_false(s[1].is_ramp(), "Warmup z samym Power to krok stały")
	assert_near(s[1].power_start, 0.6, 1e-9, "atrybuty WIELKIMI literami")
	assert_near(s[2].duration_s, 120.0, 1e-9, "Duration=\"120.0\"")
	assert_near(s[2].cadence_rpm, 100.0, 1e-9)
	assert_near(s[3].power_start, 0.75, 1e-9, "SteadyState z PowerLow/PowerHigh -> środek")
	assert_near(s[5].power_start, 0.6, 1e-9, "Ramp w górę")
	assert_near(s[5].power_end, 1.2, 1e-9)
	assert_near(s[6].power_start, 0.8, 1e-9, "Ramp w dół zostaje w dół")
	assert_near(s[6].power_end, 0.5, 1e-9)
	assert_near(s[7].power_start, 1.0, 1e-9, "PowerOnLow")
	assert_near(s[7].power_end, 1.2, 1e-9, "PowerOnHigh")
	assert_near(s[7].cadence_rpm, 110.0, 1e-9)
	assert_near(s[8].power_start, 0.5, 1e-9, "PowerOffLow")
	assert_near(s[8].power_end, 0.4, 1e-9, "PowerOffHigh")
	assert_near(s[8].cadence_rpm, 85.0, 1e-9, "CadenceResting")
	assert_near(s[11].power_start, 1.3, 1e-9, "IntervalsT bez części Off")
	assert_near(s[11].duration_s, 20.0, 1e-9)
	assert_near(s[14].cadence_rpm, 90.0, 1e-9, "FreeRide z kadencją")
	assert_near(s[15].duration_s, 60.0, 1e-9, "Freeride (inna pisownia)")
	assert_near(s[16].power_start, WorkoutZwoParser.MAX_EFFORT_FRACTION, 1e-9, "MaxEffort = 150%")
	assert_eq(s[16].label, "Maksymalny wysiłek")
	assert_near(s[17].power_start, 0.6, 1e-9, "SolidState jak SteadyState")
	assert_near(s[18].power_start, 0.6, 1e-9, "Cooldown zawsze w dół")
	assert_near(s[18].power_end, 0.3, 1e-9)
	var warnings: Array = r["warnings"]
	assert_eq(warnings.size(), 2, "zerowy krok i nieznany element: %s" % str(warnings))
	var joined := " | ".join(PackedStringArray(warnings))
	assert_true(joined.contains("zerowy czas"), joined)
	assert_true(joined.contains("<unknown>"), joined)


func test_cooldown_descends_in_both_conventions() -> void:
	var p := _ok(_zwo("<Cooldown Duration=\"300\" PowerLow=\"0.75\" PowerHigh=\"0.25\"/><Cooldown Duration=\"300\" PowerLow=\"0.25\" PowerHigh=\"0.75\"/>"))
	if p == null:
		return
	for s in p.steps:
		assert_near(s.power_start, 0.75, 1e-9)
		assert_near(s.power_end, 0.25, 1e-9)


func test_intervals_are_expanded() -> void:
	var p := _ok(_zwo("<IntervalsT Repeat=\"3\" OnDuration=\"60\" OffDuration=\"30\" OnPower=\"1.2\" OffPower=\"0.5\" Cadence=\"105\" CadenceResting=\"80\"/>"))
	if p == null:
		return
	assert_eq(p.step_count(), 6)
	for i in 6:
		var s := p.steps[i]
		if i % 2 == 0:
			assert_eq(s.kind, K.WORK)
			assert_near(s.duration_s, 60.0, 1e-9)
			assert_near(s.power_start, 1.2, 1e-9)
			assert_near(s.cadence_rpm, 105.0, 1e-9)
		else:
			assert_eq(s.kind, K.RECOVERY)
			assert_near(s.duration_s, 30.0, 1e-9)
			assert_near(s.power_start, 0.5, 1e-9)
			assert_near(s.cadence_rpm, 80.0, 1e-9)
	var no_repeat := _ok(_zwo("<IntervalsT OnDuration=\"60\" OffDuration=\"60\" OnPower=\"1\" OffPower=\"0.5\"/>"))
	assert_true(no_repeat != null and no_repeat.step_count() == 2, "Repeat domyślnie 1")


func test_cadence_range_and_bad_cadence() -> void:
	var r := WorkoutLoader.parse_zwo(_zwo("<SteadyState Duration=\"60\" Power=\"0.7\" CadenceLow=\"85\" CadenceHigh=\"95\"/><SteadyState Duration=\"60\" Power=\"0.7\" Cadence=\"szybko\"/>"))
	assert_eq(r["error"], "")
	var p: WorkoutPlan = r["plan"]
	if p == null:
		return
	assert_near(p.steps[0].cadence_rpm, 90.0, 1e-9, "środek CadenceLow/CadenceHigh")
	assert_near(p.steps[1].cadence_rpm, 0.0, 1e-9, "zła kadencja pominięta")
	assert_eq((r["warnings"] as Array).size(), 1, "ostrzeżenie o złej kadencji")


func test_sport_type_warning() -> void:
	var r := WorkoutLoader.parse_zwo(_zwo("<SteadyState Duration=\"60\" Power=\"0.7\"/>", "<sportType>run</sportType>"))
	assert_eq(r["error"], "")
	assert_eq((r["warnings"] as Array).size(), 1, "trening biegowy -> ostrzeżenie")
	var bike := WorkoutLoader.parse_zwo(_zwo("<SteadyState Duration=\"60\" Power=\"0.7\"/>", "<sportType> Bike </sportType>"))
	assert_true((bike["warnings"] as Array).is_empty(), "bike bez ostrzeżeń")


func test_shipped_zwo_plan() -> void:
	var r := WorkoutLoader.load_file("res://plans/piramida_progowa.zwo")
	assert_eq(r["error"], "")
	assert_true((r["warnings"] as Array).is_empty(), str(r["warnings"]))
	var p: WorkoutPlan = r["plan"]
	if p == null:
		return
	assert_eq(p.name, "Piramida progowa")
	assert_near(p.total_duration_s(), 2340.0, 1e-6, "39 minut")
	assert_eq(p.summary()["hard_intervals"], 5, "2-3-4-3-2")
	assert_eq(p.steps[10].kind, K.FREERIDE)
	assert_near(p.steps[11].power_start, 0.65, 1e-9, "schłodzenie od 65%")


func test_errors() -> void:
	_err("", "pusty")
	_err("to nie jest XML", "workout_file")
	_err("<html><body/></html>", "workout_file")
	_err("<workout_file><name>Tes", "Niekompletny")
	# Atrybuty bez cudzysłowów: XMLParser ich nie widzi, więc brakuje Duration.
	_err(_zwo("<SteadyState Duration=300 Power=0.5/>"), "Duration")
	_err("<workout_file><name>x</name></workout_file>", "Brak sekcji <workout>")
	_err("<workout_file/>", "Brak sekcji <workout>")
	_err(_zwo(""), "żadnych kroków")
	_err(_zwo("<textevent timeoffset=\"1\" message=\"x\"/>"), "żadnych kroków")
	_err(_zwo("<SteadyState Power=\"0.5\"/>"), "Duration")
	_err(_zwo("<SteadyState Duration=\"abc\" Power=\"0.5\"/>"), "nieprawidłowy czas")
	_err(_zwo("<SteadyState Duration=\"-60\" Power=\"0.5\"/>"), "ujemny")
	_err(_zwo("<SteadyState Duration=\"60\" Power=\"95\"/>"), "poza zakresem")
	_err(_zwo("<SteadyState Duration=\"60\" Power=\"dużo\"/>"), "nieprawidłowa moc")
	_err(_zwo("<SteadyState Duration=\"60\"/>"), "Power")
	_err(_zwo("<Warmup Duration=\"60\"/>"), "PowerLow")
	_err(_zwo("<IntervalsT Repeat=\"2.5\" OnDuration=\"60\" OffDuration=\"60\" OnPower=\"1\" OffPower=\"0.5\"/>"), "Repeat")
	_err(_zwo("<IntervalsT Repeat=\"500\" OnDuration=\"60\" OffDuration=\"60\" OnPower=\"1\" OffPower=\"0.5\"/>"), "Repeat")
	_err(_zwo("<IntervalsT Repeat=\"2\" OnDuration=\"60\" OffDuration=\"60\" OnPower=\"1\"/>"), "OffPower")
	_err(_zwo("<IntervalsT Repeat=\"2\" OffDuration=\"60\" OnPower=\"1\" OffPower=\"0.5\"/>"), "OnDuration")
	_err(_zwo("<SteadyState Duration=\"50000\" Power=\"0.5\"/>"), "12 h")
	_err(_zwo("<SteadyState Duration=\"60\" Power=\"0.5\"/>") + "<workout_file/>", "za zamknięciem")
	_err("<workout_file><workout><SteadyState Duration=\"60\" Power=\"0.5\"></workout></workout_file>", "niepasujący znacznik")
	var fixture := WorkoutLoader.load_file(FIXTURES + "/zly.zwo")
	assert_true(fixture["plan"] == null)
	assert_true(str(fixture["error"]).contains("niepasujący znacznik </workout> w linii 8"), str(fixture["error"]))


func test_error_names_the_step_and_line() -> void:
	var text := "<workout_file>\n<workout>\n<SteadyState Duration=\"60\" Power=\"0.5\"/>\n<SteadyState Duration=\"60\" Power=\"7\"/>\n</workout>\n</workout_file>"
	var message := _err(text, "linii 4")
	assert_true(message.begins_with("<steadystate> w linii 4"), message)


func test_random_text_never_crashes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261115
	var base := FileAccess.get_file_as_string(FIXTURES + "/kanion_4x4.zwo")
	for i in 150:
		var text := base
		match i % 3:
			0:
				text = base.substr(0, rng.randi_range(0, base.length()))
			1:
				# Podmieniamy tylko bajty ASCII – tekst zostaje poprawnym UTF-8.
				var chars := text.to_utf8_buffer()
				for k in rng.randi_range(1, 6):
					var pos := rng.randi_range(0, chars.size() - 1)
					if chars[pos] < 0x80:
						chars[pos] = rng.randi_range(0x20, 0x7E)
				text = chars.get_string_from_utf8()
			_:
				var junk := PackedByteArray()
				for k in rng.randi_range(0, 80):
					junk.append(rng.randi_range(0x20, 0x7E))
				text = junk.get_string_from_ascii()
		var r: Variant = WorkoutLoader.parse_zwo(text)
		if not r is Dictionary:
			fail("parse_zwo nie zwrócił słownika (próba %d)" % i)
			return
		var d: Dictionary = r
		if d["plan"] == null and str(d["error"]) == "":
			fail("brak planu i brak błędu (próba %d)" % i)
			return
