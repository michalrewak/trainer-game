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
		"records": {},
		"campaigns": {},
		"campaign_active": "",
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
# --- Kampanie treningowe ---

## Wybrana kampania ("" = żadna jeszcze nie wybrana).
func campaign_active() -> String:
	var id := str(data.get("campaign_active", ""))
	return id if CampaignCatalog.has(id) else ""


func set_campaign_active(id: String) -> void:
	if CampaignCatalog.has(id):
		data["campaign_active"] = id


## Zaliczone sesje kampanii, po kolei: [{"index", "date", "in_band_pct", "tss", "boss_defeated"}].
func campaign_done(id: String) -> Array:
	var all: Variant = data.get("campaigns", {})
	if not (all is Dictionary) or not ((all as Dictionary).get(id) is Dictionary):
		return []
	var done: Variant = ((all as Dictionary)[id] as Dictionary).get("done", [])
	return done if done is Array else []


## Numer następnej sesji do przejechania (= liczba zaliczonych).
func campaign_next_index(id: String) -> int:
	return mini(campaign_done(id).size(), CampaignCatalog.session_count(id)) if CampaignCatalog.has(id) else 0


func campaign_finished(id: String) -> bool:
	return CampaignCatalog.has(id) and campaign_done(id).size() >= CampaignCatalog.session_count(id)


## Ile razy kampania została ukończona w całości.
func campaign_completions(id: String) -> int:
	var all: Variant = data.get("campaigns", {})
	if all is Dictionary and (all as Dictionary).get(id) is Dictionary:
		return int(((all as Dictionary)[id] as Dictionary).get("completions", 0))
	return 0


## Zaczyna kampanię od pierwszej sesji (licznik ukończeń zostaje).
func restart_campaign(id: String) -> void:
	if not CampaignCatalog.has(id):
		return
	var all: Dictionary = data.get("campaigns", {}) if data.get("campaigns") is Dictionary else {}
	all[id] = {"done": [], "completions": campaign_completions(id)}
	data["campaigns"] = all


## Zalicza sesję kampanii, jeśli to ta, która była następna w kolejce.
func _record_campaign_session(info: Dictionary, summary: Dictionary, date: String) -> void:
	var id := str(info.get("id", ""))
	var index := int(info.get("index", -1))
	if not CampaignCatalog.has(id) or index != campaign_next_index(id) or campaign_finished(id):
		return
	var all: Dictionary = data.get("campaigns", {}) if data.get("campaigns") is Dictionary else {}
	var mine: Dictionary = all.get(id, {}) if all.get(id) is Dictionary else {}
	var done: Array = mine.get("done", []) if mine.get("done") is Array else []
	done.append({
		"index": index, "date": date,
		"in_band_pct": int(summary.get("workout_in_band_pct", 0)), "tss": float(summary.get("tss", 0.0)),
		"boss_defeated": bool(info.get("boss_defeated", false)),
	})
	mine["done"] = done
	if done.size() >= CampaignCatalog.session_count(id):
		mine["completions"] = int(mine.get("completions", 0)) + 1
	all[id] = mine
	data["campaigns"] = all
	data["campaign_active"] = id


## Klucze rekordów i ich nazwy do ekranów. Moc liczona osobno dla każdego źródła
## ("pad", "trainer"), żeby symulacja na triggerze nie mieszała się z prawdziwymi watami.
const RECORD_NAMES := {
	"best_20s_w": "Moc 20 s", "best_1min_w": "Moc 1 min", "best_5min_w": "Moc 5 min", "best_20min_w": "Moc 20 min",
	"best_streak": "Passa", "scrap": "Złom z wyprawy", "energy_kj": "Praca z wyprawy",
}


func record(source: String, key: String) -> float:
	var all: Dictionary = data.get("records", {})
	var mine: Variant = all.get(source, {})
	return float((mine as Dictionary).get(key, 0.0)) if mine is Dictionary else 0.0


## Opis rekordu do wyświetlenia, np. "Moc 1 min: 265 W".
static func record_text(key: String, value: float) -> String:
	var unit := " W"
	if key == "best_streak":
		return "%s: ×%.1f" % [RECORD_NAMES[key], value]
	if key == "scrap":
		unit = ""
	elif key == "energy_kj":
		unit = " kJ"
	return "%s: %d%s" % [RECORD_NAMES[key], roundi(value), unit]


## Ile dni z rzędu (do dziś albo wczoraj) była choć jedna wyprawa.
func day_streak(today: String = "") -> int:
	var days := {}
	for r: Variant in runs():
		if r is Dictionary:
			days[str((r as Dictionary).get("date", "")).substr(0, 10)] = true
	var now := Time.get_unix_time_from_datetime_string((today if today != "" else Time.get_date_string_from_system()) + "T12:00:00")
	var count := 0
	var offset := 0
	if not days.has(Time.get_date_string_from_unix_time(int(now))):
		offset = 1
	while days.has(Time.get_date_string_from_unix_time(int(now) - (count + offset) * 86400)):
		count += 1
	return count


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
	# Rekordy: wynik lepszy od zapisanego dla tego samego źródła mocy. Autopilot się nie liczy.
	var source := str(summary.get("source", "pad"))
	var broken: Array = []
	if source != "auto":
		var all: Dictionary = data.get("records", {})
		var mine: Dictionary = all.get(source, {}) if all.get(source, {}) is Dictionary else {}
		for key: String in RECORD_NAMES:
			var value := float(summary.get(key, 0.0))
			if value > float(mine.get(key, 0.0)) + 0.001 and (key != "best_streak" or value > 1.0):
				# Pierwsza wyprawa ustawia poziom odniesienia bez fanfar.
				if mine.has(key):
					broken.append(key)
				mine[key] = value
		all[source] = mine
		data["records"] = all
	summary["new_records"] = broken
	var run := summary.duplicate(true)
	run["date"] = timestamp if timestamp != "" else Time.get_datetime_string_from_system(false, true)
	# Kampania: sesja liczy się tylko przejechana do końca.
	if summary.get("campaign") is Dictionary and bool(summary.get("completed", false)):
		_record_campaign_session(summary["campaign"], summary, str(run["date"]))
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
	clean["records"] = (raw.get("records") as Dictionary).duplicate(true) if raw.get("records") is Dictionary else {}
	clean["campaigns"] = (raw.get("campaigns") as Dictionary).duplicate(true) if raw.get("campaigns") is Dictionary else {}
	clean["campaign_active"] = str(raw.get("campaign_active", ""))
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
