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

var raid_view: RaidView
var _loadout: Loadout
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
var _checkpoint_t := 0.0


func _ready() -> void:
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.35, -0.75, -0.55), Vector3.UP)
	power = PowerSourceFactory.create(App.power_source_kind(), App.bridge_url())
	if App.options.autopilot:
		autopilot = Autopilot.new()
	sim = RunSimulation.new(App.run_duration_s(), App.run_seed())
	sim.expedition.metrics.ftp_w = App.ftp_w()
	hud.ftp_w = App.ftp_w()
	# Etap 3: moduły z garażu i teren wyprawy.
	var loadout := App.run_loadout()
	loadout.apply_to(sim)
	TerrainCatalog.apply_to(App.selected_terrain, sim)
	track.theme = App.selected_terrain
	# Wzniesienia i doliny – w mieście łagodniej.
	sim.course_enabled = true
	sim.course.amplitude = 0.5 if App.selected_terrain == TerrainCatalog.CITY else 1.0
	sim.course.curve_amplitude = 0.6 if App.selected_terrain == TerrainCatalog.CITY else 1.0
	RenderingServer.global_shader_parameter_set(&"hill_phase", sim.course.hill_phases())
	RenderingServer.global_shader_parameter_set(&"curve_phase", sim.course.curve_phases())
	RenderingServer.global_shader_parameter_set(&"hill_amp", sim.course.amplitude)
	RenderingServer.global_shader_parameter_set(&"curve_amp", sim.course.curve_amplitude)
	RenderingServer.global_shader_parameter_set(&"track_d", 0.0)
	RenderingServer.global_shader_parameter_set(&"climb_slope", 0.0)
	RenderingServer.global_shader_parameter_set(&"bend_on", 1.0)
	buggy.apply_loadout(loadout)
	_loadout = loadout
	camera.extra_back = BuggyView.tail_length(loadout)
	raid_view = RaidView.new()
	add_child(raid_view)
	_apply_terrain_look(App.selected_terrain)
	weather.setup($WorldEnvironment, sun)
	weather.attach_headlights(buggy)
	weather.set_time(_time_of_day(), true)
	if App.time_mode() == "storm":
		weather.set_storm(1.0)
	sim.wreck_hit.connect(_on_wreck_hit)
	sim.scrap_collected.connect(_on_scrap_collected)
	sim.wreck_rammed.connect(func(item: TrackItem) -> void:
		combat_view.explode_at(Vector3(sim.lane_x(item.lane), 0.0, -(item.distance_m - sim.vehicle.distance_m)))
		camera.shake(0.6)
		hud.show_popup("TARAN!", Palette.UI_GOOD, 1.0))
	sim.fuel_collected.connect(func(_item: TrackItem) -> void: hud.show_popup("+1 PALIWO", Color("ff8a4a"), 1.0))
	_setup_combat()
	_setup_challenges()
	_setup_workout()
	_setup_raids()
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
			# Na mecie pojazd wytacza się bez mocy (zamiast „zamarzać”).
			sim.vehicle.step(delta, 0.0)
			_update_views(delta, 0.0)
			if _finish_left <= 0.0:
				_commit(true)


## Pora dnia: 0 = dzień, 0.5 = zmierzch, 1 = noc. W trybie „zmienna” wyprawa zaczyna się
## za dnia, w połowie zachodzi słońce, a końcówka jest nocna.
func _time_of_day() -> float:
	match App.time_mode():
		"day", "storm":
			return 0.0
		"dusk":
			return 0.5
		"night":
			return 1.0
	var p := sim.expedition.progress()
	if p < 0.3:
		return 0.0
	if p < 0.55:
		return (p - 0.3) / 0.25 * 0.5
	if p < 0.8:
		return 0.5 + (p - 0.55) / 0.25 * 0.5
	return 1.0


func _exit_tree() -> void:
	# Menu i garaż rysujemy bez wyginania świata.
	RenderingServer.global_shader_parameter_set(&"bend_on", 0.0)


## Pauza przez zdarzenie (nie odpytywanie w _process): to samo wciśnięcie, które wznawia
## grę w menu pauzy, nie może jej od razu znowu zapauzować.
func _unhandled_input(event: InputEvent) -> void:
	if _state == State.RIDING and event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		_pause("")


func _ride(delta: float) -> void:
	power.update(delta)
	for notice in power.take_notices():
		hud.show_message(notice, 5.0)
	match power.get_status():
		PowerSource.Status.CONNECTING:
			# Czekamy na trenażer – czas wyprawy stoi, nic nie przepada.
			hud.set_persistent_message("Łączenie z trenażerem: %s\n(uruchom mostek bridge/; port zajęty? --bridge-port=8766)" % App.bridge_url())
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
	elif sim.challenges.is_active() or sim.raids.is_raiding():
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
	# Checkpoint co 60 s: po awarii (np. utrata GPU) złom z wyprawy nie przepada.
	_checkpoint_t += delta
	if _checkpoint_t >= 60.0:
		_checkpoint_t = 0.0
		App.write_checkpoint(_summary(false))
	if e.finished:
		_state = State.FINISHING
		_finish_left = FINISH_DELAY_S
		hud.show_message("META!  +%d złomu" % e.scrap, FINISH_DELAY_S + 1.0)


