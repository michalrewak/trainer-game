class_name WorkoutJsonParser
extends RefCounted
## Parser naszego formatu planu JSON (opis i przykłady: docs/plany-treningowe.md).
## Używaj przez WorkoutLoader.parse_json(). Błędy wskazują miejsce w pliku ścieżką
## w stylu JSON, np. steps[1].steps[0].power.
##
##   {"name": "...", "description": "...", "steps": [
##       {"type": "warmup", "duration": "10:00", "from": 0.5, "to": 0.75},
##       {"repeat": 4, "steps": [
##           {"type": "work", "duration": 240, "power": 1.05, "cadence": 95, "label": "Burza"},
##           {"type": "recovery", "duration": "3:00", "power": 0.55}]},
##       {"type": "cooldown", "duration": "10:00", "from": 0.65, "to": 0.45}]}

const FORMAT_VERSION := 1
## Cel względny: najwyżej 300% FTP (większa liczba to prawie na pewno procenty albo waty).
const MAX_FRACTION := 3.0
const MAX_WATTS := 2500.0
const MAX_FTP := 2000.0
const MAX_CADENCE := 250.0
const MAX_REPEAT := 100
const MAX_DEPTH := 8
const MAX_STEPS := 5000
const MAX_TOTAL_S := 12.0 * 3600.0

## Domyślne cele, gdy krok nie podaje mocy (tylko te rodzaje mogą ją pominąć).
const DEFAULT_WARMUP: Array[float] = [0.50, 0.75]
const DEFAULT_COOLDOWN: Array[float] = [0.65, 0.45]
const DEFAULT_RECOVERY := 0.50

const RAMP_TYPE := "ramp"
const TYPE_ALIASES := {
	"interval": "work",
	"rest": "recovery",
	"free": "freeride",
	"free_ride": "freeride",
	"warm_up": "warmup",
	"cool_down": "cooldown",
}
const ROOT_KEYS: Array[String] = ["name", "description", "steps", "ftp", "absolute_watts", "version", "format", "author", "tags", "sport"]
const STEP_KEYS: Array[String] = ["type", "duration", "power", "from", "to", "cadence", "label"]
const REPEAT_KEYS: Array[String] = ["repeat", "steps", "label"]
const COMMENT_KEYS: Array[String] = ["comment", "comments", "note", "notes"]

var _error := ""
var _warnings: Array[String] = []
var _absolute := false
var _convert_ftp := 0.0
var _count := 0


func parse(text: String, ftp: float = WorkoutLoader.DEFAULT_FTP) -> Dictionary:
	_error = ""
	_warnings.clear()
	_absolute = false
	_convert_ftp = 0.0
	_count = 0
	if text.strip_edges() == "":
		return WorkoutLoader.failure("Plik planu jest pusty.")
	var json := JSON.new()
	if json.parse(text) != OK:
		return WorkoutLoader.failure("Błąd składni JSON w linii %d: %s." % [json.get_error_line(), json.get_error_message()])
	if not json.data is Dictionary:
		return WorkoutLoader.failure("Plan JSON musi być obiektem { ... } z listą kroków \"steps\".")
	var root: Dictionary = json.data
	var plan := WorkoutPlan.new()
	plan.source_format = "json"
	_warn_unknown_keys(root, ROOT_KEYS, "plan")
	plan.name = _optional_text(root, "name", "plan")
	plan.description = _optional_text(root, "description", "plan")
	_check_version(root)
	_read_watts_mode(root, ftp)
	if _error != "":
		return _failure()
	if not root.has("steps"):
		return WorkoutLoader.failure("Brak listy kroków \"steps\".", _warnings)
	var steps := _parse_list(root["steps"], "steps", 0)
	if _error != "":
		return _failure()
	plan.steps = steps
	var total := plan.total_duration_s()
	if total > MAX_TOTAL_S:
		return WorkoutLoader.failure("Plan trwa %s – to więcej niż 12 h, na pewno błąd w czasach kroków." % WorkoutStep.format_duration(total), _warnings)
	if _absolute:
		plan.reference_ftp = _convert_ftp
	return WorkoutLoader.success(plan, _warnings)


