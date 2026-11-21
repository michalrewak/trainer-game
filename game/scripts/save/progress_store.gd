class_name ProgressStore
extends RefCounted
## Trwały postęp gracza w pliku JSON (domyślnie user://progress.json, na Windows:
## %APPDATA%\Godot\app_userdata\Wasteland Rider\progress.json).
##
## Zapis jest atomowy: najpierw plik .tmp, potem poprzednia wersja -> .bak, a .tmp -> właściwy
## plik. Odczyt próbuje kolejno: plik główny, .tmp, .bak; uszkodzony plik nigdy nie
## wywraca gry – w najgorszym razie startujemy od zera.

const FORMAT_VERSION := 1
const MAX_RUNS := 200

var path := "user://progress.json"
var data: Dictionary = {}
var loaded_from := ""


func _init(p_path: String = "user://progress.json") -> void:
	path = p_path
	data = default_data()


static func default_data() -> Dictionary:
	return {
		"version": FORMAT_VERSION,
		"total_scrap": 0,
		"fuel": 0,
		"crew": 0,
		"total_energy_kj": 0,
		"upgrades": {},
		"runs_completed": 0,
		"total_distance_m": 0,
		"best_run_scrap": 0,
		"runs": [],
	}


func total_scrap() -> int:
	return int(data.get("total_scrap", 0))


func fuel() -> int:
	return int(data.get("fuel", 0))


func upgrade_level(id: String) -> int:
	return int((data.get("upgrades", {}) as Dictionary).get(id, 0))


## Uwolnieni pedalarze (rosną z każdą przejętą galerą).
func crew() -> int:
	return int(data.get("crew", 0))


func loadout() -> Loadout:
	var l := Loadout.new(data.get("upgrades", {}))
	l.crew = crew()
	return l


## Trening z ostatnich dni: {"runs", "tss", "kj", "minutes"} – do garażu.
func recent_stats(days: int = 7) -> Dictionary:
	var out := {"runs": 0, "tss": 0.0, "kj": 0, "minutes": 0}
	var since := Time.get_unix_time_from_system() - days * 86400.0
	for r: Variant in runs():
		if not (r is Dictionary):
			continue
		var run: Dictionary = r
		var when := Time.get_unix_time_from_datetime_string(str(run.get("date", "")).replace(" ", "T"))
		if when < since:
			continue
		out["runs"] = int(out["runs"]) + 1
		out["tss"] = float(out["tss"]) + float(run.get("tss", 0.0))
		out["kj"] = int(out["kj"]) + int(run.get("energy_kj", 0))
		out["minutes"] = int(out["minutes"]) + roundi(float(run.get("duration_s", 0)) / 60.0)
	return out


## Łączna praca wykonana na wszystkich wyprawach [kJ] – odblokowuje większe podwozia.
func total_energy_kj() -> int:
	return int(data.get("total_energy_kj", 0))


func chassis_level() -> int:
	return upgrade_level(UpgradeCatalog.CHASSIS)


func can_buy(id: String) -> bool:
	return block_reason(id) == ""


## Dlaczego nie można kupić następnego poziomu ("" = można). Tekst do garażu.
func block_reason(id: String) -> String:
	var lvl := upgrade_level(id)
	var cost := UpgradeCatalog.next_cost(id, lvl)
	if cost.is_empty():
		return "Maksymalny poziom."
	if lvl >= UpgradeCatalog.level_cap(id, chassis_level()):
		return "Wymaga większego podwozia."
	var need_kj := UpgradeCatalog.required_kj(id, lvl)
	if total_energy_kj() < need_kj:
		return "Wymaga %d kJ łącznej pracy (masz %d kJ)." % [need_kj, total_energy_kj()]
	var missing_scrap := int(cost["scrap"]) - total_scrap()
	var missing_fuel := int(cost["fuel"]) - fuel()
	if missing_scrap > 0 or missing_fuel > 0:
		var parts: Array[String] = []
		if missing_scrap > 0:
			parts.append("%d złomu" % missing_scrap)
		if missing_fuel > 0:
			parts.append("%d paliwa" % missing_fuel)
		return "Brakuje: %s." % " i ".join(parts)
	return ""


## Najbliższy cel rozwoju: na co już stać albo czego brakuje do najtańszego modułu.
func next_goal() -> String:
	var best_id := ""
	var best_scrap := 1 << 30
	for id in UpgradeCatalog.ORDER:
		var lvl := upgrade_level(id)
		var cost := UpgradeCatalog.next_cost(id, lvl)
		if cost.is_empty() or lvl >= UpgradeCatalog.level_cap(id, chassis_level()):
			continue
		if can_buy(id):
			return "Stać cię na: %s poz. %d" % [UpgradeCatalog.display_name(id), lvl + 1]
		if total_energy_kj() >= UpgradeCatalog.required_kj(id, lvl) and int(cost["scrap"]) < best_scrap:
			best_scrap = int(cost["scrap"])
			best_id = id
	if best_id == "":
		var need := UpgradeCatalog.required_kj(UpgradeCatalog.CHASSIS, chassis_level())
		if need > 0:
			return "Większe podwozie: jeszcze %d kJ pracy" % maxi(0, need - total_energy_kj())
		return "Pojazd rozbudowany do końca"
	return "%s poz. %d – %s" % [UpgradeCatalog.display_name(best_id), upgrade_level(best_id) + 1, block_reason(best_id).to_lower()]


