class_name WorkoutLoader
extends RefCounted
## Wczytywanie planów treningowych: nasz JSON, Zwift ZWO i Garmin FIT (eksport z Garmin Connect).
## Opis formatów: docs/plany-treningowe.md.
##
## Każda funkcja zwraca słownik:
##   {"plan": WorkoutPlan albo null, "error": String (pusty = OK), "warnings": Array[String]}
## Błędny plik nigdy nie wywraca gry: dostajemy plan == null i komunikat po polsku w "error".
## "warnings" to rzeczy, które wczytaliśmy z przybliżeniem (np. krok „do naciśnięcia Lap”).
##
## ftp (W) służy tylko do przeliczania planów zapisanych w watach (JSON z absolute_watts,
## cele FIT w watach) na ułamki FTP. Najlepiej podawać FTP gracza – wtedy waty z pliku
## zostają dokładnie takie, jak w pliku.

const DEFAULT_FTP := 250.0
const SUPPORTED_EXTENSIONS: Array[String] = ["json", "zwo", "fit"]
## Plan to kilka kB; większy plik to na pewno nie plan (np. zapis aktywności).
const MAX_FILE_BYTES := 4 * 1024 * 1024


## Wczytuje plan z pliku; format po rozszerzeniu (.json, .zwo, .fit – wielkość liter bez znaczenia).
static func load_file(path: String, ftp: float = DEFAULT_FTP) -> Dictionary:
	var ext := path.get_extension().to_lower()
	if not SUPPORTED_EXTENSIONS.has(ext):
		return failure("Nieobsługiwany format pliku „%s” – obsługiwane: .json, .zwo, .fit." % path.get_file())
	if not FileAccess.file_exists(path):
		return failure("Nie znaleziono pliku planu: %s" % path)
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		var open_error := FileAccess.get_open_error()
		if open_error != OK:
			return failure("Nie można odczytać pliku %s (%s)." % [path.get_file(), error_string(open_error)])
		return failure("Plik %s jest pusty." % path.get_file())
	if bytes.size() > MAX_FILE_BYTES:
		return failure("Plik %s jest za duży jak na plan treningowy (%d kB)." % [path.get_file(), roundi(bytes.size() / 1024.0)])
	var result: Dictionary
	match ext:
		"json":
			result = parse_json(_bytes_to_text(bytes), ftp)
		"zwo":
			result = parse_zwo(_bytes_to_text(bytes))
		_:
			result = parse_fit(bytes, ftp)
	var plan: WorkoutPlan = result["plan"]
	if plan != null:
		plan.source_path = path
		if plan.name.strip_edges() == "":
			plan.name = path.get_file().get_basename()
	elif result["error"] != "":
		result["error"] = "%s: %s" % [path.get_file(), result["error"]]
	return result


## Nasz format JSON (patrz docs/plany-treningowe.md).
static func parse_json(text: String, ftp: float = DEFAULT_FTP) -> Dictionary:
	return WorkoutJsonParser.new().parse(text, ftp)


## Plik treningu Zwift (.zwo, XML).
static func parse_zwo(text: String) -> Dictionary:
	return WorkoutZwoParser.new().parse(text)


## Plik treningu FIT (np. eksport z Garmin Connect).
static func parse_fit(bytes: PackedByteArray, ftp: float = DEFAULT_FTP) -> Dictionary:
	return WorkoutFitParser.new().parse(bytes, ftp)


## Czy plik ma obsługiwane rozszerzenie.
static func is_supported_file(path: String) -> bool:
	return SUPPORTED_EXTENSIONS.has(path.get_extension().to_lower())


## Ścieżki planów w katalogu (np. "res://plans" albo "user://plans"), posortowane po nazwie pliku.
## Uwaga: w wyeksportowanej grze pliki .json/.zwo/.fit trzeba dodać do filtra eksportu.
static func list_plan_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file in dir.get_files():
		if is_supported_file(file):
			out.append(dir_path.path_join(file))
	out.sort()
	return out


static func success(plan: WorkoutPlan, warnings: Array[String] = []) -> Dictionary:
	return {"plan": plan, "error": "", "warnings": warnings.duplicate()}


static func failure(message: String, warnings: Array[String] = []) -> Dictionary:
	return {"plan": null, "error": message, "warnings": warnings.duplicate()}


## Tekst UTF-8 (z ewentualnym BOM). Niepoprawne UTF-8 (i bajty zerowe) czytamy jako Latin-1
## z U+FFFD zamiast NUL, żeby nie zaśmiecać logów błędami dekodowania Godota – taki plik
## i tak skończy się czytelnym komunikatem o błędzie składni.
static func _bytes_to_text(bytes: PackedByteArray) -> String:
	var start := 3 if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF else 0
	var body := bytes.slice(start)
	if body.find(0) < 0 and FitDecoder.is_valid_utf8(body):
		return body.get_string_from_utf8()
	var chars := PackedStringArray()
	for b in body:
		chars.append(char(b) if b != 0 else char(0xFFFD))
	return "".join(chars)