## Czas z tekstu: sekundy ("90", "90.5"), "mm:ss" ("4:30", "90:00") albo "h:mm:ss" ("1:05:00").
## Zwraca -1 dla niepoprawnego zapisu.
static func parse_duration_text(text: String) -> float:
	var s := text.strip_edges()
	if s.is_valid_float():
		return s.to_float()
	var parts := s.split(":")
	if parts.size() < 2 or parts.size() > 3:
		return -1.0
	var numbers: Array[int] = []
	for part in parts:
		if not part.is_valid_int() or part.begins_with("+") or part.begins_with("-"):
			return -1.0
		numbers.append(part.to_int())
	if numbers[numbers.size() - 1] >= 60:
		return -1.0
	if numbers.size() == 2:
		return numbers[0] * 60.0 + numbers[1]
	if numbers[1] >= 60:
		return -1.0
	return numbers[0] * 3600.0 + numbers[1] * 60.0 + numbers[2]


func _failure() -> Dictionary:
	return WorkoutLoader.failure(_error, _warnings)


func _fail(message: String) -> void:
	if _error == "":
		_error = message


func _warn(message: String) -> void:
	_warnings.append(message)


func _check_version(root: Dictionary) -> void:
	if not root.has("version"):
		return
	var v: Variant = root["version"]
	if not _is_number(v):
		_fail("Pole \"version\" musi być liczbą.")
	elif float(v) > FORMAT_VERSION:
		_warn("Plan zapisano w nowszej wersji formatu (%s) – wczytuję to, co rozumiem." % str(v))


func _read_watts_mode(root: Dictionary, ftp: float) -> void:
	if root.has("absolute_watts"):
		if not root["absolute_watts"] is bool:
			_fail("Pole \"absolute_watts\" musi mieć wartość true albo false.")
			return
		_absolute = root["absolute_watts"]
	var file_ftp := 0.0
	if root.has("ftp"):
		var v: Variant = root["ftp"]
		if not _is_number(v) or float(v) <= 0.0 or float(v) > MAX_FTP:
			_fail("Pole \"ftp\" musi być liczbą watów od 1 do %d." % int(MAX_FTP))
			return
		file_ftp = float(v)
	if _absolute:
		# FTP z pliku, a bez niego FTP gracza – wtedy waty z planu zostają dokładnie takie, jak zapisane.
		_convert_ftp = file_ftp if file_ftp > 0.0 else (ftp if ftp > 0.0 else WorkoutLoader.DEFAULT_FTP)


func _parse_list(value: Variant, path: String, depth: int) -> Array[WorkoutStep]:
	var out: Array[WorkoutStep] = []
	if not value is Array:
		_fail("%s: oczekiwano listy kroków [ ... ]." % path)
		return out
	var list: Array = value
	if list.is_empty():
		_fail("%s: lista kroków jest pusta." % path)
		return out
	for i in list.size():
		var item_path := "%s[%d]" % [path, i]
		if not list[i] is Dictionary:
			_fail("%s: krok musi być obiektem { ... }." % item_path)
			return out
		var item: Dictionary = list[i]
		if item.has("repeat") or item.has("steps"):
			out.append_array(_parse_repeat(item, item_path, depth))
		else:
			var step := _parse_step(item, item_path)
			if step != null:
				out.append(step)
				_count += 1
		if _error != "":
			return out
		if _count > MAX_STEPS:
			_fail("Plan ma więcej niż %d kroków po rozwinięciu powtórzeń." % MAX_STEPS)
			return out
	return out


