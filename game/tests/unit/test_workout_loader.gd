extends TestCase
## WorkoutLoader: wybór formatu po rozszerzeniu, błędy plików, przykładowe plany gry
## i równoważność tego samego planu w JSON / ZWO / FIT.

const FIXTURES := "res://tests/fixtures/workouts"
const PLANS := "res://plans"
## Osobny katalog na proces – równoległe uruchomienia testów nie kolidują.
var DIR := "user://test_workouts/%d" % OS.get_process_id()


func _write(file_name: String, bytes: PackedByteArray) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return path


func _signature(p: WorkoutPlan) -> Array:
	var out: Array = []
	for s in p.steps:
		out.append([s.kind, snappedf(s.duration_s, 0.001), snappedf(s.power_start, 1e-6), snappedf(s.power_end, 1e-6), snappedf(s.cadence_rpm, 0.001)])
	return out


func test_dispatch_by_extension() -> void:
	for file_name: String in ["waty_absolutne.json", "kanion_4x4.zwo", "kanion_4x4.fit"]:
		var r := WorkoutLoader.load_file(FIXTURES.path_join(file_name))
		assert_eq(r["error"], "", file_name)
		var p: WorkoutPlan = r["plan"]
		assert_true(p != null and p.source_format == file_name.get_extension(), "format %s" % file_name)
	var upper := _write("KANION.ZWO", FileAccess.get_file_as_bytes(FIXTURES + "/kanion_4x4.zwo"))
	var r := WorkoutLoader.load_file(upper)
	assert_eq(r["error"], "", "rozszerzenie wielkimi literami")
	assert_true(WorkoutLoader.is_supported_file("a/b/Plan.FIT"))
	assert_false(WorkoutLoader.is_supported_file("plan.erg"))


func test_file_errors() -> void:
	var r := WorkoutLoader.load_file("res://plans/plan.erg")
	assert_true(r["plan"] == null)
	assert_true(str(r["error"]).contains("Nieobsługiwany format"), str(r["error"]))
	r = WorkoutLoader.load_file("res://plans/nie_ma_takiego.json")
	assert_true(str(r["error"]).contains("Nie znaleziono"), str(r["error"]))
	r = WorkoutLoader.load_file(_write("pusty.zwo", PackedByteArray()))
	assert_true(r["plan"] == null)
	assert_true(str(r["error"]).contains("pusty"), str(r["error"]))
	var big := PackedByteArray()
	big.resize(WorkoutLoader.MAX_FILE_BYTES + 10)
	r = WorkoutLoader.load_file(_write("wielki.json", big))
	assert_true(str(r["error"]).contains("za duży"), str(r["error"]))
	r = WorkoutLoader.load_file(_write("binarny.json", PackedByteArray([0xFF, 0xFE, 0x00, 0xC3, 0x28, 0x7B])))
	assert_true(r["plan"] == null and str(r["error"]).begins_with("binarny.json: "), str(r["error"]))


func test_name_falls_back_to_file_name_and_bom_is_skipped() -> void:
	var text := char(0xFEFF) + "{\"steps\": [{\"type\": \"work\", \"duration\": 60, \"power\": 1.0}]}"
	var r := WorkoutLoader.load_file(_write("moj_plan.json", text.to_utf8_buffer()))
	assert_eq(r["error"], "", "BOM na początku pliku")
	var p: WorkoutPlan = r["plan"]
	assert_true(p != null and p.name == "moj_plan", "nazwa z pliku")
	assert_true(p != null and p.source_path.ends_with("moj_plan.json"))


func test_shipped_plans_are_valid() -> void:
	var files := WorkoutLoader.list_plan_files(PLANS)
	var names := PackedStringArray()
	for f in files:
		names.append(f.get_file())
	assert_eq(names, PackedStringArray(["kanion_4x4.json", "piramida_progowa.zwo", "pustynny_szlak.json", "szybki_test_20min.json"]), "plany dołączone do gry")
	for path in files:
		var r := WorkoutLoader.load_file(path)
		assert_eq(r["error"], "", path)
		assert_true((r["warnings"] as Array).is_empty(), "%s bez ostrzeżeń: %s" % [path, str(r["warnings"])])
		var p: WorkoutPlan = r["plan"]
		if p == null:
			continue
		assert_true(p.name != "" and p.description != "", "%s: nazwa i opis" % path)
		var s := p.summary()
		assert_between(s["duration_s"], 15.0 * 60.0, 60.0 * 60.0, "%s: czas" % path)
		assert_true(int(s["hard_intervals"]) >= 4, "%s: są ciężkie odcinki" % path)
		assert_between(s["intensity_factor"], 0.6, 1.0, "%s: IF" % path)
		assert_true(p.steps[0].kind == WorkoutStep.Kind.WARMUP, "%s: zaczyna się rozgrzewką" % path)
		assert_true(p.steps[p.step_count() - 1].kind == WorkoutStep.Kind.COOLDOWN, "%s: kończy się schłodzeniem" % path)


