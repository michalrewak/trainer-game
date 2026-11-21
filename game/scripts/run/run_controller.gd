extends Node3D
## Scena wyprawy: łączy źródło mocy (PowerSource), symulację (RunSimulation) i widoki.
## Kolejność w klatce: wejście -> moc -> zmiana pasa -> symulacja -> widoki -> HUD.
## Gra nie wie, skąd pochodzi moc – dostaje ją wyłącznie przez interfejs PowerSource.

enum State { RIDING, PAUSED, FINISHING, DONE }

## Po końcu czasu pojazd jeszcze chwilę wtacza się na plac osady.
const FINISH_DELAY_S := 3.2

@onready var track: TrackView = $Track
@onready var buggy: BuggyView = $Buggy
@onready var combat_view: CombatView = $Combat
@onready var weather: WeatherFx = $Weather

var raid_view: RaidView
var convoy_view: ConvoyView
var settlement_view: SettlementView
var sfx: Sfx
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
	sim.lanes.assist_enabled = App.steer_assist_enabled()
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
	convoy_view = ConvoyView.new()
	add_child(convoy_view)
	settlement_view = SettlementView.new()
	add_child(settlement_view)
	sfx = Sfx.new()
	sfx.enabled = App.sound_enabled() and not App.is_headless()
	add_child(sfx)
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
		sfx.play("boom", 1.2)
		hud.show_popup("TARAN!", Palette.UI_GOOD, 1.0))
	sim.fuel_collected.connect(func(_item: TrackItem) -> void:
		sfx.play("big")
		hud.show_popup("+1 PALIWO", Color("ff8a4a"), 1.0))
	_setup_combat()
	_setup_challenges()
	_setup_workout()
	_setup_raids()
	_setup_convoys()
	_setup_engagement()
	sim.combat.raider_spawned.connect(_on_raider_spawned)
	pause_menu.resume_requested.connect(_resume)
	pause_menu.end_requested.connect(_end_early)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_had_pad = not Input.get_connected_joypads().is_empty()
	App.active_run = self
	if autopilot == null:
		hud.set_persistent_message("Wciśnij RT albo W, żeby ruszyć")
	_update_views(0.0, 0.0)
	_say("start", 0)


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


## Gałka kierowania: strefa martwa i łagodny początek (precyzja przy małym wychyleniu).
static func steer_curve(raw: float) -> float:
	var a := absf(raw)
	if a < 0.18:
		return 0.0
	return signf(raw) * pow((a - 0.18) / 0.82, 1.4)


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
	var steer := 0.0
	if autopilot != null:
		dir = autopilot.decide(sim, delta)
	else:
		# Krzyżak i klawisze skaczą o pas; lewa gałka kieruje płynnie.
		dir = lane_input.update(delta, Input.get_action_raw_strength(&"lane_left"), Input.get_action_raw_strength(&"lane_right"))
		steer = steer_curve(Input.get_axis(&"steer_left", &"steer_right"))
	sim.steer(steer)
	if dir != 0:
		sim.request_lane_change(dir)
	sim.combat.aim = Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down")
	# LT strzela zawsze; RT dodatkowo, gdy moc daje trenażer (RT nie jest wtedy „pedałem”).
	var rt_fires := not (power is GamepadPowerSource) and Input.get_action_raw_strength(&"power_trigger") > 0.3
	sim.combat.fire_held = Input.is_action_pressed(&"fire") or rt_fires
	if Input.is_action_just_pressed(&"boost"):
		_fire_boost(true)
	elif autopilot != null and autopilot.wants_boost(sim):
		_fire_boost(false)
	if autopilot != null and sim.convoys.is_active():
		power.set_erg_target(autopilot.convoy_power_w(sim, App.ftp_w()))
	var p := power.get_power_watts()
	sim.combat.target_power_w = _current_target_w()
	if workout != null:
		sim.combat.target_low_tol = TargetBand.WORKOUT_TOL
		sim.combat.target_high_tol = TargetBand.WORKOUT_TOL
	elif sim.convoys.is_active():
		sim.combat.target_low_tol = sim.convoys.band_low()
		sim.combat.target_high_tol = sim.convoys.band_high()
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
	_tick_chatter(delta, p)
	_tick_records(delta)
	if sim.vehicle.speed_mps > 1.5:
		hud.set_persistent_message("")
	var e := sim.expedition
	if not _last_minute_shown and e.duration_s >= 120.0 and e.time_left_s() <= 60.0:
		_last_minute_shown = true
		hud.show_message("MINUTA DO OSADY", 3.0)
		_say("last_minute", 1)
	# Osada na horyzoncie: wyprawa kończy się wjazdem przez jej bramę.
	if sim.arrival.just_sighted:
		sfx.play("tier")
		hud.show_message("OSADA NA HORYZONCIE\nBrama otwarta – dowieź, co masz", 3.5)
		_say("home_sight", 2)
	_maybe_screenshot()
	# Checkpoint co 60 s: po awarii (np. utrata GPU) złom z wyprawy nie przepada.
	_checkpoint_t += delta
	if _checkpoint_t >= 60.0:
		_checkpoint_t = 0.0
		App.write_checkpoint(_summary(false))
	if e.finished:
		_state = State.FINISHING
		_finish_left = FINISH_DELAY_S
		hud.show_message("W OSADZIE!\n+%d złomu do magazynu" % e.scrap, FINISH_DELAY_S + 1.0)
		sfx.play("fanfare")
		_say("finish", 2)


