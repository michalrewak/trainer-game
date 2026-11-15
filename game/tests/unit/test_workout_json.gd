extends TestCase
## Nasz format JSON planów: plik przykładowy, czasy, typy, powtórzenia, waty, walidacja.

const K := WorkoutStep.Kind
const FIXTURES := "res://tests/fixtures/workouts"
const WORK_60 := "{\"type\": \"work\", \"duration\": 60, \"power\": 1.0}"


func _ok(text: String, ftp: float = 250.0) -> WorkoutPlan:
	var r := WorkoutLoader.parse_json(text, ftp)
	assert_eq(r["error"], "", "plan powinien się wczytać:")
	return r["plan"]


## Sprawdza, że tekst daje błąd zawierający fragment; zwraca komunikat.
func _err(text: String, fragment: String) -> String:
	var r := WorkoutLoader.parse_json(text)
	var message: String = r["error"]
	assert_true(r["plan"] == null, "błędny plan nie daje planu (%s)" % fragment)
	assert_true(message.contains(fragment), "błąd „%s” powinien zawierać „%s”" % [message, fragment])
	return message


func _steps_json(steps: String) -> String:
	return "{\"name\": \"t\", \"steps\": [%s]}" % steps


func test_kanion_plan_file() -> void:
	var r := WorkoutLoader.load_file("res://plans/kanion_4x4.json")
	assert_eq(r["error"], "")
	assert_true((r["warnings"] as Array).is_empty(), "przykładowy plan bez ostrzeżeń")
	var p: WorkoutPlan = r["plan"]
	if p == null:
		return
	assert_eq(p.name, "Kanion 4x4")
	assert_eq(p.source_format, "json")
	assert_eq(p.source_path, "res://plans/kanion_4x4.json")
	assert_near(p.reference_ftp, 0.0, 1e-9, "plan względny")
	assert_eq(p.step_count(), 10, "rozgrzewka + 4 x 2 + schłodzenie")
	assert_near(p.total_duration_s(), 2880.0, 1e-6, "48 minut")
	var kinds: Array[int] = []
	for s in p.steps:
		kinds.append(s.kind)
	assert_eq(kinds, [K.WARMUP, K.WORK, K.RECOVERY, K.WORK, K.RECOVERY, K.WORK, K.RECOVERY, K.WORK, K.RECOVERY, K.COOLDOWN] as Array[int])
	var warmup := p.steps[0]
	assert_true(warmup.is_ramp(), "rozgrzewka to rampa")
	assert_near(warmup.duration_s, 600.0, 1e-9)
	assert_near(warmup.power_start, 0.5, 1e-9)
	assert_near(warmup.power_end, 0.75, 1e-9)
	var work := p.steps[7]
	assert_near(work.duration_s, 240.0, 1e-9)
	assert_near(work.power_start, 1.05, 1e-9)
	assert_near(work.cadence_rpm, 95.0, 1e-9)
	assert_eq(work.label, "Interwał 4 min")
	assert_near(p.steps[8].power_start, 0.55, 1e-9)
	assert_near(p.steps[9].power_start, 0.65, 1e-9, "schłodzenie od 65%")
	assert_near(p.steps[9].power_end, 0.45, 1e-9, "do 45%")
	assert_false(p.steps[1] == p.steps[3], "powtórzone kroki to osobne obiekty")
	assert_near(p.target_watts_at(600.0 + 10.0, 250.0), 262.5, 1e-6, "pierwszy interwał 105% z 250 W")


func test_duration_text_formats() -> void:
	var cases := {"90": 90.0, "90.5": 90.5, "4:30": 270.0, "0:45": 45.0, "90:00": 5400.0, "1:05:00": 3900.0, " 2:00 ": 120.0}
	for text: String in cases:
		assert_near(WorkoutJsonParser.parse_duration_text(text), cases[text], 1e-9, "„%s”" % text)
	for bad: String in ["4:75", "abc", "1:2:3:4", "-1:00", "1:60:00", "", ":30", "4:", "4:+5", "1,5"]:
		assert_near(WorkoutJsonParser.parse_duration_text(bad), -1.0, 1e-9, "niepoprawne „%s”" % bad)
	var p := _ok(_steps_json("{\"type\": \"work\", \"duration\": \"2:30\", \"power\": 1.0}, {\"type\": \"recovery\", \"duration\": 45.5, \"power\": 0.5}"))
	if p != null:
		assert_near(p.steps[0].duration_s, 150.0, 1e-9)
		assert_near(p.steps[1].duration_s, 45.5, 1e-9)


