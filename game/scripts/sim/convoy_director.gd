class_name ConvoyDirector
extends RefCounted
## Konwoje Tłustych (docs/swiat.md). Środkowym pasem jedzie kolumna spięta sprzęgami:
##
##   [OGON ze strażą] =sprzęg= [GALERA: klatka z pedalarzami i paliwem] =sprzęg= [CIĄGNIK]
##
## Celem nie jest „strzelać, aż padnie”, tylko ODCZEPIĆ galerę. Trzy drogi:
## - chirurg: zrównaj się z tylnym sprzęgiem (ogon odpada, miny się kończą), potem
##   z przednim – czyste odcięcie, pełny łup i dodatkowy uwolniony pedalarz;
## - na skróty: od razu przedni sprzęg – szybciej, ale ogon dalej wisi na zdobyczy
##   (mniej łupu), chyba że zdążysz go odciąć podczas przesiadki;
## - rzeźnik: rozbij ciągnik – najwięcej pancerza i najtrudniejsze tempo, za to łup x1,5.
## W klatkę nie wolno strzelać: każde trzy trafienia to jeden uwolniony mniej.
##
## To walka o tempo. Konwój jedzie własnym rytmem liczonym od FTP gracza na wzorcowym,
## nieulepszonym pojeździe (akceleratory i dopalacz realnie pomagają), a Tłusty na zmianę
## każe pedalarzom gnać i hamować. Sprzęg da się trafić tylko z boku, z bliska – trzeba
## przyspieszać i zwalniać, żeby utrzymać się w oknie. Za mało mocy i konwój ucieka.
## Po odcięciu wagon wytraca prędkość: trzeba ZWOLNIĆ i przytrzymać się go do przesiadki.

signal sighted(info: Dictionary)
signal engaged(info: Dictionary)
signal pace_warning(fast: bool)
signal pace_changed(fast: bool)
signal hitch_broken(front: bool)
signal guard_lost(destroyed: bool)
signal tractor_destroyed
signal cage_hit(freed_left: int)
signal mine_dropped(mine: Dictionary)
signal mine_exploded(mine: Dictionary, hit: bool, blocked: bool, scrap_lost: int)
signal bumped(squeezed: bool)
signal capture_started(jackpot: bool)
signal finished(info: Dictionary, result: Dictionary)

enum State { IDLE, CHASE, ENGAGED, CAPTURE }
enum Outcome { CAPTURED, PARTIAL, OUTRUN, PASSED, FORTRESS, TIME_UP }

const TIERS: Array[Dictionary] = [
	{"name": "Cysterna Tłustych", "hitch_hp": 9, "guard_hp": 28, "tractor_hp": 70, "pace": 1.0, "scrap": 150, "fuel": 3, "freed": 2},
	{"name": "Galera Smalca", "hitch_hp": 16, "guard_hp": 55, "tractor_hp": 150, "pace": 1.05, "scrap": 240, "fuel": 5, "freed": 3},
	{"name": "Skarbiec Barona", "hitch_hp": 28, "guard_hp": 100, "tractor_hp": 300, "pace": 1.1, "scrap": 360, "fuel": 8, "freed": 5},
]

## Układ kolumny względem środka galery [m], dodatnie = do przodu.
const TRACTOR_OFFSET_M := 11.0
const GUARD_OFFSET_M := -10.0
const HITCH_FRONT_OFFSET_M := 5.6
const HITCH_REAR_OFFSET_M := -5.2
const TRACTOR_HALF_M := 4.0
const GALLEY_HALF_M := 4.2
const GUARD_HALF_M := 3.4
## Okno sprzęgu: jedziesz bocznym pasem tuż ZA sprzęgiem (widzisz go przed sobą, skosem).
## Tyle metrów za nim i tyle przed nim jeszcze da się trafić w sworzeń.
const WINDOW_BACK_M := 8.0
const WINDOW_FRONT_M := 1.5