func _update_views(delta: float, power_w: float) -> void:
	track.sync(sim, delta)
	buggy.sync(sim, power.get_cadence(), power_w, delta)
	combat_view.sync(sim, delta)
	raid_view.sync(sim, delta)
	convoy_view.sync(sim, delta)
	settlement_view.sync(sim, delta)
	buggy.set_boost(sim.power_train.is_boosting())
	var aim_at: Variant = sim.combat.aim_point()
	var target_local: Variant = null
	if aim_at is Vector2:
		target_local = Vector3(sim.lanes.x_m + (aim_at as Vector2).x, 0.0, -(aim_at as Vector2).y)
	buggy.update_combat(target_local, sim.combat.capacitor, delta)
	buggy.set_aim_line(sim.combat.is_aiming())
	# Zakręty i wzniesienia rysuje shader (bend.gdshaderinc) – podajemy mu dystans pojazdu.
	# Podjazd z wyzwania to dodatkowe nachylenie, wizualnie przesadzone jak reszta wzniesień.
	var climb := sim.challenges.grade_percent() / 100.0 * 2.5 if sim.challenges.enabled else 0.0
	_tilt = lerpf(_tilt, climb, 1.0 - exp(-delta * 1.5))
	weather.set_time(_time_of_day())
	RenderingServer.global_shader_parameter_set(&"track_d", sim.vehicle.distance_m)
	RenderingServer.global_shader_parameter_set(&"climb_slope", _tilt)
	# Przy konwoju kamera odsuwa się, żeby było widać całą kolumnę obok pojazdu.
	var want_back := BuggyView.tail_length(_loadout, sim.raids.is_towing())
	if sim.convoys.is_active() and sim.convoys.gap_m() < 45.0:
		want_back += 7.0
	camera.extra_back = lerpf(camera.extra_back, want_back, 1.0 - exp(-delta * 1.2))
	camera.follow(sim.lanes.x_m, sim.vehicle.speed_mps, delta)
	hud.update_from(sim, power, delta)
	hud.update_combat(sim.combat, power_w, sim.lanes.x_m, delta)