func test_types_aliases_and_defaults() -> void:
	var p := _ok(_steps_json(", ".join([
		"{\"type\": \"WORK\", \"duration\": 60, \"power\": 0.5}",
		"{\"type\": \"interval\", \"duration\": 60, \"power\": 1.1}",
		"{\"type\": \"rest\", \"duration\": 60, \"power\": 0.4}",
		"{\"type\": \"steady\", \"duration\": 60, \"from\": 0.6, \"to\": 0.7}",
		"{\"type\": \"ramp\", \"duration\": 60, \"from\": 0.6, \"to\": 0.9}",
		"{\"type\": \"ramp\", \"duration\": 60, \"from\": 0.8, \"to\": 1.2}",
		"{\"type\": \"freeride\", \"duration\": 60, \"cadence\": 90}",
		"{\"type\": \"warmup\", \"duration\": 60}",
		"{\"type\": \"cooldown\", \"duration\": 60}",
		"{\"type\": \"recovery\", \"duration\": 60}",
		"{\"type\": \"warm_up\", \"duration\": 60, \"power\": 0.6}",
	])))
	if p == null:
		return
	var expected: Array[int] = [K.WORK, K.WORK, K.RECOVERY, K.STEADY, K.STEADY, K.WORK, K.FREERIDE, K.WARMUP, K.COOLDOWN, K.RECOVERY, K.WARMUP]
	for i in expected.size():
		assert_eq(p.steps[i].kind, expected[i], "rodzaj kroku %d" % i)
	assert_near(p.steps[0].power_start, 0.5, 1e-9, "praca może być lekka – wybór autora")
	assert_true(p.steps[3].is_ramp(), "steady z from/to to też rampa")
	assert_near(p.steps[6].power_start, 0.0, 1e-9, "jazda swobodna bez celu")
	assert_near(p.steps[6].cadence_rpm, 90.0, 1e-9)
	assert_near(p.steps[7].power_start, WorkoutJsonParser.DEFAULT_WARMUP[0], 1e-9, "domyślna rozgrzewka")
	assert_near(p.steps[7].power_end, WorkoutJsonParser.DEFAULT_WARMUP[1], 1e-9)
	assert_near(p.steps[8].power_start, WorkoutJsonParser.DEFAULT_COOLDOWN[0], 1e-9, "domyślne schłodzenie")
	assert_near(p.steps[8].power_end, WorkoutJsonParser.DEFAULT_COOLDOWN[1], 1e-9)
	assert_near(p.steps[9].power_start, WorkoutJsonParser.DEFAULT_RECOVERY, 1e-9, "domyślna regeneracja")


func test_percent_strings_and_labels() -> void:
	var p := _ok(_steps_json("{\"type\": \"work\", \"duration\": 60, \"power\": \"95%\", \"label\": \"  Burza  \"}, {\"type\": \"steady\", \"duration\": 60, \"from\": \"60 %\", \"to\": 0.7}"))
	if p == null:
		return
	assert_near(p.steps[0].power_start, 0.95, 1e-9, "„95%” = 0.95")
	assert_eq(p.steps[0].label, "Burza", "etykieta bez spacji na brzegach")
	assert_near(p.steps[1].power_start, 0.6, 1e-9)


func test_nested_repeats() -> void:
	var inner := "{\"repeat\": 3, \"steps\": [{\"type\": \"work\", \"duration\": 30, \"power\": 1.2, \"label\": \"a\"}, {\"type\": \"recovery\", \"duration\": 30, \"power\": 0.5, \"label\": \"b\"}]}"
	var outer := "{\"repeat\": 2, \"label\": \"blok\", \"steps\": [{\"type\": \"steady\", \"duration\": 120, \"power\": 0.7, \"label\": \"s\"}, %s]}" % inner
	var p := _ok(_steps_json(outer))
	if p == null:
		return
	assert_eq(p.step_count(), 14, "2 x (1 + 3 x 2)")
	var labels := PackedStringArray()
	for s in p.steps:
		labels.append(s.label)
	assert_eq("".join(labels), "sabababsababab")
	assert_near(p.total_duration_s(), 2 * (120 + 3 * 60), 1e-6)


func test_absolute_watts_fixture() -> void:
	var r := WorkoutLoader.load_file(FIXTURES + "/waty_absolutne.json", 200.0)
	assert_eq(r["error"], "")
	var p: WorkoutPlan = r["plan"]
	if p == null:
		return
	assert_near(p.reference_ftp, 280.0, 1e-9, "FTP z pliku")
	assert_near(p.steps[0].power_start, 0.5, 1e-9, "140 W / 280")
	assert_near(p.steps[0].power_end, 0.75, 1e-9, "210 W / 280")
	assert_near(p.steps[1].power_start, 1.1, 1e-9, "308 W / 280")
	assert_near(p.steps[2].power_start, 0.5, 1e-9, "procent zostaje procentem")
	assert_near(p.steps[3].power_start, WorkoutJsonParser.DEFAULT_COOLDOWN[0], 1e-9, "domyślne cele są względne")
	assert_near(p.target_watts_at(310.0, 280.0), 308.0, 1e-6, "przy FTP z pliku waty dokładnie jak w pliku")


