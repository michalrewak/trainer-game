extends SceneTree
## Kompiluje wszystkie skrypty i wczytuje wszystkie sceny projektu – łapie błędy
## parsowania/typów, zanim ujawnią się dopiero w trakcie gry.
##   godot --headless --path game --script res://tests/check_scripts.gd
## Kod wyjścia: 0 = wszystko się kompiluje, 1 = błędy.

const ROOTS := ["res://scripts", "res://scenes", "res://tests", "res://tools"]


func _initialize() -> void:
	var files: Array[String] = []
	for root_dir in ROOTS:
		_collect(root_dir, files)
	var bad := 0
	var self_path: String = (get_script() as Script).resource_path
	for f in files:
		if f == self_path:
			continue
		var res: Resource = ResourceLoader.load(f)
		var ok := res != null
		if ok and res is GDScript:
			ok = (res as GDScript).can_instantiate() or (res as GDScript).is_abstract()
		if ok and res is PackedScene:
			ok = (res as PackedScene).can_instantiate()
		if not ok:
			bad += 1
			printerr("BŁĄD: ", f)
	print("Sprawdzono %d plików, błędów: %d" % [files.size(), bad])
	quit(1 if bad > 0 else 0)


func _collect(path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if sub.begins_with("_") or sub.begins_with("."):
			continue
		_collect(path + "/" + sub, out)
	for file in dir.get_files():
		if file.ends_with(".gd") or file.ends_with(".tscn"):
			out.append(path + "/" + file)
