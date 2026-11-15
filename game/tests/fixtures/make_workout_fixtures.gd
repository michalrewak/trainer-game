extends SceneTree
## Generuje pliki FIT do game/tests/fixtures/workouts/ z definicji w WorkoutFixtures:
##   godot --headless --path game --import
##   godot --headless --path game --script res://tests/fixtures/make_workout_fixtures.gd
## Pliki są deterministyczne – ponowne uruchomienie daje identyczne bajty.


func _initialize() -> void:
	var files := WorkoutFixtures.fit_files()
	var failed := 0
	DirAccess.make_dir_recursive_absolute(WorkoutFixtures.DIR)
	for file_name: String in files:
		var bytes: PackedByteArray = files[file_name]
		var path := WorkoutFixtures.DIR.path_join(file_name)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			printerr("Nie mogę zapisać %s (%s)" % [path, error_string(FileAccess.get_open_error())])
			failed += 1
			continue
		f.store_buffer(bytes)
		f.close()
		print("zapisano %s (%d B)" % [path, bytes.size()])
	quit(1 if failed > 0 else 0)