## Moc docelowa w tej chwili: krok planu, wyzwanie trybu wolnego albo spokojne tempo (65% FTP).
func _current_target_w() -> float:
	if workout != null:
		var w := workout.target_w(sim.expedition.elapsed_s)
		return w if w > 0.0 else App.free_ride_target_w()
	if sim.convoys.is_active():
		return sim.convoys.target_w()
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
		hud.show_message("ZWIAD: %s" % str(s["name"]), 2.5)
		_say("raid_scout", 1, 240.0))
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
	_say("raid_start", 1)


func _on_shell_landed(shell: Dictionary, hit: bool, blocked: bool, lost: int) -> void:
	combat_view.explode_at(Vector3(sim.lane_x(int(shell["lane"])), 0.0, -(float(shell["d"]) - sim.vehicle.distance_m)))
	if not hit:
		return
	if blocked:
		buggy.discharge()
		camera.shake(0.5)
		hud.show_popup("WYŁADOWANIE ZDETONOWAŁO POCISK", Palette.UI_SCRAP)
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
	var cargo := "%d złomu" % scrap + (" i %d paliwa" % fuel if fuel > 0 else "")
	hud.show_message("DOWIEŹ ŁUP!\n%s na przyczepie" % cargo, 3.0)


func _on_raid_finished(_s: Dictionary, scrap: int, fuel: int, repelled: bool) -> void:
	power.set_erg_target(0.0)
	buggy.set_loot_wagon(false)
	if repelled:
		hud.show_message("ODPARCI – osada się obroniła", 3.0)
	else:
		hud.show_message("ŁUP DOWIEZIONY: +%d złomu%s" % [scrap, ", +%d paliwa" % fuel if fuel > 0 else ""], 3.5)
		_say("raid_done", 1)


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


# --- Konwoje Tłustych: pościg, odcinanie sprzęgów, przesiadka --------------------

func _setup_convoys() -> void:
	var c := sim.convoys
	c.enabled = workout == null and not App.options.no_convoys and sim.combat.enabled
	c.ftp_w = App.ftp_w()
	if App.options.convoy_test:
		# Test konwoju: od razu, bez zwiadów i wyzwań w tle.
		c.set_first_at(5.0)
		sim.raids.enabled = false
		sim.challenges.enabled = false
	c.sighted.connect(func(info: Dictionary) -> void:
		hud.show_message("KONWÓJ: %s\nDogoń go – jedź mocniej niż %d W" % [str(info["name"]).to_upper(), roundi(c.hold_power_w())], 3.5)
		_say("convoy_sighted", 2))
	c.engaged.connect(func(_info: Dictionary) -> void:
		hud.show_message("ODCZEP GALERĘ!\nBoczny pas, zrównaj się ze sprzęgiem i strzelaj w sworzeń", 4.0)
		_say("convoy_engaged", 2)
		_say("convoy_hint", 1))
	c.pace_warning.connect(func(fast: bool) -> void:
		sfx.play("warn", 1.2 if fast else 0.8)
		_say("pace_fast" if fast else "pace_slow", 1))
	c.pace_changed.connect(func(fast: bool) -> void:
		if fast:
			hud.show_popup("KONWÓJ UCIEKA – DOCIŚNIJ!", Palette.UI_ACCENT, 1.8)
		else:
			hud.show_popup("KONWÓJ HAMUJE – ODPUŚĆ!", Palette.UI_SCRAP, 1.8))
	c.hitch_broken.connect(func(front: bool) -> void:
		camera.shake(0.9)
		hud.show_popup("PRZEDNI SPRZĘG PUŚCIŁ!" if front else "TYLNY SPRZĘG PUŚCIŁ – OGON ODPADA!", Palette.UI_GOOD, 2.2)
		_say("hitch_front" if front else "hitch_rear", 2))
	c.guard_lost.connect(func(destroyed: bool) -> void:
		if destroyed:
			camera.shake(1.0)
			hud.show_popup("OGON ROZBITY!", Palette.UI_GOOD, 2.0)
			_say("guard_destroyed", 2))
	c.tractor_destroyed.connect(func() -> void:
		camera.shake(1.6)
		hud.show_popup("CIĄGNIK BARONA ROZBITY! ŁUP ×1,5", Palette.UI_GOOD, 2.6)
		_say("tractor_destroyed", 2))
	c.cage_hit.connect(func(left: int) -> void:
		hud.show_popup("TRAFIASZ W KLATKĘ! Uwolnisz już tylko %d" % left, Palette.UI_BAD, 2.0)
		_say("cage_hit", 2, 8.0))
	c.mine_dropped.connect(func(_m: Dictionary) -> void: _say("mine", 0, 40.0))
	c.mine_exploded.connect(_on_mine_exploded)
	c.bumped.connect(func(squeezed: bool) -> void:
		buggy.on_hit()
		camera.shake(1.0)
		hud.show_popup("ZGNIECIONY MIĘDZY WAGONAMI!" if squeezed else "ZDERZENIE Z KONWOJEM!", Palette.UI_BAD)
		_say("bump", 1, 30.0))
	c.capture_started.connect(func(_jackpot: bool) -> void:
		hud.show_message("PRZESIADKA!\nZwolnij poniżej %d km/h i trzymaj się galery" % roundi(ConvoyDirector.BOARD_MAX_SPEED * 3.6), 4.0)
		_say("capture", 2))
	c.finished.connect(_on_convoy_finished)