const SIGHT_GAP_M := 110.0
const ENGAGE_GAP_M := 40.0
const ESCAPE_CHASE_M := 220.0
const ESCAPE_ENGAGED_M := 140.0
const PASSED_REL_M := 90.0
## Tempo jako ułamek FTP gracza na wzorcowym pojeździe.
const CHASE_FTP := 0.72
const FAST_FTP := 1.0
const SLOW_FTP := 0.55
const FAST_S := 15.0
const SLOW_S := 11.0
const PACE_WARN_S := 2.0
## Konwój to ciężki sprzęt: różnicę tempa widać w odstępie kilkukrotnie mocniej, żeby
## pościg i gubienie trwały sekundy, a nie minuty.
const CHASE_GAIN := 3.0
const ENGAGED_GAIN := 2.5
const MAX_GAP_RATE := 10.0
const ENGAGE_LIMIT_S := 210.0
const MIN_TIME_LEFT_S := 170.0
## Przesiadka po odcięciu: wagon wytraca prędkość, trzeba przy nim zostać.
const CAPTURE_SPEED := 3.0
const CAPTURE_DECEL := 0.7
const BOARD_S := 4.0
## Przesiadka liczy się tylko przy małej prędkości – trzeba naprawdę odpuścić.
const BOARD_MAX_SPEED := 5.0
const BOARD_BEHIND_M := -16.0
const BOARD_AHEAD_M := 14.0
const CAPTURE_LIMIT_S := 45.0
const LOST_AHEAD_M := 80.0
const LOST_BEHIND_M := -120.0
const MINE_FUSE_S := 1.7
const MINE_GAP_S := 4.2
const MINE_CAPACITOR_COST := 0.25
const BUMP_COOLDOWN_S := 1.2
const ESCORT_GAP_S := 20.0
const CAGE_HITS_PER_PEDALER := 3

var enabled := false
var ftp_w := 200.0
var first_at_s := 150.0
var gap_s := 300.0
## Poziom konwojów rośnie z podwoziem gracza (0–2); drugi konwój wyprawy jest o stopień cięższy.
var base_tier := 0
## Wyłączane w testach, żeby eskorta nie mieszała w pomiarach.
var escorts_enabled := true

var state: State = State.IDLE
var info: Dictionary = {}
var tier := 0
var tractor: RaiderModel
var galley: RaiderModel
var guard: RaiderModel
var hitch_front: RaiderModel
var hitch_rear: RaiderModel
var guard_attached := false
var tractor_attached := false
var pace_fast := false
var engaged_s := 0.0
var board_s := 0.0
var jackpot := false
var clean_cuts := 0
var cage_hits := 0
var mines: Array[Dictionary] = []
var convoys_seen := 0
var captured := 0

var _sim_ref: WeakRef
var _rng := RandomNumberGenerator.new()
var _reference := VehicleModel.new()
var _next_at_s := 0.0
var _pace_v := 0.0
var _pace_left_s := 0.0
var _pace_warned := false
var _bump_left_s := 0.0
var _mine_left_s := 0.0
var _escort_left_s := 0.0
var _capture_s := 0.0
var _next_mine_id := 1
var _leaving: Array[Dictionary] = []


func _init(sim: RunSimulation, seed_value: int = 0) -> void:
	_sim_ref = weakref(sim)
	_rng.seed = seed_value + 4421
	_next_at_s = first_at_s


func set_first_at(seconds: float) -> void:
	first_at_s = seconds
	_next_at_s = seconds


func is_active() -> bool:
	return state != State.IDLE


## Odstęp od zderzaka gracza do końca kolumny [m]; dodatni = konwój jest przed nami.
func gap_m() -> float:
	var sim := _sim()
	if galley == null or sim == null:
		return 0.0
	return _tail_d() - sim.vehicle.distance_m - sim.vehicle_half_length_m


## Położenie gracza względem środka galery [m]; dodatnie = gracz z przodu.
func rel_m() -> float:
	var sim := _sim()
	return sim.vehicle.distance_m - galley.d if galley != null and sim != null else 0.0


## Które okno sprzęgu jest teraz otwarte: 0 = żadne, 1 = tylne, 2 = przednie.
func open_window() -> int:
	if hitch_front != null and hitch_front.is_alive() and hitch_front.exposed:
		return 2
	if hitch_rear != null and hitch_rear.is_alive() and hitch_rear.exposed:
		return 1
	return 0