func test_shipped_plan_details() -> void:
	var szlak: WorkoutPlan = WorkoutLoader.load_file(PLANS + "/pustynny_szlak.json")["plan"]
	if szlak != null:
		assert_near(szlak.total_duration_s(), 1800.0, 1e-6, "30 minut")
		assert_eq(szlak.summary()["hard_intervals"], 5, "pięć zrywów")
		assert_near(szlak.summary()["time_above_threshold_s"], 150.0, 1e-6, "5 x 30 s")
	var demo: WorkoutPlan = WorkoutLoader.load_file(PLANS + "/szybki_test_20min.json")["plan"]
	if demo != null:
		assert_near(demo.total_duration_s(), 1200.0, 1e-6, "20 minut")
		var kinds := {}
		for s in demo.steps:
			kinds[s.kind] = true
		assert_eq(kinds.size(), 6, "plan demo ma wszystkie rodzaje kroków")
		assert_eq(demo.summary()["hard_intervals"], 6)


func test_kanion_is_the_same_in_all_formats() -> void:
	var json: WorkoutPlan = WorkoutLoader.load_file(PLANS + "/kanion_4x4.json")["plan"]
	var zwo: WorkoutPlan = WorkoutLoader.load_file(FIXTURES + "/kanion_4x4.zwo")["plan"]
	var fit: WorkoutPlan = WorkoutLoader.load_file(FIXTURES + "/kanion_4x4.fit")["plan"]
	if json == null or zwo == null or fit == null:
		fail("któryś format się nie wczytał")
		return
	assert_eq(_signature(zwo), _signature(json), "ZWO = JSON")
	assert_eq(_signature(fit), _signature(json), "FIT = JSON")
	for i in json.step_count():
		assert_eq(fit.steps[i].label, json.steps[i].label, "etykiety FIT i JSON, krok %d" % i)
	assert_eq(zwo.name, json.name)
	assert_eq(fit.name, json.name)
	var a := json.summary()
	var b := fit.summary()
	for key: String in a:
		assert_near(float(b[key]), float(a[key]), 1e-6, "summary[%s]" % key)


func test_kanion_summary() -> void:
	var p: WorkoutPlan = WorkoutLoader.load_file(PLANS + "/kanion_4x4.json")["plan"]
	if p == null:
		return
	var s := p.summary()
	assert_near(s["duration_s"], 2880.0, 1e-6)
	assert_eq(s["step_count"], 10)
	assert_eq(s["hard_intervals"], 4)
	assert_near(s["hard_time_s"], 960.0, 1e-6)
	assert_near(s["time_above_threshold_s"], 960.0, 1e-6)
	assert_near(s["max_intensity"], 1.05, 1e-9)
	assert_near(s["freeride_s"], 0.0, 1e-9)
	assert_near(s["avg_intensity"], (0.625 * 600 + 4 * (1.05 * 240 + 0.55 * 180) + 0.55 * 600) / 2880.0, 1e-9)
	assert_between(s["intensity_factor"], 0.78, 0.85, "IF planu 4x4")
	assert_between(s["tss"], 48.0, 58.0, "TSS planu 4x4")


func test_parser_instances_can_be_reused() -> void:
	var json := WorkoutJsonParser.new()
	assert_true(json.parse("{ zły")["plan"] == null)
	var ok := json.parse("{\"steps\": [{\"type\": \"work\", \"duration\": 60, \"power\": 1}]}")
	assert_eq(ok["error"], "", "błąd z poprzedniego wywołania nie przechodzi dalej")
	var zwo := WorkoutZwoParser.new()
	var first: WorkoutPlan = zwo.parse("<workout_file><workout><SteadyState Duration=\"60\" Power=\"0.5\"/></workout></workout_file>")["plan"]
	var second: WorkoutPlan = zwo.parse("<workout_file><workout><SteadyState Duration=\"30\" Power=\"0.6\"/></workout></workout_file>")["plan"]
	assert_true(first != null and second != null and first != second, "nowy plan przy każdym wywołaniu")
	assert_true(first != null and first.step_count() == 1 and second != null and second.step_count() == 1)
	var fit := WorkoutFitParser.new()
	fit.parse(PackedByteArray())
	var again := fit.parse(WorkoutFixtures.kanion_4x4())
	assert_eq(again["error"], "")
	assert_true((again["warnings"] as Array).is_empty(), "ostrzeżenia z poprzedniego wywołania nie przechodzą dalej")


func test_list_plan_files() -> void:
	var files := WorkoutLoader.list_plan_files(FIXTURES)
	var names := PackedStringArray()
	for f in files:
		names.append(f.get_file())
	assert_true(names.has("kanion_4x4.fit") and names.has("kanion_4x4.zwo") and names.has("zly.json"), str(names))
	assert_false(names.has(".gitattributes"), "tylko obsługiwane rozszerzenia")
	var sorted := names.duplicate()
	sorted.sort()
	assert_eq(names, sorted, "posortowane")
	assert_true(WorkoutLoader.list_plan_files("res://nie_ma_katalogu").is_empty())