func _update_views(delta: float, power_w: float) -> void:
	track.sync(sim, delta)
	buggy.sync(sim, power.get_cadence(), power_w, delta)
	combat_view.sync(sim, delta)
	raid_view.sync(sim, delta)
	var aim_at: Variant = sim.combat.aim_point()
	var target_local: Variant = null
	if aim_at is Vector2:
		target_local = Vector3(sim.lanes.x_m + (aim_at as Vector2).x, 0.0, -(aim_at as Vector2).y)
	buggy.update_combat(target_local, sim.combat.shield, delta)
	buggy.set_aim_line(sim.combat.is_aiming())
	# Zakręty i wzniesienia rysuje shader (bend.gdshaderinc) – podajemy mu dystans pojazdu.
	# Podjazd z wyzwania to dodatkowe nachylenie, wizualnie przesadzone jak reszta wzniesień.
	var climb := sim.challenges.grade_percent() / 100.0 * 2.5 if sim.challenges.enabled else 0.0
	_tilt = lerpf(_tilt, climb, 1.0 - exp(-delta * 1.5))
	weather.set_time(_time_of_day())
	RenderingServer.global_shader_parameter_set(&"track_d", sim.vehicle.distance_m)
	RenderingServer.global_shader_parameter_set(&"climb_slope", _tilt)
	camera.follow(sim.lanes.x_m, sim.vehicle.speed_mps, delta)
	hud.update_from(sim, power, delta)
	hud.update_combat(sim.combat, power_w, sim.lanes.x_m, delta)


## Moc docelowa w tej chwili: krok planu, wyzwanie trybu wolnego albo spokojne tempo (65% FTP).
func _current_target_w() -> float:
	if workout != null:
		var w := workout.target_w(sim.expedition.elapsed_s)
		return w if w > 0.0 else App.free_ride_target_w()
	if sim.raids.is_raiding():
		return sim.raids.target_w()
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
	if sim.raids.is_raiding() or (sim.challenges.is_active() and float(sim.challenges.current.get("grade", 0.0)) <= 0.0):
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
	weather.set_storm(0.85 if hard or App.time_mode() == "storm" else 0.0)
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


# --- Napady na osady: zwiad, zjazd, brama, łup ---------------------------------

func _setup_raids() -> void:
	var r := sim.raids
	r.enabled = workout == null and not App.options.no_raids
	r.ftp_w = App.ftp_w()
	if App.options.raid_test:
		r.set_first_fork(RaidDirector.SCOUT_M + 120.0)
		if autopilot != null:
			autopilot.take_raids = true
	r.scouted.connect(func(s: Dictionary) -> void:
		hud.show_message("ZWIAD: %s" % str(s["name"]), 2.5))
	r.started.connect(_on_raid_started)
	r.shell_landed.connect(_on_shell_landed)
	r.gate_broken.connect(_on_gate_broken)
	r.looting_started.connect(func(_s: Dictionary) -> void:
		hud.show_message("PLĄDRUJ!\nZbieraj, ile zdążysz", 2.5))
	r.escape_started.connect(_on_escape_started)
	r.loot_spilled.connect(func(lost: int) -> void:
		hud.show_popup("ŁADUNEK SIĘ SYPIE: -%d" % lost, Palette.UI_BAD))
	r.finished.connect(_on_raid_finished)


func _on_raid_started(s: Dictionary) -> void:
	power.set_erg_target(sim.raids.target_w())
	# Za bramą trasa zmienia się w ruiny osady.
	track.town_from = sim.raids.gate_d
	track.town_to = sim.raids.gate_d + float(s["duration_s"]) * 11.0
	hud.show_message("NAPAD: %s\nPodjazd pod ostrzałem – rozbij bramę" % str(s["name"]).to_upper(), 3.0)


func _on_shell_landed(shell: Dictionary, hit: bool, blocked: bool, lost: int) -> void:
	combat_view.explode_at(Vector3(sim.lane_x(int(shell["lane"])), 0.0, -(float(shell["d"]) - sim.vehicle.distance_m)))
	if not hit:
		return
	if blocked:
		buggy.shield_block()
		camera.shake(0.5)
		hud.show_popup("TARCZA ZATRZYMAŁA POCISK", Palette.UI_SCRAP)
	else:
		buggy.on_hit()
		camera.shake(1.2)
		hud.show_popup("TRAFIONY! -%d ZŁOMU" % lost if lost > 0 else "TRAFIONY!", Palette.UI_BAD)


