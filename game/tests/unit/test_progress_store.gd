extends TestCase

const DIR := "user://test_saves"


func _fresh_path(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var p := "%s/%s.json" % [DIR, name]
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(p + suffix):
			DirAccess.remove_absolute(p + suffix)
	return p


func _summary(scrap: int, completed: bool = true) -> Dictionary:
	var e := Expedition.new(120.0)
	e.add_scrap(scrap)
	e.tick(120.0, 200.0, 8.6, 1030.0)
	return e.to_summary(completed)


func test_roundtrip_keeps_totals_and_types() -> void:
	var p := _fresh_path("roundtrip")
	var a := ProgressStore.new(p)
	a.record_run(_summary(30), "2026-11-15T20:00:00")
	a.record_run(_summary(12, false), "2026-11-15T20:10:00")
	assert_true(a.save_data(), "zapis")
	var b := ProgressStore.new(p)
	assert_true(b.load_data(), "odczyt")
	assert_eq(b.total_scrap(), 42)
	assert_eq(typeof(b.data["total_scrap"]), TYPE_INT, "liczby wracają jako int")
	assert_eq(b.runs().size(), 2)
	assert_eq(int(b.data["runs_completed"]), 1, "przerwana wyprawa się nie liczy do ukończonych")
	assert_eq(int(b.data["best_run_scrap"]), 30)
	assert_eq(str(b.runs()[0]["date"]), "2026-11-15T20:00:00")


func test_missing_file_gives_defaults() -> void:
	var p := _fresh_path("missing")
	var s := ProgressStore.new(p)
	assert_false(s.load_data())
	assert_eq(s.total_scrap(), 0)
	assert_eq(int(s.data["version"]), ProgressStore.FORMAT_VERSION)


func test_corrupt_file_falls_back_to_backup() -> void:
	var p := _fresh_path("corrupt")
	var s := ProgressStore.new(p)
	s.record_run(_summary(10))
	s.save_data()
	s.record_run(_summary(5))
	s.save_data()
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("{ to nie jest JSON")
	f.close()
	var r := ProgressStore.new(p)
	assert_true(r.load_data(), "odczyt z kopii")
	assert_eq(r.loaded_from, p + ".bak")
	assert_eq(r.total_scrap(), 10, "kopia sprzed ostatniego zapisu")


func test_save_overwrites_existing_file_atomically() -> void:
	var p := _fresh_path("overwrite")
	var s := ProgressStore.new(p)
	for i in 3:
		s.record_run(_summary(1))
		assert_true(s.save_data(), "zapis %d" % i)
	assert_false(FileAccess.file_exists(p + ".tmp"), "brak pliku tymczasowego po zapisie")
	var r := ProgressStore.new(p)
	r.load_data()
	assert_eq(r.total_scrap(), 3)


func test_unknown_future_fields_survive() -> void:
	var p := _fresh_path("future")
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "total_scrap": 7, "runs": [], "upgrades": {"engine": 2}}))
	f.close()
	var s := ProgressStore.new(p)
	assert_true(s.load_data())
	assert_eq(s.total_scrap(), 7)
	assert_true(s.data.has("upgrades"), "pola z przyszłych etapów zostają")


func test_history_is_capped() -> void:
	var s := ProgressStore.new(_fresh_path("cap"))
	for i in ProgressStore.MAX_RUNS + 15:
		s.record_run(_summary(1))
	assert_eq(s.runs().size(), ProgressStore.MAX_RUNS)
	assert_eq(s.total_scrap(), ProgressStore.MAX_RUNS + 15, "suma liczy wszystkie wyprawy")
