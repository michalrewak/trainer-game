extends Node3D
## Scena wyprawy: łączy źródło mocy (PowerSource), symulację (RunSimulation) i widoki.
## Kolejność w klatce: wejście -> moc -> zmiana pasa -> symulacja -> widoki -> HUD.
## Gra nie wie, skąd pochodzi moc – dostaje ją wyłącznie przez interfejs PowerSource.

enum State { RIDING, PAUSED, FINISHING, DONE }

const FINISH_DELAY_S := 2.5

@onready var track: TrackView = $Track
@onready var buggy: BuggyView = $Buggy
@onready var combat_view: CombatView = $Combat
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
	_setup_combat()
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
	sim.combat.aim = Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")
	sim.combat.fire_held = Input.is_action_pressed(&"fire")
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
	combat_view.sync(sim, delta)
	var target := sim.combat.current_target()
	var target_local: Variant = null
	if target != null:
		target_local = Vector3(target.x, 0.0, -(target.d - sim.vehicle.distance_m))
	buggy.update_combat(target_local, sim.combat.shield, delta)
	camera.follow(sim.lanes.x_m, sim.vehicle.speed_mps, delta)
	hud.update_from(sim, power, delta)
	hud.update_combat(sim.combat, power_w, sim.lanes.x_m, delta)


# --- Walka (etap 2) ------------------------------------------------------------

func _setup_combat() -> void:
	var c := sim.combat
	c.target_power_w = App.free_ride_target_w()
	c.auto_fire = App.auto_fire_enabled() or autopilot != null
	c.enabled = not App.options.no_combat
	if App.options.combat_test:
		c.set_first_encounter(6.0)
	c.raider_warning.connect(_on_raider_warning)
	c.ram_resolved.connect(_on_ram_resolved)
	c.raider_destroyed.connect(_on_raider_destroyed)
	c.shot_fired.connect(func(_p: Dictionary) -> void: buggy.muzzle_flash())


func _on_raider_warning(r: RaiderModel) -> void:
	hud.show_message("ATAK Z %s!" % ("LEWEJ" if r.side < 0 else "PRAWEJ"), 1.2)


func _on_ram_resolved(_r: RaiderModel, outcome: int, lost: int) -> void:
	match outcome:
		CombatModel.RamOutcome.HIT:
			buggy.on_hit()
			camera.shake(1.2)
			hud.show_popup("RABUNEK! -%d ZŁOMU" % lost if lost > 0 else "ZEPCHNIĘTY!", Palette.UI_BAD)
		CombatModel.RamOutcome.BLOCKED:
			buggy.shield_block()
			camera.shake(0.5)
			hud.show_popup("TARCZA ZATRZYMAŁA ATAK", Palette.UI_SCRAP)
		CombatModel.RamOutcome.DODGED:
			hud.show_popup("UNIK!", Palette.UI_GOOD)
		CombatModel.RamOutcome.COUNTER:
			camera.shake(0.4)
			hud.show_popup("ODEPCHNIĘTY!", Palette.UI_GOOD)


func _on_raider_destroyed(r: RaiderModel, dropped: int, cause: int) -> void:
	combat_view.explode_at(Vector3(r.x, 0.0, -(r.d - sim.vehicle.distance_m)))
	camera.shake(0.35)
	if cause == CombatModel.DestroyCause.WRECK:
		hud.show_popup("ROZBIŁ SIĘ O WRAK! +%d" % dropped, Palette.UI_GOOD)
	else:
		hud.show_popup("GANG ROZBITY! +%d ZŁOMU NA DRODZE" % dropped, Palette.UI_GOOD)


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
