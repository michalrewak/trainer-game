extends Node3D
## Scena wyprawy: łączy źródło mocy (PowerSource), symulację (RunSimulation) i widoki.
## Kolejność w klatce: wejście -> moc -> zmiana pasa -> symulacja -> widoki -> HUD.
## Gra nie wie, skąd pochodzi moc – dostaje ją wyłącznie przez interfejs PowerSource.

enum State { RIDING, PAUSED, FINISHING, DONE }

const FINISH_DELAY_S := 2.5

@onready var track: TrackView = $Track
@onready var buggy: BuggyView = $Buggy
@onready var camera: ChaseCamera = $Camera
@onready var hud: Hud = $Hud
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var sun: DirectionalLight3D = $Sun

var sim: RunSimulation
var power: PowerSource
var lane_input := LaneInput.new()
var autopilot: Autopilot = null

var _state := State.RIDING
var _finish_left := 0.0
var _saved := false
var _had_pad := false
var _last_minute_shown := false
var _shots_done: Dictionary = {}


func _ready() -> void:
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.35, -0.75, -0.55), Vector3.UP)
	power = PowerSourceFactory.create(App.power_source_kind())
	if App.options.autopilot:
		autopilot = Autopilot.new()
	sim = RunSimulation.new(App.run_duration_s(), App.run_seed())
	sim.wreck_hit.connect(_on_wreck_hit)
	sim.scrap_collected.connect(_on_scrap_collected)
	pause_menu.resume_requested.connect(_resume)
	pause_menu.end_requested.connect(_end_early)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_had_pad = not Input.get_connected_joypads().is_empty()
	App.active_run = self
	if autopilot == null:
		hud.set_persistent_message("Wciśnij RT albo W, żeby ruszyć")
	_update_views(0.0, 0.0)


func _process(delta: float) -> void:
	match _state:
		State.RIDING:
			_ride(delta)
		State.FINISHING:
			_finish_left -= delta
			_update_views(delta, 0.0)
			if _finish_left <= 0.0:
				_commit(true)


func _ride(delta: float) -> void:
	if Input.is_action_just_pressed(&"pause"):
		_pause("")
		return
	power.update(delta)
	for notice in power.take_notices():
		hud.show_message(notice, 5.0)
	if power.get_status() != PowerSource.Status.ACTIVE:
		_pause("Źródło mocy: brak połączenia")
		return
	var dir := 0
	if autopilot != null:
		dir = autopilot.decide(sim, delta)
	else:
		dir = lane_input.update(delta, Input.get_action_raw_strength(&"lane_left"), Input.get_action_raw_strength(&"lane_right"))
	if dir != 0:
		sim.request_lane_change(dir)
	var p := power.get_power_watts()
	sim.step(delta, p)
	_update_views(delta, p)
	if sim.vehicle.speed_mps > 1.5:
		hud.set_persistent_message("")
	var e := sim.expedition
	if not _last_minute_shown and e.duration_s >= 120.0 and e.time_left_s() <= 60.0:
		_last_minute_shown = true
		hud.show_message("OSTATNIA MINUTA", 3.0)
	_maybe_screenshot()
	if e.finished:
		_state = State.FINISHING
		_finish_left = FINISH_DELAY_S
		hud.show_message("META!  +%d złomu" % e.scrap, FINISH_DELAY_S + 1.0)


func _update_views(delta: float, power_w: float) -> void:
	track.sync(sim, delta)
	buggy.sync(sim, power.get_cadence(), power_w, delta)
	camera.follow(sim.lanes.x_m, sim.vehicle.speed_mps, delta)
	hud.update_from(sim, power, delta)


# --- Pauza i koniec ----------------------------------------------------------

func _pause(reason: String) -> void:
	if _state != State.RIDING:
		return
	_state = State.PAUSED
	get_tree().paused = true
	pause_menu.open(reason)


func _resume() -> void:
	pause_menu.close()
	get_tree().paused = false
	_state = State.RIDING


func _end_early() -> void:
	pause_menu.close()
	get_tree().paused = false
	_commit(false)


func _commit(completed: bool) -> void:
	if _saved:
		return
	_saved = true
	_state = State.DONE
	App.finish_run(sim.expedition.to_summary(completed and sim.expedition.finished))


## Wywoływane przez App przy zamknięciu okna w trakcie jazdy – złom nie przepada.
func save_partial_run() -> void:
	if _saved:
		return
	_saved = true
	App.progress.record_run(sim.expedition.to_summary(false))
	App.progress.save_data()


# --- Zdarzenia -----------------------------------------------------------------

func _on_wreck_hit(_item: TrackItem, lost: int) -> void:
	buggy.on_hit()
	camera.shake(1.0)
	hud.flash_hit(lost)


func _on_scrap_collected(_item: TrackItem) -> void:
	hud.pulse_scrap()


func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	if connected:
		_had_pad = true
		return
	if _had_pad and power is GamepadPowerSource and Input.get_connected_joypads().is_empty():
		_pause("Pad rozłączony – połącz go i wciśnij Start / Esc")


# --- Zrzuty ekranu do testów wizualnych ----------------------------------------

func _maybe_screenshot() -> void:
	var dir := App.options.screenshot_dir
	if dir == "" or App.is_headless():
		return
	for t in App.options.shot_times:
		if sim.expedition.elapsed_s >= t and not _shots_done.has(t):
			_shots_done[t] = true
			Screenshot.capture(self, "%s/run_%03ds.png" % [dir, roundi(t)])