func _parse_repeat(d: Dictionary, path: String, depth: int) -> Array[WorkoutStep]:
	var out: Array[WorkoutStep] = []
	if depth >= MAX_DEPTH:
		_fail("%s: zbyt głęboko zagnieżdżone powtórzenia (najwyżej %d poziomów)." % [path, MAX_DEPTH])
		return out
	if not d.has("repeat"):
		_fail("%s: blok kroków wymaga pola \"repeat\" (liczba powtórzeń)." % path)
		return out
	if not d.has("steps"):
		_fail("%s: blok powtórzeń wymaga listy \"steps\"." % path)
		return out
	_warn_unknown_keys(d, REPEAT_KEYS, path)
	var count := _parse_count(d["repeat"], path + ".repeat")
	if _error != "":
		return out
	var children := _parse_list(d["steps"], path + ".steps", depth + 1)
	if _error != "":
		return out
	var added := (count - 1) * children.size()
	if _count + added > MAX_STEPS:
		_fail("Plan ma więcej niż %d kroków po rozwinięciu powtórzeń (%s)." % [MAX_STEPS, path])
		return out
	_count += added
	for r in count:
		for child in children:
			out.append(child if r == 0 else child.copy())
	return out


func _parse_step(d: Dictionary, path: String) -> WorkoutStep:
	_warn_unknown_keys(d, STEP_KEYS, path)
	if not d.has("type"):
		_fail("%s: brak pola \"type\" (warmup, cooldown, work, recovery, steady, freeride, ramp)." % path)
		return null
	if not d["type"] is String:
		_fail("%s.type: typ kroku musi być tekstem." % path)
		return null
	var type_name: String = (d["type"] as String).strip_edges().to_lower()
	type_name = TYPE_ALIASES.get(type_name, type_name)
	var ramp := type_name == RAMP_TYPE
	var kind_index := WorkoutStep.kind_from_name(type_name)
	if kind_index < 0 and not ramp:
		_fail("%s.type: nieznany typ kroku „%s” (warmup, cooldown, work, recovery, steady, freeride, ramp)." % [path, d["type"]])
		return null
	if not d.has("duration"):
		_fail("%s: brak pola \"duration\" (sekundy albo „mm:ss”)." % path)
		return null
	var duration := _parse_duration(d["duration"], path + ".duration")
	var cadence := _parse_cadence(d, path)
	var label := _optional_text(d, "label", path)
	if _error != "":
		return null
	var has_power := d.has("power")
	var has_from := d.has("from")
	if has_from != d.has("to"):
		_fail("%s: zmienny cel wymaga obu pól \"from\" i \"to\"." % path)
		return null
	if has_power and has_from:
		_fail("%s: podaj albo \"power\", albo \"from\"/\"to\" – nie oba naraz." % path)
		return null
	if ramp and not has_from:
		_fail("%s: rampa wymaga pól \"from\" i \"to\" (ułamki FTP)." % path)
		return null
	if kind_index == WorkoutStep.Kind.FREERIDE:
		if has_power or has_from:
			_warn("%s: jazda swobodna nie ma celu mocy – pominięto power/from/to." % path)
		return WorkoutStep.new(WorkoutStep.Kind.FREERIDE, duration, 0.0, 0.0, cadence, label)
	var start := 0.0
	var end := 0.0
	if has_power:
		start = _parse_power(d["power"], path + ".power")
		end = start
	elif has_from:
		start = _parse_power(d["from"], path + ".from")
		end = _parse_power(d["to"], path + ".to")
	else:
		match kind_index:
			WorkoutStep.Kind.WARMUP:
				start = DEFAULT_WARMUP[0]
				end = DEFAULT_WARMUP[1]
			WorkoutStep.Kind.COOLDOWN:
				start = DEFAULT_COOLDOWN[0]
				end = DEFAULT_COOLDOWN[1]
			WorkoutStep.Kind.RECOVERY:
				start = DEFAULT_RECOVERY
				end = DEFAULT_RECOVERY
			_:
				_fail("%s: brak celu mocy – dodaj \"power\" (ułamek FTP, np. 0.75) albo \"from\" i \"to\"." % path)
	if _error != "":
		return null
	var kind: WorkoutStep.Kind = WorkoutStep.kind_for_power((start + end) * 0.5) if ramp else kind_index as WorkoutStep.Kind
	return WorkoutStep.new(kind, duration, start, end, cadence, label)


