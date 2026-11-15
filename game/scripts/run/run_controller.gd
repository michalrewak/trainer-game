extends Node3D
## Scena wyprawy: łączy źródło mocy (PowerSource), symulację (RunSimulation) i widoki.
## Kolejność w klatce: wejście -> moc -> zmiana pasa -> symulacja -> widoki -> HUD.
## Gra nie wie, skąd pochodzi moc – dostaje ją wyłącznie przez interfejs PowerSource.

enum State { RIDING, PAUSED, FINISHING, DONE }

const FINISH_DELAY_S := 2.5

@onready var track: TrackView = $Track
@onready var buggy: BuggyView = $Buggy
@onready var combat_view: CombatView = $Combat
@onready var weather: WeatherFx = $Weather
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
var _tilt := 0.0


func _ready() -> void:
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.35, -0.75, -0.55), Vector3.UP)
	power = PowerSourceFactory.create(App.power_source_kind())
	if App.options.autopilot:
		autopilot = Autopilot.new()
	sim = RunSimulation.new(App.run_duration_s(), App.run_seed())
	# Etap 3: moduły z garażu i teren wyprawy.
	var loadout := App.run_loadout()
	loadout.apply_to(sim)
	TerrainCatalog.apply_to(App.selected_terrain, sim)
	track.theme = App.selected_terrain
	# Wzniesienia i doliny – w mieście łagodniej.
	sim.course_enabled = true
	sim.course.amplitude = 0.5 if App.selected_terrain == TerrainCatalog.CITY else 1.0
	buggy.apply_loadout(loadout)
	_apply_terrain_look(App.selected_terrain)
	weather.setup($WorldEnvironment, sun)
	sim.wreck_hit.connect(_on_wreck_hit)
	sim.scrap_collected.connect(_on_scrap_collected)
	sim.fuel_collected.connect(func(_item: TrackItem) -> void: hud.show_popup("+1 PALIWO", Color("ff8a4a"), 1.0))
	_setup_combat()
	_setup_challenges()
	_setup_workout()
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
	match power.get_status():
		PowerSource.Status.CONNECTING:
			# Czekamy na trenażer – czas wyprawy stoi, nic nie przepada.
			hud.set_persistent_message("Łączenie z trenażerem (mostek bridge/)…")
			_update_views(delta, 0.0)
			return
		PowerSource.Status.LOST:
			_pause("Trenażer rozłączony – mostek próbuje połączyć się ponownie")
			return
	var dir := 0
	if autopilot != null:
		dir = autopilot.decide(sim, delta)
	else:
		dir = lane_input.update(delta, Input.get_action_raw_strength(&"lane_left"), Input.get_action_raw_strength(&"lane_right"))
	if dir != 0:
		sim.request_lane_change(dir)
	sim.combat.aim = Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")
	# LT strzela zawsze; RT dodatkowo, gdy moc daje trenażer (RT nie jest wtedy „pedałem”).
	var rt_fires := not (power is GamepadPowerSource) and Input.get_action_raw_strength(&"power_trigger") > 0.3
	sim.combat.fire_held = Input.is_action_pressed(&"fire") or rt_fires
	var p := power.get_power_watts()
	sim.combat.target_power_w = _current_target_w()
	if workout != null:
		sim.combat.target_low_tol = TargetBand.WORKOUT_TOL
		sim.combat.target_high_tol = TargetBand.WORKOUT_TOL
	elif sim.challenges.is_active():
		sim.combat.target_low_tol = TargetBand.CHALLENGE_TOL
		sim.combat.target_high_tol = TargetBand.CHALLENGE_TOL
	else:
		sim.combat.target_low_tol = TargetBand.FREE_RIDE_LOW
		sim.combat.target_high_tol = TargetBand.FREE_RIDE_HIGH
	sim.step(delta, p)
	if workout != null:
		_tick_workout(delta, p)
	else:
		_send_terrain_grade()
	_update_views(delta, p)
	_update_challenge_hud()
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
	# Podjazd: świat przechyla się wokół pojazdu – droga przed nami „wznosi się”.
	_tilt = lerpf(_tilt, atan(sim.vehicle.grade) * 1.4, 1.0 - exp(-delta * 1.5))
	track.rotation.x = _tilt
	combat_view.rotation.x = _tilt
	buggy.rotation.x = _tilt
	camera.follow(sim.lanes.x_m, sim.vehicle.speed_mps, delta)
	hud.update_from(sim, power, delta)
	hud.update_combat(sim.combat, power_w, sim.lanes.x_m, delta)