## Moc z nóg, przy której gracz trzyma tempo konwoju (z jego akceleratorami i dopalaczem).
func hold_power_w() -> float:
	var sim := _sim()
	if sim == null or not is_active():
		return 0.0
	_reference.grade = sim.vehicle.grade
	return maxf(0.0, _reference.resist_force(_pace_v) * _pace_v / maxf(sim.power_multiplier(), 0.1))


## Cel mocy do zasilania kondensatorów i działka.
func target_w() -> float:
	match state:
		State.CHASE:
			return roundf(ftp_w * 0.85 / 5.0) * 5.0
		State.ENGAGED:
			return roundf(ftp_w * (FAST_FTP if pace_fast else SLOW_FTP) / 5.0) * 5.0
		State.CAPTURE:
			return roundf(ftp_w * 0.35 / 5.0) * 5.0
	return 0.0


## Tolerancje widełek: w pościgu i sprincie luz u góry, przy hamowaniu – u dołu.
func band_low() -> float:
	match state:
		State.ENGAGED:
			return 0.08 if pace_fast else 0.3
		State.CAPTURE:
			# Przy przesiadce nie ma „za słabo” – trzeba odpuścić.
			return 1.0
	return 0.15


func band_high() -> float:
	if state == State.ENGAGED and not pace_fast:
		return 0.35
	return 0.6


func time_to_fortress_s() -> float:
	return maxf(0.0, ENGAGE_LIMIT_S - engaged_s) if state == State.ENGAGED else 0.0


func pace_left_s() -> float:
	return maxf(0.0, _pace_left_s)


func board_ratio() -> float:
	return clampf(board_s / BOARD_S, 0.0, 1.0)


## Ilu pedalarzy wyjdzie z klatki, jeśli teraz przejmiesz galerę.
func freed_now() -> int:
	var base := int(info.get("freed", 0)) - floori(cage_hits / float(CAGE_HITS_PER_PEDALER))
	if clean_cuts >= 2:
		base += 1
	return maxi(0, base)


func step(delta: float) -> void:
	var sim := _sim()
	if sim == null or delta <= 0.0:
		return
	_move_leaving(sim, delta)
	_step_mines(sim, delta)
	if state == State.IDLE:
		_maybe_sight(sim)
		return
	_bump_left_s = maxf(0.0, _bump_left_s - delta)
	_drive(sim, delta)
	_check_damage(sim)
	_expose(sim)
	_plow_wrecks(sim)
	_bump(sim)
	match state:
		State.CHASE:
			if gap_m() <= ENGAGE_GAP_M:
				_engage()
			elif gap_m() > ESCAPE_CHASE_M:
				_end(sim, Outcome.OUTRUN)
			elif sim.expedition.finished:
				_end(sim, Outcome.TIME_UP)
		State.ENGAGED:
			engaged_s += delta
			_tick_pace(delta)
			_tick_escorts(sim, delta)
			_tick_mine_drop(sim, delta)
			if gap_m() > ESCAPE_ENGAGED_M:
				_end(sim, Outcome.OUTRUN)
			elif rel_m() > PASSED_REL_M:
				_end(sim, Outcome.PASSED)
			elif engaged_s >= ENGAGE_LIMIT_S:
				_end(sim, Outcome.FORTRESS)
			elif sim.expedition.finished:
				_end(sim, Outcome.TIME_UP)
		State.CAPTURE:
			_capture_s += delta
			_tick_mine_drop(sim, delta)
			var rel := rel_m()
			if rel > BOARD_BEHIND_M and rel < BOARD_AHEAD_M and sim.vehicle.speed_mps <= BOARD_MAX_SPEED:
				board_s += delta
			if board_s >= BOARD_S:
				_finish_capture(sim, false)
			elif rel > LOST_AHEAD_M or rel < LOST_BEHIND_M or _capture_s > CAPTURE_LIMIT_S or sim.expedition.finished:
				_finish_capture(sim, true)


# --- Start i ruch kolumny ------------------------------------------------------

