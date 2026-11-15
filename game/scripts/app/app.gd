extends Node
## Autoload "App": opcje uruchomienia, postęp gracza, przełączanie ekranów oraz okno
## (pełny ekran, przenoszenie na drugi monitor/telewizor, skala renderowania 3D).

const START_SCENE := "res://scenes/ui/garage.tscn"
const RUN_SCENE := "res://scenes/run/run.tscn"
const SUMMARY_SCENE := "res://scenes/ui/summary_screen.tscn"
const SETTINGS_PATH := "user://settings.json"

var options: LaunchOptions
var progress: ProgressStore
var settings: Dictionary = {}
var selected_minutes := LaunchOptions.DEFAULT_MINUTES
var selected_terrain := "canyon"
var last_summary: Dictionary = {}
var last_total_before := 0
## Aktywna wyprawa (RunController) – żeby zapisać postęp przy zamknięciu okna.
var active_run: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	options = LaunchOptions.parse(OS.get_cmdline_user_args())
	progress = ProgressStore.new(options.save_path)
	progress.load_data()
	settings = _load_settings()
	selected_minutes = options.minutes if options.minutes_from_cli else float(settings.get("minutes", LaunchOptions.DEFAULT_MINUTES))
	selected_terrain = str(settings.get("terrain", "canyon"))
	if not TerrainCatalog.is_unlocked(selected_terrain, progress.loadout(), ftp_w()):
		selected_terrain = TerrainCatalog.CANYON
	if options.terrain != "" and TerrainCatalog.DEFS.has(options.terrain):
		selected_terrain = options.terrain
	Engine.time_scale = options.time_scale
	get_tree().set_auto_accept_quit(false)
	_setup_display()
	if options.autostart:
		start_run.call_deferred(selected_minutes)


func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


# --- Przepływ ekranów -------------------------------------------------------

func start_run(minutes: float) -> void:
	selected_minutes = maxf(0.05, minutes)
	if not options.minutes_from_cli:
		settings["minutes"] = selected_minutes
	settings["terrain"] = selected_terrain
	_save_settings()
	get_tree().paused = false
	get_tree().change_scene_to_file(RUN_SCENE)


func power_source_kind() -> String:
	return PowerSourceFactory.KIND_AUTOPILOT if options.autopilot else PowerSourceFactory.KIND_GAMEPAD


func run_duration_s() -> float:
	return selected_minutes * 60.0


func run_seed() -> int:
	return options.seed_value if options.seed_value >= 0 else randi()


## Moduły na tę wyprawę (z magazynu albo – przy --all-upgrades – wszystkie na maks.).
func run_loadout() -> Loadout:
	if options.all_upgrades:
		var maxed := {}
		for id in UpgradeCatalog.ORDER:
			maxed[id] = UpgradeCatalog.max_level(id)
		return Loadout.new(maxed)
	return progress.loadout()


## FTP gracza (W) – z ustawień; domyślnie 200 W, dopóki gracz nie poda własnego.
func ftp_w() -> float:
	return clampf(float(settings.get("ftp", 200.0)), 80.0, 500.0)


func set_ftp_w(value: float) -> void:
	settings["ftp"] = clampf(roundf(value / 5.0) * 5.0, 80.0, 500.0)
	_save_settings()


## Moc docelowa „zasilania” w jeździe swobodnej: spokojne tempo (65% FTP).
func free_ride_target_w() -> float:
	return roundf(ftp_w() * 0.65 / 5.0) * 5.0


## Automatyczny ogień wieżyczki (wygoda na ciężkich odcinkach) – z ustawień.
func auto_fire_enabled() -> bool:
	return bool(settings.get("auto_fire", false))


func set_auto_fire(enabled: bool) -> void:
	settings["auto_fire"] = enabled
	_save_settings()


## Zapisuje wynik wyprawy (ukończonej albo przerwanej) i pokazuje podsumowanie.
func finish_run(summary: Dictionary) -> void:
	active_run = null
	last_total_before = progress.total_scrap()
	progress.record_run(summary)
	var saved := progress.save_data()
	last_summary = summary.duplicate()
	last_summary["saved"] = saved
	print("Wyprawa zapisana=%s: %s" % [saved, JSON.stringify(summary)])
	if options.quit_on_finish:
		get_tree().quit(0 if saved else 2)
		return
	get_tree().paused = false
	get_tree().change_scene_to_file(SUMMARY_SCENE)


func go_to_start() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(START_SCENE)


func quit_game() -> void:
	if active_run != null and active_run.has_method("save_partial_run"):
		active_run.save_partial_run()
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


# --- Okno i wyświetlacz -----------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_fullscreen"):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"next_screen"):
		move_to_next_screen()
		get_viewport().set_input_as_handled()


func toggle_fullscreen() -> void:
	if is_headless():
		return
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Przenosi okno na kolejny ekran (np. z laptopa na telewizor) i zapamiętuje wybór.
func move_to_next_screen() -> void:
	if is_headless():
		return
	var count := DisplayServer.get_screen_count()
	if count < 2:
		return
	var next := (DisplayServer.window_get_current_screen() + 1) % count
	_move_to_screen(next)
	settings["screen"] = next
	_save_settings()


func _move_to_screen(screen: int) -> void:
	var mode := DisplayServer.window_get_mode()
	var was_fullscreen := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if was_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_current_screen(screen)
	if was_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _setup_display() -> void:
	if is_headless():
		return
	# Jeśli użytkownik sam podał --screen, nie nadpisujemy go zapamiętanym ekranem.
	var cli_screen := OS.get_cmdline_args().has("--screen")
	var saved_screen := int(settings.get("screen", -1))
	if not cli_screen and saved_screen >= 0 and saved_screen < DisplayServer.get_screen_count():
		_move_to_screen.call_deferred(saved_screen)


# --- Ustawienia lokalne (nie postęp) ---------------------------------------

func _load_settings() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	return parsed if parsed is Dictionary else {}


func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(settings, "  "))
		f.close()