func _on_gate_broken(how: int) -> void:
	for gx: float in [-3.5, 0.0, 3.5]:
		combat_view.explode_at(Vector3(gx, 0.0, -(sim.raids.gate_d - sim.vehicle.distance_m)))
	camera.shake(1.0)
	match how:
		RaidDirector.GateBreak.SHOT:
			hud.show_popup("BRAMA ROZBITA! +10% ŁUPU", Palette.UI_GOOD, 2.0)
		RaidDirector.GateBreak.RAM:
			hud.show_popup("TARAN WYWAŻYŁ BRAMĘ", Palette.UI_GOOD, 2.0)
		_:
			hud.show_popup("WYŁOM NA SIŁĘ – TRACISZ ROZPĘD", Palette.UI_ACCENT, 2.0)


func _on_escape_started(_s: Dictionary, scrap: int, fuel: int) -> void:
	power.set_erg_target(0.0)
	buggy.set_loot_wagon(true)
	camera.extra_back = BuggyView.tail_length(_loadout, true)
	var cargo := "%d złomu" % scrap + (" i %d paliwa" % fuel if fuel > 0 else "")
	hud.show_message("DOWIEŹ ŁUP!\n%s na przyczepie" % cargo, 3.0)


func _on_raid_finished(_s: Dictionary, scrap: int, fuel: int, repelled: bool) -> void:
	power.set_erg_target(0.0)
	buggy.set_loot_wagon(false)
	camera.extra_back = BuggyView.tail_length(_loadout)
	if repelled:
		hud.show_message("ODPARCI – osada się obroniła", 3.0)
	else:
		hud.show_message("ŁUP DOWIEZIONY: +%d złomu%s" % [scrap, ", +%d paliwa" % fuel if fuel > 0 else ""], 3.5)


## Karta zwiadu i stan napadu w HUD. Zwraca true, gdy napad zajmuje linię statusu.
func _update_raid_hud() -> bool:
	var r := sim.raids
	match r.state:
		RaidDirector.State.SCOUTING:
			var s := r.current
			var side := int(s["side"])
			var loot := "%s  ~%d złomu" % ["★".repeat(int(s["stars"])) + "☆".repeat(3 - int(s["stars"])), int(s["loot_scrap"])]
			if int(s["loot_fuel"]) > 0:
				loot += ", %d paliwa" % int(s["loot_fuel"])
			var defense := "%d %s, brama" % [int(s["towers"]), "wieża" if int(s["towers"]) == 1 else "wieże"]
			if int(s["guards"]) > 0:
				defense += ", %d wozy straży" % int(s["guards"])
			var effort := "%s na %d W (%d%% FTP)" % [UiStyle.clock(float(s["duration_s"])), roundi(r.target_w()), roundi(float(s["ftp"]) * 100.0)]
			var title := "%s  %s  %d m" % ["◀" if side < 0 else "", str(s["name"]).to_upper(), roundi(r.distance_to_next_m())] + ("  ▶" if side > 0 else "")
			var how := "Zjedź na %s pas, żeby napaść" % ("LEWY" if side < 0 else "PRAWY")
			hud.update_scout(true, side, title, "Łup: %s\nObrona: %s\nWysiłek: %s\n%s" % [loot, defense, effort, how])
			hud.update_challenge("", Palette.UI_TEXT)
			return true
		RaidDirector.State.RAIDING:
			hud.update_scout(false)
			var ratio := r.hold_ratio()
			var col := Palette.UI_GOOD if ratio >= 0.8 else Palette.UI_ACCENT
			var what := "BRAMA %s  %d m" % ["■".repeat(r.gate_hp) + "□".repeat(r.gate_hp_max - r.gate_hp), roundi(r.distance_to_next_m())] if r.phase == RaidDirector.Phase.APPROACH else "PLĄDROWANIE"
			hud.update_challenge("%s · %s · %s · %d%%" % [what, UiStyle.clock(r.time_left_s()), TargetBand.range_text(r.target_w(), RaidDirector.BAND_TOL, RaidDirector.BAND_TOL), roundi(ratio * 100.0)], col)
			return true
		RaidDirector.State.ESCAPING:
			hud.update_scout(false)
			hud.update_challenge("DOWIEŹ ŁUP %s · %d złomu na przyczepie" % [UiStyle.clock(r.escape_left_s), r.pending_scrap], Palette.UI_SCRAP)
			return true
	hud.update_scout(false)
	return false


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
	weather.set_storm(1.0 if App.time_mode() == "storm" else 0.0)
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
	if _update_raid_hud():
		return
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
	c.wreck_destroyed.connect(func(item: TrackItem) -> void:
		combat_view.explode_at(Vector3(sim.lane_x(item.lane), 0.0, -(item.distance_m - sim.vehicle.distance_m)))
		hud.show_popup("WRAK ROZBITY", Palette.UI_GOOD, 1.0))


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
	hud.visible = false
	pause_menu.open(reason)


func _resume() -> void:
	pause_menu.close()
	hud.visible = true
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
	App.clear_checkpoint()
	App.finish_run(_summary(completed and sim.expedition.finished))


## Wywoływane przez App przy zamknięciu okna w trakcie jazdy – złom nie przepada.
func save_partial_run() -> void:
	if _saved:
		return
	_saved = true
	App.clear_checkpoint()
	App.progress.record_run(_summary(sim.expedition.finished))
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