func test_absolute_watts_without_ftp_use_player_ftp() -> void:
	var text := "{\"absolute_watts\": true, \"steps\": [{\"type\": \"work\", \"duration\": 60, \"power\": 300}]}"
	var p := _ok(text, 200.0)
	if p == null:
		return
	assert_near(p.steps[0].power_start, 1.5, 1e-9, "300 W przy FTP gracza 200")
	assert_near(p.target_watts_at(10.0, 200.0), 300.0, 1e-6)
	assert_near(p.reference_ftp, 200.0, 1e-9)
	var fallback := _ok(text, 0.0)
	if fallback != null:
		assert_near(fallback.reference_ftp, WorkoutLoader.DEFAULT_FTP, 1e-9, "bez FTP domyślne 250")
	_err("{\"absolute_watts\": true, \"steps\": [{\"type\": \"work\", \"duration\": 60, \"power\": 3000}]}", "za dużo")


func test_validation_errors() -> void:
	_err("", "pusty")
	_err("   \n ", "pusty")
	_err("{ to nie jest JSON", "Błąd składni JSON")
	_err("[1, 2]", "obiektem")
	_err("{\"name\": \"x\"}", "steps")
	_err("{\"steps\": []}", "pusta")
	_err("{\"steps\": {}}", "listy kroków")
	_err("{\"steps\": [5]}", "obiektem")
	_err(_steps_json("{\"duration\": 60, \"power\": 1}"), "type")
	_err(_steps_json("{\"type\": 3, \"duration\": 60, \"power\": 1}"), "tekstem")
	_err(_steps_json("{\"type\": \"sprint\", \"duration\": 60, \"power\": 1}"), "nieznany typ kroku „sprint”")
	_err(_steps_json("{\"type\": \"work\", \"power\": 1}"), "duration")
	_err(_steps_json("{\"type\": \"work\", \"duration\": -5, \"power\": 1}"), "większy od zera")
	_err(_steps_json("{\"type\": \"work\", \"duration\": 0, \"power\": 1}"), "większy od zera")
	_err(_steps_json("{\"type\": \"work\", \"duration\": \"4:75\", \"power\": 1}"), "nieprawidłowy czas")
	_err(_steps_json("{\"type\": \"work\", \"duration\": [60], \"power\": 1}"), "czas musi być")
	_err(_steps_json("{\"type\": \"work\", \"duration\": 1e400, \"power\": 1}"), "czas musi być")
	_err(_steps_json("{\"type\": \"work\", \"duration\": \"13:00:00\", \"power\": 1}"), "12 h")
	_err(_steps_json("{\"type\": \"work\", \"duration\": 60}"), "brak celu mocy")
	_err(_steps_json("{\"type\": \"work\", \"duration\": 60, \"power\": 95}"), "300% FTP")
	_err(_steps_json("{\"type\": \"work\", \"duration\": 60, \"power\": -0.5}"), "ujemna")
	_err(_steps_json("{\"type\": \"work\", \"duration\": 60, \"power\": \"dużo\"}"), "liczbą")
	_err(_steps_json("{\"type\": \"work\", \"duration\": 60, \"power\": \"x%\"}"), "nieprawidłowa moc")
	_err(_steps_json("{\"type\": \"ramp\", \"duration\": 60, \"power\": 0.8}"), "rampa wymaga")
	_err(_steps_json("{\"type\": \"ramp\", \"duration\": 60}"), "rampa wymaga")
	_err(_steps_json("{\"type\": \"work\", \"duration\": 60, \"from\": 0.5}"), "from\" i \"to")
	_err(_steps_json("{\"type\": \"work\", \"duration\": 60, \"power\": 1, \"from\": 0.5, \"to\": 0.6}"), "nie oba")
	_err(_steps_json("{\"type\": \"work\", \"duration\": 60, \"power\": 1, \"cadence\": 400}"), "kadencja")
	_err(_steps_json("{\"type\": \"work\", \"duration\": 60, \"power\": 1, \"label\": 7}"), "tekstem")
	_err(_steps_json("{\"repeat\": 0, \"steps\": [%s]}" % WORK_60), "od 1 do")
	_err(_steps_json("{\"repeat\": 101, \"steps\": [%s]}" % WORK_60), "od 1 do")
	_err(_steps_json("{\"repeat\": 2.5, \"steps\": [%s]}" % WORK_60), "całkowitą")
	_err(_steps_json("{\"repeat\": \"2\", \"steps\": [%s]}" % WORK_60), "całkowitą")
	_err(_steps_json("{\"repeat\": 3}"), "steps")
	_err(_steps_json("{\"steps\": [%s]}" % WORK_60), "repeat")
	_err(_steps_json("{\"repeat\": 2, \"steps\": []}"), "pusta")
	_err("{\"absolute_watts\": \"tak\", \"steps\": [%s]}" % WORK_60, "absolute_watts")
	_err("{\"ftp\": -1, \"steps\": [%s]}" % WORK_60, "ftp")
	_err("{\"ftp\": \"250\", \"steps\": [%s]}" % WORK_60, "ftp")
	_err("{\"name\": 5, \"steps\": [%s]}" % WORK_60, "tekstem")
	_err("{\"version\": \"x\", \"steps\": [%s]}" % WORK_60, "version")