func _maybe_sight(sim: RunSimulation) -> void:
	var e := sim.expedition
	if not enabled or e.finished or sim.safe_zone or not sim.combat.enabled:
		return
	if e.elapsed_s < _next_at_s or e.time_left_s() < MIN_TIME_LEFT_S:
		return
	if sim.raids.state != RaidDirector.State.IDLE or sim.challenges.phase != ChallengeDirector.Phase.IDLE:
		return
	tier = mini(TIERS.size() - 1, base_tier + (1 if convoys_seen > 0 else 0))
	convoys_seen += 1
	info = TIERS[tier].duplicate()
	info["tier"] = tier
	var c := sim.combat
	galley = c.add_convoy_part(RaiderModel.Part.GALLEY, 1, tier)
	galley.invulnerable = true
	galley.half_length = 3.0
	galley.hit_radius = 1.1
	galley.exposed = false
	tractor = c.add_convoy_part(RaiderModel.Part.TRACTOR, int(info["tractor_hp"]), tier)
	tractor.half_length = 3.2
	tractor.hit_radius = 1.1
	guard = c.add_convoy_part(RaiderModel.Part.GUARD, int(info["guard_hp"]), tier)
	guard.half_length = 2.6
	guard.hit_radius = 1.1
	hitch_front = c.add_convoy_part(RaiderModel.Part.HITCH_FRONT, int(info["hitch_hp"]), tier)
	hitch_rear = c.add_convoy_part(RaiderModel.Part.HITCH_REAR, int(info["hitch_hp"]), tier)
	for h: RaiderModel in [hitch_front, hitch_rear]:
		h.hit_radius = 1.3
		h.aim_priority = 50.0
		h.exposed = false
	guard_attached = true
	tractor_attached = true
	jackpot = false
	clean_cuts = 0
	cage_hits = 0
	engaged_s = 0.0
	board_s = 0.0
	pace_fast = false
	galley.d = sim.vehicle.distance_m + sim.vehicle_half_length_m + SIGHT_GAP_M - GUARD_OFFSET_M + GUARD_HALF_M
	state = State.CHASE
	_pace_v = _ref_speed(sim, CHASE_FTP)
	_place(sim, _pace_v)
	_expose(sim)
	sighted.emit(info)


func _engage() -> void:
	state = State.ENGAGED
	pace_fast = true
	_pace_left_s = FAST_S
	_pace_warned = false
	engaged_s = 0.0
	_escort_left_s = 4.0
	_mine_left_s = 3.0
	engaged.emit(info)


func _drive(sim: RunSimulation, delta: float) -> void:
	var pv := sim.vehicle.speed_mps
	var want := CAPTURE_SPEED
	var gain := 1.0
	var accel := CAPTURE_DECEL
	match state:
		State.CHASE:
			want = _ref_speed(sim, CHASE_FTP)
			gain = CHASE_GAIN
			accel = 2.0
		State.ENGAGED:
			want = _ref_speed(sim, FAST_FTP * float(info["pace"]) if pace_fast else SLOW_FTP)
			gain = ENGAGED_GAIN
			accel = 2.0
	_pace_v = move_toward(_pace_v, want, accel * delta)
	var rate := clampf(gain * (_pace_v - pv), -MAX_GAP_RATE, MAX_GAP_RATE)
	var old := galley.d
	galley.d += maxf(0.0, pv + rate) * delta
	_place(sim, (galley.d - old) / delta)


## Ustawia części kolumny względem galery.
func _place(sim: RunSimulation, speed: float) -> void:
	var cx := sim.lane_x(_lane(sim))
	var slowing := (state == State.ENGAGED and not pace_fast) or state == State.CAPTURE
	galley.x = cx
	galley.speed = speed
	galley.braking = slowing
	if tractor_attached:
		# Rozbity ciągnik (droga „rzeźnika”) dalej wisi na sprzęgu jako wrak.
		tractor.d = galley.d + TRACTOR_OFFSET_M
		tractor.x = cx
		tractor.speed = speed
		tractor.braking = slowing
		if hitch_front.is_alive():
			hitch_front.d = galley.d + HITCH_FRONT_OFFSET_M
			hitch_front.x = cx
			hitch_front.speed = speed
	if guard_attached:
		guard.d = galley.d + GUARD_OFFSET_M
		guard.x = cx
		guard.speed = speed
		guard.braking = slowing
		hitch_rear.d = galley.d + HITCH_REAR_OFFSET_M
		hitch_rear.x = cx
		hitch_rear.speed = speed
	sim.combat.wall_active = true
	sim.combat.wall_x = cx
	sim.combat.wall_from_d = _tail_d()
	sim.combat.wall_to_d = _nose_d()