## Moc docelowa w tej chwili: krok planu, wyzwanie trybu wolnego albo spokojne tempo (65% FTP).
func _current_target_w() -> float:
	if workout != null:
		var w := workout.target_w(sim.expedition.elapsed_s)
		return w if w > 0.0 else App.free_ride_target_w()
	if sim.challenges.is_active():
		return sim.challenges.target_w()
	return App.free_ride_target_w()


# --- Tryb treningowy (etap 4) --------------------------------------------------

var workout: WorkoutRunner = null
var _erg_refresh := 0.0
var _sent_grade := 999.0


## Jazda swobodna: trenażer czuje teren (tryb symulacji). Wysyłamy tylko zmiany >= 0,5%,
## a w trakcie wyzwań ERG – wcale (ERG ma pierwszeństwo). W treningu nigdy.
func _send_terrain_grade() -> void:
	if sim.challenges.is_active() and float(sim.challenges.current.get("grade", 0.0)) <= 0.0:
		return
	var g := snappedf(sim.vehicle.grade * 100.0, 0.5)
	if absf(g - _sent_grade) >= 0.5:
		_sent_grade = g
		power.set_grade(g)


func _setup_workout() -> void:
	var plan := App.selected_plan()
	if plan == null:
		return
	workout = WorkoutRunner.new(plan, App.ftp_w())
	sim.challenges.enabled = false
	hud.set_workout(workout.blocks(), plan.name)
	workout.step_changed.connect(_on_workout_step)


func _on_workout_step(index: int, step: WorkoutStep) -> void:
	var t := sim.expedition.elapsed_s
	var hard := workout.plan.is_hard_step(index)
	# Ciężki interwał = burza piaskowa i pole bezpieczne: tylko pedałujesz, bez klikania.
	sim.set_safe_zone(hard)
	weather.set_storm(0.85 if hard else 0.0)
	power.set_erg_target(workout.target_w(t))
	_erg_refresh = 0.0
	var title := "INTERWAŁ – BURZA PIASKOWA" if hard else step.display_label().to_upper()
	hud.show_message("%s\n%s · %s" % [title, TargetBand.range_text(workout.target_w(t), workout.tol, workout.tol), WorkoutStep.format_duration(step.duration_s)], 3.0)


func _tick_workout(delta: float, power_w: float) -> void:
	var t := sim.expedition.elapsed_s
	workout.step(t, delta, power_w)
	# Rampy (rozgrzewka/schłodzenie): odświeżamy cel ERG co 5 s.
	_erg_refresh += delta
	if _erg_refresh >= 5.0:
		_erg_refresh = 0.0
		var i := workout.plan.step_index_at(t)
		if i >= 0 and workout.plan.steps[i].is_ramp():
			power.set_erg_target(workout.target_w(t))
	var info := workout.info(t)
	info["safe"] = sim.safe_zone
	hud.update_workout(info)


# --- Tryb wolny: wyzwania (etap 6) ---------------------------------------------

func _setup_challenges() -> void:
	var ch := sim.challenges
	ch.enabled = not App.options.no_challenges
	ch.ftp_w = App.ftp_w()
	if App.options.challenge_test:
		ch.set_first_after(8.0)
	ch.announced.connect(func(c: Dictionary) -> void:
		hud.show_message("WYZWANIE: %s\n%s" % [str(c["name"]), str(c["brief"])], ChallengeDirector.ANNOUNCE_S))
	ch.started.connect(_on_challenge_started)
	ch.finished.connect(_on_challenge_finished)