func test_error_points_to_the_step() -> void:
	var message := _err(_steps_json("%s, {\"repeat\": 2, \"steps\": [%s, {\"type\": \"work\", \"duration\": 60}]}" % [WORK_60, WORK_60]), "brak celu mocy")
	assert_true(message.begins_with("steps[1].steps[1]"), "ścieżka do kroku w błędzie: %s" % message)


func test_limits() -> void:
	var nested := WORK_60
	for i in 9:
		nested = "{\"repeat\": 1, \"steps\": [%s]}" % nested
	_err(_steps_json(nested), "zagnieżdżone")
	var ok_nested := WORK_60
	for i in 8:
		ok_nested = "{\"repeat\": 1, \"steps\": [%s]}" % ok_nested
	assert_true(_ok(_steps_json(ok_nested)) != null, "8 poziomów jest OK")
	var explosion := "{\"repeat\": 100, \"steps\": [{\"repeat\": 100, \"steps\": [{\"type\": \"work\", \"duration\": 1, \"power\": 1}]}]}"
	_err(_steps_json(explosion), "więcej niż 5000")
	_err(_steps_json("{\"repeat\": 100, \"steps\": [{\"type\": \"work\", \"duration\": 600, \"power\": 1}]}"), "12 h")


func test_unknown_keys_are_warnings() -> void:
	var text := "{\"nme\": \"x\", \"_komentarz\": \"ok\", \"comment\": \"ok\", \"steps\": [{\"type\": \"work\", \"duration\": 60, \"power\": 1, \"powr\": 2, \"notes\": \"ok\"}, {\"repeat\": 2, \"count\": 3, \"steps\": [%s]}]}" % WORK_60
	var r := WorkoutLoader.parse_json(text)
	assert_eq(r["error"], "")
	var warnings: Array = r["warnings"]
	assert_eq(warnings.size(), 3, "nme, powr, count: %s" % str(warnings))
	var joined := " | ".join(PackedStringArray(warnings))
	assert_true(joined.contains("„nme”") and joined.contains("„powr”") and joined.contains("„count”"), joined)
	assert_true(joined.contains("steps[0]"), "ostrzeżenie wskazuje krok")


func test_freeride_power_and_newer_version_warn() -> void:
	var r := WorkoutLoader.parse_json("{\"version\": 2, \"steps\": [{\"type\": \"freeride\", \"duration\": 60, \"power\": 0.7}]}")
	assert_eq(r["error"], "")
	assert_eq((r["warnings"] as Array).size(), 2, "nowsza wersja + moc w jeździe swobodnej")
	var p: WorkoutPlan = r["plan"]
	if p != null:
		assert_near(p.steps[0].power_start, 0.0, 1e-9, "jazda swobodna bez celu mimo pola power")


func test_trailing_commas_are_tolerated() -> void:
	# Parser JSON Godota akceptuje przecinki na końcu list – nie wymagamy od autora planu więcej.
	var p := _ok("{\"steps\": [%s,],}" % WORK_60)
	assert_true(p != null and p.step_count() == 1)


func test_broken_fixture_files() -> void:
	var r := WorkoutLoader.load_file(FIXTURES + "/zly.json")
	assert_true(r["plan"] == null)
	assert_true(str(r["error"]).begins_with("zly.json: Błąd składni JSON"), str(r["error"]))
	r = WorkoutLoader.load_file(FIXTURES + "/bez_krokow.json")
	assert_true(r["plan"] == null)
	assert_true(str(r["error"]).contains("pusta"), str(r["error"]))