## Prędkość, jaką przy danej części FTP osiąga wzorcowy pojazd na bieżącym nachyleniu.
func _ref_speed(sim: RunSimulation, ftp_fraction: float) -> float:
	_reference.grade = sim.vehicle.grade
	return _reference.steady_state_speed(ftp_w * ftp_fraction)


func _lane(sim: RunSimulation) -> int:
	return floori((sim.lanes.lane_count - 1) / 2.0)


func _tail_d() -> float:
	return guard.d - GUARD_HALF_M if guard_attached else galley.d - GALLEY_HALF_M


func _nose_d() -> float:
	return tractor.d + TRACTOR_HALF_M if tractor_attached else galley.d + GALLEY_HALF_M


# --- Tempo, eskorta, miny ------------------------------------------------------

func _tick_pace(delta: float) -> void:
	_pace_left_s -= delta
	if not _pace_warned and _pace_left_s <= PACE_WARN_S:
		_pace_warned = true
		pace_warning.emit(not pace_fast)
	if _pace_left_s <= 0.0:
		pace_fast = not pace_fast
		_pace_left_s = (FAST_S if pace_fast else SLOW_S) * _rng.randf_range(0.85, 1.15)
		_pace_warned = false
		pace_changed.emit(pace_fast)


## Wozy eskorty dojeżdżają od zewnętrznej strony – po drugiej jest ściana konwoju.
func _tick_escorts(sim: RunSimulation, delta: float) -> void:
	_escort_left_s -= delta
	if _escort_left_s > 0.0 or not escorts_enabled:
		return
	_escort_left_s = ESCORT_GAP_S - 3.0 * tier
	var attackers := 0
	for r in sim.combat.live_raiders():
		if not r.is_convoy_part() and r.state != RaiderModel.State.RETREAT:
			attackers += 1
	if attackers >= 2:
		return
	var lane := sim.lanes.target_lane
	var side := -1 if _rng.randf() < 0.5 else 1
	if lane < _lane(sim):
		side = -1
	elif lane > _lane(sim):
		side = 1
	sim.combat.spawn_raider(side)


## Strażnik z ogona zrzuca miny beczkowe na pas gracza, dopóki ten jedzie za konwojem.
func _tick_mine_drop(sim: RunSimulation, delta: float) -> void:
	if not guard_attached or not guard.is_alive():
		return
	var pd := sim.vehicle.distance_m
	var behind := guard.d - GUARD_HALF_M - pd
	if behind < 6.0 or behind > 70.0:
		_mine_left_s = maxf(_mine_left_s, 1.0)
		return
	_mine_left_s -= delta
	if _mine_left_s > 0.0:
		return
	_mine_left_s = MINE_GAP_S - 0.5 * tier
	var d := minf(pd + maxf(12.0, sim.vehicle.speed_mps * MINE_FUSE_S), guard.d - GUARD_HALF_M - 1.0)
	var mine := {"id": _next_mine_id, "lane": sim.lanes.target_lane, "d": d, "t_left": MINE_FUSE_S}
	_next_mine_id += 1
	mines.append(mine)
	mine_dropped.emit(mine)