func _on_mine_exploded(mine: Dictionary, hit: bool, blocked: bool, lost: int) -> void:
	sfx.play("boom", 1.1, -3.0)
	combat_view.explode_at(Vector3(sim.lane_x(int(mine["lane"])), 0.0, -(float(mine["d"]) - sim.vehicle.distance_m)))
	if not hit:
		return
	if blocked:
		buggy.discharge()
		camera.shake(0.5)
		hud.show_popup("WYŁADOWANIE ZDETONOWAŁO MINĘ", Palette.UI_SCRAP)
	else:
		buggy.on_hit()
		camera.shake(1.2)
		hud.show_popup("MINA! -%d ZŁOMU" % lost if lost > 0 else "MINA!", Palette.UI_BAD)


func _on_convoy_finished(_info: Dictionary, result: Dictionary) -> void:
	if autopilot != null:
		power.set_erg_target(0.0)
	hud.update_convoy({})
	match int(result["outcome"]):
		ConvoyDirector.Outcome.CAPTURED:
			var extra := ""
			if bool(result.get("jackpot", false)):
				extra = "  ·  ŁUP ×1,5"
			elif bool(result.get("clean", false)):
				extra = "  ·  CZYSTE CIĘCIE"
			elif bool(result.get("guard_hangs", false)):
				extra = "  ·  ogon zabrał 30% łupu"
			hud.show_message("GALERA PRZEJĘTA!%s\n+%d złomu  ·  +%d paliwa  ·  +%d do załogi" % [extra, int(result["scrap"]), int(result["fuel"]), int(result["freed"])], 5.0)
			camera.shake(0.6)
			sfx.play("fanfare")
			_say("captured_clean" if bool(result.get("clean", false)) else "captured", 2)
		ConvoyDirector.Outcome.PARTIAL:
			hud.show_message("WAGON ZOSTAŁ W TYLE\nZgarnąłeś tylko resztki: +%d złomu" % int(result["scrap"]), 4.0)
			_say("partial", 2)
		ConvoyDirector.Outcome.OUTRUN:
			hud.show_message("KONWÓJ UCIEKŁ\nZa mało mocy na kołach", 3.5)
			_say("outrun", 2)
		ConvoyDirector.Outcome.PASSED:
			hud.show_message("ZGUBIŁEŚ KONWÓJ\nWyprzedziłeś go za daleko", 3.5)
			_say("passed", 2)
		ConvoyDirector.Outcome.FORTRESS:
			hud.show_message("KONWÓJ DOJECHAŁ DO TWIERDZY", 3.5)
			_say("fortress", 2)