## Kupuje następny poziom ulepszenia (zapis pliku robi wywołujący). Zwraca powodzenie.
func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	var cost := UpgradeCatalog.next_cost(id, upgrade_level(id))
	data["total_scrap"] = total_scrap() - int(cost["scrap"])
	data["fuel"] = fuel() - int(cost["fuel"])
	var ups: Dictionary = data.get("upgrades", {})
	ups[id] = upgrade_level(id) + 1
	data["upgrades"] = ups
	return true


func runs() -> Array:
	return data.get("runs", [])


## Dopisuje wyprawę (podsumowanie z Expedition.to_summary) i aktualizuje sumy.
func record_run(summary: Dictionary, timestamp: String = "") -> void:
	var run := summary.duplicate(true)
	run["date"] = timestamp if timestamp != "" else Time.get_datetime_string_from_system(false, true)
	var scrap := int(run.get("scrap", 0))
	data["total_scrap"] = total_scrap() + scrap
	data["fuel"] = fuel() + int(run.get("fuel", 0))
	data["crew"] = crew() + int(run.get("pedalers_freed", 0))
	data["total_energy_kj"] = total_energy_kj() + int(run.get("energy_kj", 0))
	data["total_distance_m"] = int(data.get("total_distance_m", 0)) + int(run.get("distance_m", 0))
	if bool(run.get("completed", false)):
		data["runs_completed"] = int(data.get("runs_completed", 0)) + 1
	data["best_run_scrap"] = maxi(int(data.get("best_run_scrap", 0)), scrap)
	var history: Array = runs()
	history.append(run)
	while history.size() > MAX_RUNS:
		history.pop_front()
	data["runs"] = history


func load_data() -> bool:
	for candidate in [path, path + ".tmp", path + ".bak"]:
		var parsed := _read_json(candidate)
		if not parsed.is_empty():
			data = _sanitize(parsed)
			loaded_from = candidate
			return true
	data = default_data()
	loaded_from = ""
	return false


func save_data() -> bool:
	var text := JSON.stringify(data, "  ")
	var tmp := path + ".tmp"
	var bak := path + ".bak"
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("ProgressStore: nie mogę zapisać %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(text)
	file.close()
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		var err_bak := DirAccess.rename_absolute(path, bak)
		if err_bak != OK:
			push_warning("ProgressStore: nie udało się utworzyć kopii .bak (%s)" % error_string(err_bak))
			DirAccess.remove_absolute(path)
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("ProgressStore: zmiana nazwy %s -> %s nie powiodła się (%s)" % [tmp, path, error_string(err)])
		return false
	return true


static func _read_json(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	var text := FileAccess.get_file_as_string(file_path)
	if text.strip_edges() == "":
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary and (parsed as Dictionary).has("total_scrap"):
		return parsed
	return {}


## JSON zwraca liczby jako float – przywracamy typy i uzupełniamy brakujące pola.
static func _sanitize(raw: Dictionary) -> Dictionary:
	var clean := default_data()
	clean["version"] = FORMAT_VERSION
	clean["total_scrap"] = maxi(0, int(raw.get("total_scrap", 0)))
	clean["fuel"] = maxi(0, int(raw.get("fuel", 0)))
	clean["crew"] = maxi(0, int(raw.get("crew", 0)))
	if raw.has("total_energy_kj"):
		clean["total_energy_kj"] = maxi(0, int(raw["total_energy_kj"]))
	elif raw.get("runs") is Array:
		# Starszy zapis: pracę odtwarzamy z historii wypraw.
		var kj := 0
		for r: Variant in raw["runs"]:
			if r is Dictionary:
				kj += int((r as Dictionary).get("energy_kj", 0))
		clean["total_energy_kj"] = kj
	var ups: Variant = raw.get("upgrades", {})
	var clean_ups := {}
	if ups is Dictionary:
		for id in UpgradeCatalog.ORDER:
			if (ups as Dictionary).has(id):
				clean_ups[id] = clampi(int(ups[id]), 0, UpgradeCatalog.max_level(id))
	clean["upgrades"] = clean_ups
	clean["runs_completed"] = maxi(0, int(raw.get("runs_completed", 0)))
	clean["total_distance_m"] = maxi(0, int(raw.get("total_distance_m", 0)))
	clean["best_run_scrap"] = maxi(0, int(raw.get("best_run_scrap", 0)))
	var history: Variant = raw.get("runs", [])
	clean["runs"] = (history as Array).duplicate(true) if history is Array else []
	# Pola z przyszłych etapów (np. ulepszenia) zachowujemy bez zmian.
	for key in raw.keys():
		if not clean.has(key):
			clean[key] = raw[key]
	return clean