## Gra dyktuje opór: podjazd = nachylenie (symulacja trenażera), reszta = ERG.
func _on_challenge_started(c: Dictionary) -> void:
	if float(c.get("grade", 0.0)) > 0.0:
		power.set_grade(float(c["grade"]))
		if not power.supports_resistance_control():
			power.set_erg_target(sim.challenges.target_w())
	else:
		power.set_erg_target(sim.challenges.target_w())
	if int(c.get("kind", -1)) == ChallengeDirector.Kind.ESCAPE:
		weather.set_storm(0.8)
	hud.show_message("%s: START!" % str(c["name"]), 1.5)


func _on_challenge_finished(c: Dictionary, success: bool) -> void:
	power.set_erg_target(0.0)
	power.set_grade(0.0)
	weather.set_storm(0.0)
	if success:
		var reward := "+%d złomu" % int(c.get("reward_scrap", 0))
		if int(c.get("reward_fuel", 0)) > 0:
			reward += ", +%d paliwa" % int(c["reward_fuel"])
		hud.show_message("%s ZALICZONY! %s" % [str(c["name"]), reward], 3.5)
	elif int(c.get("kind", -1)) == ChallengeDirector.Kind.ESCAPE:
		hud.show_message("Nie udało się uciec – gang dogania!", 3.5)
	else:
		hud.show_message("%s: tym razem się nie udało" % str(c["name"]), 3.0)


func _update_challenge_hud() -> void:
	var ch := sim.challenges
	match ch.phase:
		ChallengeDirector.Phase.ANNOUNCE:
			hud.update_challenge("%s za %d s · cel %d W" % [str(ch.current["name"]), ceili(ch.time_left_s()), roundi(ch.target_w())], Palette.UI_ACCENT)
		ChallengeDirector.Phase.ACTIVE:
			var ratio := ch.hold_ratio()
			var col := Palette.UI_GOOD if ratio >= ChallengeDirector.SUCCESS_RATIO else Palette.UI_BAD
			hud.update_challenge("%s %s · %s · %d%%" % [str(ch.current["name"]), UiStyle.clock(ch.time_left_s()), TargetBand.range_text(ch.target_w(), ChallengeDirector.BAND_TOL, ChallengeDirector.BAND_TOL), roundi(ratio * 100.0)], col)
		_:
			hud.update_challenge("", Palette.UI_TEXT)


## Martwe Miasto: szarobrązowa mgła i bledsze niebo (kopia zasobu – nie zmieniamy sceny).
func _apply_terrain_look(terrain_id: String) -> void:
	if terrain_id != TerrainCatalog.CITY:
		return
	var world := $WorldEnvironment as WorldEnvironment
	var env := world.environment.duplicate(true) as Environment
	env.fog_light_color = Color(0.64, 0.6, 0.54)
	env.fog_density = 0.006
	env.ambient_light_color = Color(0.72, 0.68, 0.62)
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
	if sky_mat != null:
		sky_mat.sky_top_color = Color(0.42, 0.48, 0.54)
		sky_mat.sky_horizon_color = Color(0.76, 0.7, 0.62)
		sky_mat.ground_horizon_color = Color(0.76, 0.7, 0.62)
	world.environment = env


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


func _summary(completed: bool) -> Dictionary:
	var s := sim.expedition.to_summary(completed)
	if workout != null:
		s["workout"] = workout.plan.name
		s["workout_in_band_pct"] = roundi(workout.compliance() * 100.0)
	return s


func _commit(completed: bool) -> void:
	if _saved:
		return
	_saved = true
	_state = State.DONE
	power.set_erg_target(0.0)
	App.finish_run(_summary(completed and sim.expedition.finished))


## Wywoływane przez App przy zamknięciu okna w trakcie jazdy – złom nie przepada.
func save_partial_run() -> void:
	if _saved:
		return
	_saved = true
	App.progress.record_run(_summary(false))
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