func _parse_duration(v: Variant, path: String) -> float:
	var seconds := -1.0
	if _is_number(v):
		seconds = float(v)
	elif v is String:
		seconds = parse_duration_text(v)
		if seconds < 0.0:
			_fail("%s: nieprawidłowy czas „%s” – podaj sekundy (np. 90) albo „mm:ss” (np. „4:30”)." % [path, v])
			return 0.0
	else:
		_fail("%s: czas musi być liczbą sekund albo tekstem „mm:ss”." % path)
		return 0.0
	if not is_finite(seconds) or seconds <= 0.0:
		_fail("%s: czas kroku musi być większy od zera." % path)
		return 0.0
	if seconds > MAX_TOTAL_S:
		_fail("%s: krok dłuższy niż 12 h." % path)
		return 0.0
	return seconds


## Moc jako ułamek FTP: liczba (0.95) albo tekst z procentem ("95%"). Przy absolute_watts
## liczba to waty, przeliczane na ułamek FTP z pola "ftp" (albo FTP gracza).
func _parse_power(v: Variant, path: String) -> float:
	var value := 0.0
	var percent := false
	if _is_number(v):
		value = float(v)
	elif v is String and (v as String).strip_edges().ends_with("%"):
		var number := (v as String).strip_edges().trim_suffix("%").strip_edges()
		if not number.is_valid_float():
			_fail("%s: nieprawidłowa moc „%s”." % [path, v])
			return 0.0
		value = number.to_float() / 100.0
		percent = true
	else:
		_fail("%s: moc musi być liczbą – ułamkiem FTP, np. 0.75 (albo tekstem „75%%”)." % path)
		return 0.0
	if not is_finite(value) or value < 0.0:
		_fail("%s: moc nie może być ujemna." % path)
		return 0.0
	if _absolute and not percent:
		if value > MAX_WATTS:
			_fail("%s: %s W to za dużo (najwyżej %d W)." % [path, str(v), int(MAX_WATTS)])
			return 0.0
		return value / _convert_ftp
	if value > MAX_FRACTION:
		_fail("%s: moc %s to więcej niż 300%% FTP. Moc podaje się jako ułamek FTP (0.95 = 95%%); dla watów ustaw \"absolute_watts\": true." % [path, str(v)])
		return 0.0
	return value


func _parse_cadence(d: Dictionary, path: String) -> float:
	if not d.has("cadence"):
		return 0.0
	var v: Variant = d["cadence"]
	if not _is_number(v) or float(v) < 0.0 or float(v) > MAX_CADENCE:
		_fail("%s.cadence: kadencja musi być liczbą od 0 do %d obr./min." % [path, int(MAX_CADENCE)])
		return 0.0
	return float(v)


func _parse_count(v: Variant, path: String) -> int:
	if not _is_number(v) or float(v) != floorf(float(v)):
		_fail("%s: liczba powtórzeń musi być liczbą całkowitą." % path)
		return 0
	var f := float(v)
	if f < 1.0 or f > MAX_REPEAT:
		_fail("%s: liczba powtórzeń musi być od 1 do %d." % [path, MAX_REPEAT])
		return 0
	return int(f)


func _optional_text(d: Dictionary, key: String, path: String) -> String:
	if not d.has(key):
		return ""
	if not d[key] is String:
		_fail("%s.%s: pole musi być tekstem." % [path, key])
		return ""
	return (d[key] as String).strip_edges()


func _warn_unknown_keys(d: Dictionary, known: Array[String], path: String) -> void:
	for key: Variant in d.keys():
		var k := str(key)
		if known.has(k) or k.begins_with("_") or COMMENT_KEYS.has(k):
			continue
		_warn("%s: nieznane pole „%s” – pominięte." % [path, k])


static func _is_number(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))