## Panel konwoju: schemat kolumny, pozycja gracza i polecenie „przyspiesz / zwolnij”.
## Zwraca true, gdy konwój zajmuje linię statusu.
func _update_convoy_hud() -> bool:
	var c := sim.convoys
	if not c.is_active() or c.galley == null:
		hud.update_convoy({})
		return false
	var hold := roundi(c.hold_power_w())
	var rel := c.rel_m()
	var beside := absf(sim.lanes.x_m - c.galley.x) > 1.8
	var status := ""
	var line := ""
	var col := Palette.UI_ACCENT
	match c.state:
		ConvoyDirector.State.CHASE:
			status = "POŚCIG: %d m do konwoju. Jedź powyżej %d W" % [roundi(c.gap_m()), hold]
			line = "KONWÓJ %d m · jego tempo to %d W" % [roundi(c.gap_m()), hold]
		ConvoyDirector.State.ENGAGED:
			var pace := "UCIEKA jeszcze %d s – trzymaj %d W" % [ceili(c.pace_left_s()), hold] if c.pace_fast else "HAMUJE jeszcze %d s – odpuść do %d W" % [ceili(c.pace_left_s()), hold]
			col = Palette.UI_ACCENT if c.pace_fast else Palette.UI_SCRAP
			status = "%s\n%s" % [_convoy_order(c, rel, beside), pace]
			line = "KONWÓJ %s · tempo %d W · %d s" % ["UCIEKA" if c.pace_fast else "HAMUJE", hold, ceili(c.pace_left_s())]
		ConvoyDirector.State.CAPTURE:
			col = Palette.UI_GOOD
			var kmh := roundi(sim.vehicle.speed_kmh())
			var limit := roundi(ConvoyDirector.BOARD_MAX_SPEED * 3.6)
			if kmh > limit:
				status = "PRZESIADKA: ZWOLNIJ! Masz %d km/h, trzeba poniżej %d" % [kmh, limit]
			elif rel < ConvoyDirector.BOARD_BEHIND_M or rel > ConvoyDirector.BOARD_AHEAD_M:
				status = "PRZESIADKA: %s do galery (%d m)" % ["podjedź" if rel < 0.0 else "poczekaj, wróć", roundi(absf(rel))]
			else:
				status = "PRZESIADKA %d%% – trzymaj się wagonu" % roundi(c.board_ratio() * 100.0)
			line = "PRZESIADKA %d%% · poniżej %d km/h" % [roundi(c.board_ratio() * 100.0), limit]
	var title := "%s  ·  w klatce: %d" % [str(c.info["name"]).to_upper(), c.freed_now()]
	if c.state == ConvoyDirector.State.ENGAGED:
		title += "  ·  do twierdzy %s" % UiStyle.clock(c.time_to_fortress_s())
	hud.update_convoy({
		"title": title, "status": status, "color": col, "rel": rel, "beside": beside,
		"has_guard": c.guard_attached, "has_tractor": c.tractor_attached and c.tractor.is_alive(),
		"hitch_rear": c.hitch_rear.is_alive(), "hitch_front": c.hitch_front.is_alive(),
		"guard_hp": float(c.guard.hp) / c.guard.max_hp, "tractor_hp": float(c.tractor.hp) / c.tractor.max_hp,
		"hitch_rear_hp": float(c.hitch_rear.hp) / c.hitch_rear.max_hp, "hitch_front_hp": float(c.hitch_front.hp) / c.hitch_front.max_hp,
		"window": c.open_window(), "board": c.board_ratio() if c.state == ConvoyDirector.State.CAPTURE else -1.0,
	})
	hud.update_challenge(line, col)
	if c.open_window() != 0 and _window_seen != c.open_window():
		_window_seen = c.open_window()
		_say("window", 1, 20.0)
	return true