func _step_mines(sim: RunSimulation, delta: float) -> void:
	if mines.is_empty():
		return
	var kept: Array[Dictionary] = []
	for mine in mines:
		mine["t_left"] = float(mine["t_left"]) - delta
		if float(mine["t_left"]) > 0.0:
			kept.append(mine)
			continue
		var hit := absf(float(mine["d"]) - sim.vehicle.distance_m) < 3.5 and absf(sim.lane_x(int(mine["lane"])) - sim.lanes.x_m) < 1.6
		var blocked := false
		var lost := 0
		if hit:
			if sim.combat.capacitor >= MINE_CAPACITOR_COST:
				sim.combat.capacitor -= MINE_CAPACITOR_COST
				blocked = true
			else:
				sim.vehicle.apply_impact(0.6)
				lost = sim.expedition.lose_scrap_to_shell()
		mine_exploded.emit(mine, hit, blocked, lost)
	mines = kept


# --- Trafienia i odsłonięcie celów ---------------------------------------------

func _check_damage(sim: RunSimulation) -> void:
	if galley.hits_taken > cage_hits:
		cage_hits = galley.hits_taken
		cage_hit.emit(freed_now())
	if guard_attached:
		if not guard.is_alive():
			guard_attached = false
			sim.combat.remove_raider(hitch_rear)
			guard_lost.emit(true)
		elif not hitch_rear.is_alive():
			guard_attached = false
			clean_cuts += 1
			hitch_broken.emit(false)
			_leave(guard, -7.0)
			guard_lost.emit(false)
	if state == State.CAPTURE:
		return
	if not tractor.is_alive():
		jackpot = true
		sim.combat.remove_raider(hitch_front)
		tractor_destroyed.emit()
		_start_capture()
	elif not hitch_front.is_alive():
		tractor_attached = false
		clean_cuts += 1
		hitch_broken.emit(true)
		_leave(tractor, 9.0)
		_start_capture()


func _start_capture() -> void:
	state = State.CAPTURE
	board_s = 0.0
	_capture_s = 0.0
	galley.detached = true
	capture_started.emit(jackpot)


## Co wieżyczka może teraz wziąć na cel. Sprzęg: tylko z bocznego pasa i z bliska.
## Ogon: gdy jedziesz za nim albo obok. Ciągnik: gdy jesteś na jego wysokości.
func _expose(sim: RunSimulation) -> void:
	var pd := sim.vehicle.distance_m
	var beside := absf(sim.lanes.x_m - galley.x) > 1.8
	galley.exposed = false
	if hitch_rear.is_alive():
		hitch_rear.exposed = guard_attached and beside and _in_window(pd, hitch_rear)
	if hitch_front.is_alive():
		hitch_front.exposed = tractor_attached and state != State.CAPTURE and beside and _in_window(pd, hitch_front)
	if guard.is_alive():
		guard.exposed = guard_attached and pd < guard.d + GUARD_HALF_M + 2.0
	if tractor.is_alive():
		tractor.exposed = tractor_attached and state != State.CAPTURE and beside and pd > tractor.d - TRACTOR_HALF_M - 3.0


func _in_window(pd: float, hitch: RaiderModel) -> bool:
	var ahead := hitch.d - pd
	return ahead >= -WINDOW_FRONT_M and ahead <= WINDOW_BACK_M


## Środek okna sprzęgu względem środka galery [m] – tu warto się ustawić.
static func window_center_m(front: bool) -> float:
	return (HITCH_FRONT_OFFSET_M if front else HITCH_REAR_OFFSET_M) - (WINDOW_BACK_M - WINDOW_FRONT_M) * 0.5


## Kolumna taranuje wraki przed sobą – droga za konwojem jest czysta.
func _plow_wrecks(sim: RunSimulation) -> void:
	var from := _tail_d() - 2.0
	var to := _nose_d() + 12.0
	for item in sim.items:
		if not item.consumed and item.is_wreck() and item.distance_m > from and item.distance_m < to:
			item.consumed = true


