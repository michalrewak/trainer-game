extends SceneTree
## Runner testów jednostkowych (logika czysta, bez sceny):
##   godot --headless --path game --import
##   godot --headless --path game --script res://tests/run_tests.gd
## Kod wyjścia: 0 = wszystko zielone, 1 = są błędy. Opcjonalnie: -- --filter=vehicle

const UNIT_DIR := "res://tests/unit"


func _initialize() -> void:
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.substr(9)
	var files := _test_files()
	var passed := 0
	var failed := 0
	var started := Time.get_ticks_msec()
	for file in files:
		if filter != "" and not file.contains(filter):
			continue
		var script: GDScript = load(file)
		if script == null:
			printerr("NIE WCZYTANO: ", file)
			failed += 1
			continue
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			var method_name: String = m["name"]
			if method_name.begins_with("test_") and not methods.has(method_name):
				methods.append(method_name)
		for method_name in methods:
			var instance: TestCase = script.new()
			instance.begin(method_name)
			instance.call(method_name)
			var label := "%s :: %s" % [file.get_file().get_basename(), method_name]
			if instance.failures.is_empty():
				passed += 1
				print("  ok    ", label)
			else:
				failed += 1
				print("  BŁĄD  ", label)
				for f in instance.failures:
					print("        - ", f)
	var ms := Time.get_ticks_msec() - started
	print("")
	print("Testy: %d ok, %d błędów (%d ms)" % [passed, failed, ms])
	quit(1 if failed > 0 or passed == 0 else 0)


func _test_files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(UNIT_DIR)
	if dir == null:
		printerr("Brak katalogu ", UNIT_DIR)
		return out
	for name in dir.get_files():
		var file := name.trim_suffix(".remap")
		if file.begins_with("test_") and file.ends_with(".gd"):
			out.append(UNIT_DIR + "/" + file)
	out.sort()
	return out