## Polecenie taktyczne: gdzie jest najbliższy sprzęg i czy trzeba przyspieszyć, czy zwolnić.
func _convoy_order(c: ConvoyDirector, rel: float, beside: bool) -> String:
	match c.open_window():
		1:
			return "STRZELAJ W TYLNY SPRZĘG!"
		2:
			return "STRZELAJ W PRZEDNI SPRZĘG!"
	var hitch_at := ConvoyDirector.HITCH_REAR_OFFSET_M if c.guard_attached else ConvoyDirector.HITCH_FRONT_OFFSET_M
	var which := "tylnego" if c.guard_attached else "przedniego"
	# Ile brakuje do okna (dodatnie) albo o ile je przejechałeś (ujemne).
	var short := (hitch_at - ConvoyDirector.WINDOW_BACK_M) - rel
	var past := rel - (hitch_at + ConvoyDirector.WINDOW_FRONT_M)
	if not beside:
		return "Zjedź na boczny pas! Okno %s sprzęgu za %d m" % [which, maxi(0, roundi(short))]
	if short > 0.0:
		return "PRZYSPIESZ: %d m do okna %s sprzęgu" % [ceili(short), which]
	return "ZWOLNIJ: minąłeś okno o %d m" % ceili(past)


# --- To, co ma wciągać: passa, zlecenia, skrzynie, uniki, rekordy ---------------

var _record_checked: Dictionary = {}
var _record_t := 0.0


func _setup_engagement() -> void:
	sim.contracts.setup(sim.expedition.duration_s / 60.0, App.ftp_w(), App.run_seed(), {
		"combat": sim.combat.enabled, "convoys": sim.convoys.enabled and not App.options.convoy_test,
		"raids": sim.raids.enabled, "workout": workout != null,
	})
	sim.contracts.completed.connect(func(c: Dictionary) -> void:
		sfx.play("fanfare")
		var reward := "+%d złomu" % int(c["reward_scrap"]) + (", +%d paliwa" % int(c["reward_fuel"]) if int(c["reward_fuel"]) > 0 else "")
		hud.show_message("ZLECENIE WYKONANE\n%s  ·  %s" % [str(c["text"]), reward], 3.5)
		_say("contract", 1))
	sim.contracts.all_completed.connect(func() -> void:
		hud.show_popup("KOMPLET ZLECEŃ! +%d PALIWA" % ContractBoard.ALL_DONE_FUEL, Palette.UI_GOOD, 2.5))
	sim.streak.tier_changed.connect(func(tier: int, up: bool) -> void:
		if up:
			sfx.play("tier", 1.0 + 0.08 * tier)
			hud.pulse_streak()
			hud.show_popup("PASSA ×%.1f" % Streak.tier_multiplier(tier), Palette.UI_ACCENT, 1.2)
			if tier >= 3:
				_say("streak", 0, 90.0))
	sim.streak.broken.connect(func(_points: int) -> void:
		sfx.play("lost")
		_say("streak_lost", 0, 60.0))
	sim.near_miss.connect(func(_item: TrackItem) -> void:
		sfx.play("pickup", 1.6)
		hud.show_popup("O WŁOS!", Palette.UI_SCRAP, 0.9))
	sim.crate_opened.connect(func(_item: TrackItem, prize: int, amount: int) -> void:
		sfx.play("crate")
		match prize:
			RunSimulation.Prize.SCRAP_RAIN:
				hud.show_popup("SKRZYNIA: DESZCZ ZĘBATEK!", Palette.UI_SCRAP, 1.8)
			RunSimulation.Prize.FUEL:
				hud.show_popup("SKRZYNIA: KANISTER PALIWA", Color("ff8a4a"), 1.8)
			RunSimulation.Prize.CHARGE:
				hud.show_popup("SKRZYNIA: PEŁNY DOPALACZ I KONDENSATORY", Palette.UI_GOOD, 1.8)
			_:
				hud.show_popup("SKRZYNIA: ZŁOTA ZĘBATKA +%d" % amount, Color("ffd21a"), 1.8)
		_say("crate", 0, 80.0))