## Kolumna zajmuje środkowy pas: wjechanie w tył wyhamowuje, a wciśnięcie się między
## wagony kończy się odbiciem na boczny pas.
func _bump(sim: RunSimulation) -> void:
	if _bump_left_s > 0.0:
		return
	var px := sim.lanes.x_m
	if absf(px - galley.x) > 2.1:
		return
	var pd := sim.vehicle.distance_m
	var half := sim.vehicle_half_length_m
	var tail := _tail_d()
	var nose := _nose_d()
	if pd + half < tail - 0.3 or pd - half > nose + 0.3:
		return
	_bump_left_s = BUMP_COOLDOWN_S
	sim.vehicle.apply_impact(0.6)
	sim.combat.capacitor = maxf(0.0, sim.combat.capacitor - 0.2)
	var squeezed := pd > tail + 1.0 and pd < nose - 1.0
	if squeezed:
		if sim.lanes.target_lane == _lane(sim):
			sim.lanes.request_change(-1 if px <= galley.x else 1)
	elif pd <= tail + 1.0:
		_shift(sim, (pd + half + 0.6) - tail)
	else:
		_shift(sim, (pd - half - 0.6) - nose)
	bumped.emit(squeezed)


## Przesuwa całą kolumnę o podaną liczbę metrów (po zetknięciu z graczem).
func _shift(sim: RunSimulation, meters: float) -> void:
	galley.d += meters
	_place(sim, galley.speed)


# --- Koniec --------------------------------------------------------------------

func _finish_capture(sim: RunSimulation, partial: bool) -> void:
	var scrap := float(info["scrap"])
	var fuel := int(info["fuel"])
	var freed := freed_now()
	var guard_hangs := guard_attached and guard.is_alive()
	if jackpot:
		scrap *= 1.5
		fuel += 2
	if guard_hangs:
		scrap *= 0.7
	if partial:
		scrap *= 0.4
		fuel = 1
		freed = 0
	var result := {"scrap": roundi(scrap), "fuel": fuel, "freed": freed, "jackpot": jackpot, "clean": clean_cuts >= 2, "guard_hangs": guard_hangs}
	sim.expedition.add_scrap(int(result["scrap"]))
	sim.expedition.add_fuel(fuel)
	sim.expedition.pedalers_freed += freed
	if not partial:
		sim.expedition.convoys_captured += 1
		captured += 1
	_end(sim, Outcome.PARTIAL if partial else Outcome.CAPTURED, result)


func _end(sim: RunSimulation, outcome: Outcome, result: Dictionary = {}) -> void:
	if outcome != Outcome.CAPTURED:
		sim.expedition.convoys_lost += 1
	for r: RaiderModel in [tractor, galley, guard, hitch_front, hitch_rear]:
		if r == null or not r.is_alive() or _is_leaving(r):
			continue
		if r.is_hitch() or outcome == Outcome.OUTRUN or outcome == Outcome.PASSED:
			sim.combat.remove_raider(r)
		elif outcome == Outcome.FORTRESS or outcome == Outcome.TIME_UP:
			_leave(r, 9.0)
		else:
			_leave(r, -6.0)
	sim.combat.wall_active = false
	state = State.IDLE
	_next_at_s = sim.expedition.elapsed_s + gap_s
	var done_info := info
	tractor = null
	galley = null
	guard = null
	hitch_front = null
	hitch_rear = null
	result["outcome"] = outcome
	finished.emit(done_info, result)


## Część odjeżdża (dodatnie tempo) albo zostaje w tyle (ujemne) i znika z pola walki.
func _leave(r: RaiderModel, rate: float) -> void:
	r.exposed = false
	r.detached = true
	_leaving.append({"r": r, "rate": rate, "t": 0.0})


func _is_leaving(r: RaiderModel) -> bool:
	for entry in _leaving:
		if entry["r"] == r:
			return true
	return false


func _move_leaving(sim: RunSimulation, delta: float) -> void:
	if _leaving.is_empty():
		return
	var pv := sim.vehicle.speed_mps
	var pd := sim.vehicle.distance_m
	var kept: Array[Dictionary] = []
	for entry in _leaving:
		var r: RaiderModel = entry["r"]
		if not r.is_alive():
			continue
		entry["t"] = float(entry["t"]) + delta
		r.speed = maxf(0.0, pv + float(entry["rate"]))
		r.d += r.speed * delta
		if absf(r.d - pd) > 110.0 or float(entry["t"]) > 25.0:
			sim.combat.remove_raider(r)
		else:
			kept.append(entry)
	_leaving = kept


func _sim() -> RunSimulation:
	return _sim_ref.get_ref() as RunSimulation