## Rekordy mocy na żywo: gdy najlepszy odcinek tej wyprawy przebije zapisany rekord.
func _tick_records(delta: float) -> void:
	_record_t += delta
	if _record_t < 1.0:
		return
	_record_t = 0.0
	var source := App.power_source_tag()
	if source == "auto":
		return
	var metrics := sim.expedition.metrics
	for i in TrainingMetrics.BEST_KEYS.size():
		var key := TrainingMetrics.BEST_KEYS[i]
		var old := App.progress.record(source, key)
		if old <= 0.0 or _record_checked.has(key) or metrics.best_power(i) <= old + 1.0:
			continue
		_record_checked[key] = true
		sfx.play("fanfare", 1.15)
		hud.show_message("NOWY REKORD: MOC %s\n%d W  (było %d W)" % [TrainingMetrics.BEST_NAMES[i].to_upper(), roundi(metrics.best_power(i)), roundi(old)], 4.0)
		_say("record", 2)


# --- Dopalacz --------------------------------------------------------------------

func _fire_boost(by_player: bool) -> void:
	if sim.trigger_boost():
		sfx.play("boost")
		var t := sim.power_train
		camera.shake(0.5)
		hud.show_popup("DOPALACZ! +%d%% MOCY" % roundi(t.boost_gain * 100.0), Color("ff9a4a"), 1.6)
		_say("boost", 1, 25.0)
	elif by_player and not sim.power_train.is_boosting():
		hud.show_popup("DOPALACZ PUSTY – zbierz kanister", Palette.UI_DIM, 1.4)
		_say("boost_empty", 0, 60.0)


# --- Gadające głowy --------------------------------------------------------------

var _chat := Chatter.new()
var _chat_until: Dictionary = {}
var _lore_left_s := 28.0
var _lore_count := 0
var _window_seen := 0
var _low_cadence_s := 0.0
var _good_cadence_s := 0.0
var _overheat_s := 0.0
var _weak_s := 0.0


## Postać komentuje zdarzenie. cooldown_s: nie częściej niż co tyle sekund wyprawy.
func _say(event: String, priority: int = 1, cooldown_s: float = 0.0) -> void:
	var now := sim.expedition.elapsed_s
	if cooldown_s > 0.0 and now < float(_chat_until.get(event, -1e9)):
		return
	_chat_until[event] = now + cooldown_s
	if not hud.head_busy() or priority >= 2:
		sfx.play("radio", 1.0, -6.0)
	hud.say(_chat.line(event), priority)
	_lore_left_s = maxf(_lore_left_s, 22.0)


func _on_raider_spawned(r: RaiderModel) -> void:
	if r.is_convoy_part():
		return
	if sim.convoys.is_active():
		_say("escort", 0, 45.0)
	else:
		_say("raider", 0, 70.0)


## Gadki w tle: fabuła, gdy nic się nie dzieje, oraz uwagi do kadencji i widełek mocy.
func _tick_chatter(delta: float, power_w: float) -> void:
	var busy := sim.convoys.is_active() or sim.raids.state != RaidDirector.State.IDLE or sim.challenges.is_active()
	_lore_left_s -= delta
	if _lore_left_s <= 0.0 and not busy and not hud.head_busy() and sim.vehicle.speed_mps > 2.0:
		_lore_left_s = 65.0
		_lore_count += 1
		_say("crew" if sim.power_train.crew > 0 and _lore_count % 4 == 2 else "lore", 0)
	var cadence := power.get_cadence()
	_low_cadence_s = _low_cadence_s + delta if power_w > 80.0 and cadence > 20.0 and cadence < 65.0 else 0.0
	if _low_cadence_s > 25.0:
		_low_cadence_s = 0.0
		_say("cadence_low", 0, 150.0)
	_good_cadence_s = _good_cadence_s + delta if cadence >= 86.0 and cadence <= 96.0 else 0.0
	if _good_cadence_s > 60.0:
		_good_cadence_s = 0.0
		_say("cadence_good", 0, 240.0)
	var band := sim.combat.band_status(power_w)
	_overheat_s = _overheat_s + delta if band == TargetBand.Status.ABOVE else 0.0
	if _overheat_s > 6.0:
		_overheat_s = 0.0
		_say("overheat", 1, 75.0)
	_weak_s = _weak_s + delta if band == TargetBand.Status.BELOW and (busy or workout != null) else 0.0
	if _weak_s > 12.0:
		_weak_s = 0.0
		_say("weak", 1, 90.0)


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
	if _update_convoy_hud():
		hud.update_scout(false)
		return
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
	c.shot_fired.connect(func(_p: Dictionary) -> void:
		buggy.muzzle_flash()
		sfx.play("shot", randf_range(0.92, 1.08), -9.0))
	c.wreck_destroyed.connect(func(item: TrackItem) -> void:
		combat_view.explode_at(Vector3(sim.lane_x(item.lane), 0.0, -(item.distance_m - sim.vehicle.distance_m)))
		hud.show_popup("WRAK ROZBITY", Palette.UI_GOOD, 1.0))


func _on_raider_warning(r: RaiderModel) -> void:
	sfx.play("warn")
	hud.show_message("ATAK Z %s!" % ("LEWEJ" if r.side < 0 else "PRAWEJ"), 1.2)


func _on_ram_resolved(_r: RaiderModel, outcome: int, lost: int) -> void:
	match outcome:
		CombatModel.RamOutcome.HIT:
			buggy.on_hit()
			camera.shake(1.2)
			sfx.play("hit")
			hud.show_popup("RABUNEK! -%d ZŁOMU" % lost if lost > 0 else "ZEPCHNIĘTY!", Palette.UI_BAD)
			_say("ram_hit", 1, 40.0)
		CombatModel.RamOutcome.BLOCKED:
			buggy.discharge()
			camera.shake(0.5)
			sfx.play("hit", 1.8, -4.0)
			hud.show_popup("WYŁADOWANIE ODRZUCIŁO NAPASTNIKA", Palette.UI_SCRAP)
			_say("ram_blocked", 0, 90.0)
		CombatModel.RamOutcome.DODGED:
			hud.show_popup("UNIK!", Palette.UI_GOOD)
		CombatModel.RamOutcome.COUNTER:
			camera.shake(0.4)
			hud.show_popup("ODEPCHNIĘTY!", Palette.UI_GOOD)


func _on_raider_destroyed(r: RaiderModel, dropped: int, cause: int) -> void:
	sfx.play("boom", 0.8 if r.half_length > 0.0 else 1.0)
	combat_view.explode_at(Vector3(r.x, 0.0, -(r.d - sim.vehicle.distance_m)))
	camera.shake(0.35)
	if r.is_convoy_part():
		# Wagon wybucha na całej długości; resztę (komunikaty, łup) prowadzi konwój.
		for k: float in [-1.0, 1.0]:
			if r.half_length > 0.0:
				combat_view.explode_at(Vector3(r.x, 0.0, -(r.d + k * r.half_length - sim.vehicle.distance_m)))
		return
	_say("raider_destroyed", 0, 35.0)
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
	s["source"] = App.power_source_tag()
	s["contracts"] = sim.contracts.to_summary()
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
	sfx.play("hit")
	buggy.on_hit()
	camera.shake(1.0)
	hud.flash_hit(lost)


func _on_scrap_collected(_item: TrackItem) -> void:
	sfx.pickup(sim.streak.tier())
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
