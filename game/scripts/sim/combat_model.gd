class_name CombatModel
extends RefCounted
## Walka (etap 2) jako czysta logika na współrzędnych trasy: x = przesunięcie boczne [m],
## d = dystans wzdłuż trasy [m]. Bez węzłów i fizyki – testowalna headless.
##
## Zasady z CLAUDE.md:
## - wrogowie nadjeżdżają z boków i próbują zepchnąć gracza; obrona: wieżyczka albo zmiana pasa,
## - przegrana potyczka = utrata części złomu, nigdy „śmierć” ani przerwanie jazdy,
## - trzymanie zadanej mocy = pełna tarcza i szybszy ogień; poniżej celu słabiej, ale grywalnie.
##
## „Zasilanie” = moc / moc docelowa (wygładzone). Tarcza ładuje się proporcjonalnie do
## zasilania, a odstęp między strzałami skraca się do minimum przy >= 100%.

signal raider_spawned(raider: RaiderModel)
signal raider_warning(raider: RaiderModel)
signal ram_resolved(raider: RaiderModel, outcome: int, scrap_lost: int)
signal raider_destroyed(raider: RaiderModel, scrap_dropped: int, cause: int)
signal shot_fired(projectile: Dictionary)
signal raider_hit(raider: RaiderModel)
signal wreck_destroyed(item: TrackItem)

enum RamOutcome { HIT, BLOCKED, DODGED, COUNTER }
enum DestroyCause { SHOT, WRECK }

const SHIELD_REGEN_PER_S := 0.07
const SHIELD_RAM_COST := 0.4
const SHIELD_START := 0.5
const BASE_FIRE_INTERVAL_S := 0.55
const MIN_SUPPLY_FOR_FIRE := 0.35
const PROJECTILE_SPEED := 75.0
const PROJECTILE_MAX_AGE_S := 1.2
const HIT_RADIUS := 1.5
const RAIDER_HALF_WIDTH := 1.0
const PLAYER_HALF_WIDTH := 0.95
const SPAWN_BEHIND_M := 38.0
const SHADOW_TIME_S := 2.2
const TELEGRAPH_TIME_S := 1.3
const RAM_TIME_S := 0.55
const LATERAL_SPEED := 4.5
const AIM_CONE_COS := 0.64

## Słaba referencja: RunSimulation trzyma CombatModel, więc odwrotne silne powiązanie
## tworzyłoby cykl RefCounted (wyciek pamięci po każdej wyprawie).
var _sim_ref: WeakRef
var sim: RunSimulation:
	get:
		return _sim_ref.get_ref() as RunSimulation
var raiders: Array[RaiderModel] = []
var projectiles: Array[Dictionary] = []

var enabled := true
## Pole bezpieczne: brak nowych potyczek, napastnicy się wycofują.
var suppressed := false
var target_power_w := 130.0
## Widełki celu (TargetBand): ustawia kontroler zależnie od trybu (swobodna/wyzwanie/trening).
var target_low_tol := TargetBand.FREE_RIDE_LOW
var target_high_tol := TargetBand.FREE_RIDE_HIGH
## Ulepszenia (etap 3): kondensator i wieżyczka.
var shield_regen_multiplier := 1.0
var fire_rate_multiplier := 1.0
var projectile_damage := 1
var supply := 1.0
var shield := SHIELD_START
var aim := Vector2.ZERO
var fire_held := false
var auto_fire := false
var locked_target_id := -1

## Harmonogram potyczek (sekundy wyprawy).
var first_encounter_s := 50.0
var encounter_gap_easy_s := 105.0
var encounter_gap_hard_s := 65.0

var raiders_destroyed := 0
var rams_blocked := 0
var rams_dodged := 0
var rams_taken := 0

var _rng := RandomNumberGenerator.new()
var _fire_cooldown := 0.0
var _next_encounter_s := 0.0
var _pending_spawns: Array[float] = []
var _next_id := 1
var _next_projectile_id := 1


func _init(p_sim: RunSimulation, seed_value: int = 0) -> void:
	_sim_ref = weakref(p_sim)
	_rng.seed = seed_value + 9137
	_next_encounter_s = first_encounter_s


func set_first_encounter(seconds: float) -> void:
	first_encounter_s = seconds
	_next_encounter_s = seconds


## Zasilanie pojazdu 0..1 (pełne w widełkach celu, mniejsze poniżej i przy przegrzaniu).
func supply_ratio() -> float:
	return supply


func band_status(power_w: float) -> TargetBand.Status:
	return TargetBand.status(power_w, target_power_w, target_low_tol, target_high_tol)


func fire_interval_s() -> float:
	return BASE_FIRE_INTERVAL_S / clampf(supply, MIN_SUPPLY_FOR_FIRE, 1.0) / maxf(fire_rate_multiplier, 0.1)


func live_raiders() -> Array[RaiderModel]:
	var out: Array[RaiderModel] = []
	for r in raiders:
		if r.is_alive():
			out.append(r)
	return out


func step(delta: float, power_w: float) -> void:
	if delta <= 0.0:
		return
	var ratio := TargetBand.supply(power_w, target_power_w, target_low_tol, target_high_tol)
	supply += (ratio - supply) * (1.0 - exp(-delta / 1.5))
	shield = minf(1.0, shield + SHIELD_REGEN_PER_S * shield_regen_multiplier * clampf(supply, 0.0, 1.0) * delta)
	if not enabled:
		return
	_schedule(delta)
	_update_raiders(delta)
	_update_fire(delta)
	_update_projectiles(delta)
	_prune()


# --- Potyczki -----------------------------------------------------------------

func _schedule(delta: float) -> void:
	var e := sim.expedition
	if e.finished:
		return
	if suppressed:
		_pending_spawns.clear()
		for r in raiders:
			if r.is_alive() and r.state != RaiderModel.State.RETREAT:
				r.set_state(RaiderModel.State.RETREAT)
		return
	if e.elapsed_s >= _next_encounter_s and e.time_left_s() > 20.0:
		var difficulty := e.progress()
		var count := 1
		if difficulty > 0.35:
			count += 1
		if difficulty > 0.75:
			count += 1
		for i in count:
			_pending_spawns.append(i * 1.6)
		_next_encounter_s = e.elapsed_s + lerpf(encounter_gap_easy_s, encounter_gap_hard_s, difficulty) * _rng.randf_range(0.8, 1.2)
	for i in range(_pending_spawns.size() - 1, -1, -1):
		_pending_spawns[i] -= delta
		if _pending_spawns[i] <= 0.0:
			_pending_spawns.remove_at(i)
			spawn_raider(-1 if _rng.randf() < 0.5 else 1)


func spawn_raider(attack_side: int) -> RaiderModel:
	var r := RaiderModel.new(_next_id, attack_side, _rng.randi_range(0, 2))
	_next_id += 1
	r.max_hp = 3 + r.variant
	r.hp = r.max_hp
	r.d = sim.vehicle.distance_m - SPAWN_BEHIND_M
	r.x = _shoulder_x(attack_side)
	r.speed = sim.vehicle.speed_mps + 6.0
	r.offset_d = _rng.randf_range(-1.5, 1.0)
	raiders.append(r)
	raider_spawned.emit(r)
	return r


# --- Ruch wrogów -----------------------------------------------------------------

func _update_raiders(delta: float) -> void:
	var px := sim.lanes.x_m
	var pd := sim.vehicle.distance_m
	var pv := sim.vehicle.speed_mps
	for r in raiders:
		r.timer += delta
		r.hit_flash = maxf(0.0, r.hit_flash - delta)
		if not r.is_alive():
			# Wrak wroga wytraca prędkość i zostaje w tyle.
			r.speed = maxf(0.0, r.speed - 14.0 * delta)
			r.d += r.speed * delta
			continue
		var old_x := r.x
		match r.state:
			RaiderModel.State.APPROACH:
				# Dojazd poboczem (tam nie ma wraków), dopiero obok gracza zjazd na pas.
				_follow_player(r, pd, pv, delta, 8.0)
				_steer_to(r, _shoulder_x(r.side), delta)
				if absf(r.d - (pd + r.offset_d)) < 1.2:
					r.set_state(RaiderModel.State.SHADOW)
			RaiderModel.State.SHADOW:
				_follow_player(r, pd, pv, delta, 4.0)
				_steer_to(r, _flank_x(r.side), delta)
				if _overlaps_player(r, px, pd):
					_counter_bump(r)
				elif r.timer >= SHADOW_TIME_S:
					r.set_state(RaiderModel.State.TELEGRAPH)
					# Cel ataku i pozycja zablokowane: zmiana pasa podczas ostrzeżenia = unik.
					r.locked_flank_x = _flank_x(r.side)
					r.ram_to_x = sim.lanes.lane_center(sim.lanes.target_lane)
					raider_warning.emit(r)
			RaiderModel.State.TELEGRAPH:
				_follow_player(r, pd, pv, delta, 4.0)
				_steer_to(r, r.locked_flank_x, delta)
				if _overlaps_player(r, px, pd):
					_counter_bump(r)
				elif r.timer >= TELEGRAPH_TIME_S:
					r.set_state(RaiderModel.State.RAM)
					r.ram_from_x = r.x
					r.ram_hit_resolved = false
			RaiderModel.State.RAM:
				_follow_player(r, pd, pv, delta, 4.0)
				var k := clampf(r.timer / RAM_TIME_S, 0.0, 1.0)
				r.x = lerpf(r.ram_from_x, r.ram_to_x, k * k * (3.0 - 2.0 * k))
				if not r.ram_hit_resolved and _overlaps_player(r, px, pd):
					_resolve_ram(r, true)
				elif k >= 1.0 and not r.ram_hit_resolved:
					_resolve_ram(r, false)
			RaiderModel.State.RETREAT:
				r.speed = maxf(0.0, pv - 5.0)
				r.d += r.speed * delta
				_steer_to(r, _shoulder_x(r.side), delta)
		r.lateral_velocity = (r.x - old_x) / delta
		# Wróg jadący obok gracza może rozbić się o wrak – warto go tam zwabić.
		if r.state == RaiderModel.State.SHADOW or r.state == RaiderModel.State.TELEGRAPH or r.state == RaiderModel.State.RAM:
			_check_raider_vs_wrecks(r)


func _follow_player(r: RaiderModel, pd: float, pv: float, delta: float, max_catch_up: float) -> void:
	var gap := (pd + r.offset_d) - r.d
	r.speed = maxf(0.0, pv + clampf(gap * 0.9, -6.0, max_catch_up))
	r.d += r.speed * delta


func _steer_to(r: RaiderModel, target_x: float, delta: float) -> void:
	r.x = move_toward(r.x, target_x, LATERAL_SPEED * delta)


## Pozycja obok gracza po stronie wroga: sąsiedni pas albo pobocze, gdy gracz jest na skraju.
func _flank_x(attack_side: int) -> float:
	var lanes := sim.lanes
	var player_lane := lanes.target_lane
	var lane := player_lane + attack_side
	if lane >= 0 and lane < lanes.lane_count:
		return lanes.lane_center(lane)
	return _shoulder_x(attack_side)


func _shoulder_x(attack_side: int) -> float:
	var lanes := sim.lanes
	return attack_side * (lanes.lane_width_m * (lanes.lane_count * 0.5) + 1.3)


func _overlaps_player(r: RaiderModel, px: float, pd: float) -> bool:
	return absf(r.x - px) < RAIDER_HALF_WIDTH + PLAYER_HALF_WIDTH and absf(r.d - pd) < 3.0


func _resolve_ram(r: RaiderModel, contact: bool) -> void:
	r.ram_hit_resolved = true
	r.attempts_left -= 1
	if not contact:
		rams_dodged += 1
		r.speed = maxf(0.0, r.speed - 5.0)
		r.set_state(RaiderModel.State.RETREAT)
		ram_resolved.emit(r, RamOutcome.DODGED, 0)
		return
	if shield >= SHIELD_RAM_COST:
		shield -= SHIELD_RAM_COST
		rams_blocked += 1
		r.x = r.ram_from_x
		_damage(r, 1, DestroyCause.SHOT)
		if r.is_alive():
			r.set_state(RaiderModel.State.SHADOW if r.attempts_left > 0 else RaiderModel.State.RETREAT)
		ram_resolved.emit(r, RamOutcome.BLOCKED, 0)
		return
	rams_taken += 1
	# Zepchnięcie: o pas od napastnika; na skraju trasy – uderzenie w pobocze.
	if not sim.lanes.request_change(-r.side):
		sim.vehicle.apply_impact(0.7)
	else:
		sim.vehicle.apply_impact(0.88)
	var stolen := sim.expedition.lose_scrap_to_raid()
	r.set_state(RaiderModel.State.RETREAT)
	ram_resolved.emit(r, RamOutcome.HIT, stolen)


## Gracz sam wjechał w wroga, zanim ten zaatakował: wróg obrywa i odpada.
func _counter_bump(r: RaiderModel) -> void:
	sim.vehicle.apply_impact(0.92)
	r.attempts_left = 0
	_damage(r, 1, DestroyCause.SHOT)
	if r.is_alive():
		r.x += r.side * 1.5
		r.set_state(RaiderModel.State.RETREAT)
	ram_resolved.emit(r, RamOutcome.COUNTER, 0)


func _check_raider_vs_wrecks(r: RaiderModel) -> void:
	for item in sim.items:
		if item.consumed or not item.is_wreck():
			continue
		if absf(item.distance_m - r.d) < sim.wreck_half_length_m + 1.2 and absf(sim.lane_x(item.lane) - r.x) < sim.wreck_half_width_m + RAIDER_HALF_WIDTH:
			_damage(r, r.hp, DestroyCause.WRECK)
			return


# --- Wieżyczka -------------------------------------------------------------------

## Wróg widoczny na ekranie (kamera jest ~7 m za pojazdem) – tylko w takiego celujemy,
## żeby gracz zawsze widział, z kim walczy.
const VISIBLE_BEHIND_M := 4.0


func _targetable(r: RaiderModel, pd: float) -> bool:
	return r.is_alive() and r.state != RaiderModel.State.RETREAT and r.d > pd - VISIBLE_BEHIND_M


## Cel: przy wychylonej gałce – wróg najbliżej kierunku gałki (stożek ~50°),
## przy puszczonej – najgroźniejszy (atakujący, potem najbliższy).
func current_target() -> RaiderModel:
	var px := sim.lanes.x_m
	var pd := sim.vehicle.distance_m
	var best: RaiderModel = null
	if aim.length() > 0.4:
		var dir := Vector2(aim.x, -aim.y).normalized()
		var best_dot := AIM_CONE_COS
		for r in raiders:
			if not _targetable(r, pd):
				continue
			var rel := Vector2(r.x - px, r.d - pd)
			if rel.length() < 0.5:
				continue
			var dot := dir.dot(rel.normalized())
			if dot > best_dot:
				best_dot = dot
				best = r
		return best
	var best_score := INF
	for r in raiders:
		if not _targetable(r, pd):
			continue
		var dist := Vector2(r.x - px, r.d - pd).length()
		if dist > 60.0:
			continue
		var score := dist - (100.0 if r.is_threatening() else 0.0)
		if score < best_score:
			best_score = score
			best = r
	return best


func _update_fire(delta: float) -> void:
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	var target := current_target()
	locked_target_id = target.id if target != null else -1
	if _fire_cooldown > 0.0:
		return
	if target != null and (fire_held or auto_fire):
		_fire_at(target)
		_fire_cooldown = fire_interval_s()
	elif fire_held:
		# Wolny strzał: bez wroga w celowniku pocisk leci tam, gdzie wskazuje gałka
		# (bez wychylenia – prosto przed siebie). Tak rozbija się wraki na swoim pasie.
		_spawn_projectile(aim_direction(), -1)
		_fire_cooldown = fire_interval_s()


## Kierunek celowania w układzie (bok, przód): gałka albo prosto, gdy nie jest wychylona.
func aim_direction() -> Vector2:
	if aim.length() > 0.4:
		return Vector2(aim.x, -aim.y).normalized()
	return Vector2(0.0, 1.0)


## Czy gracz aktywnie celuje albo strzela (widok pokazuje wtedy linię celownika).
func is_aiming() -> bool:
	return aim.length() > 0.4 or fire_held


## Punkt, w który patrzy wieżyczka, względem pojazdu (bok, przód); null = spoczynek.
func aim_point() -> Variant:
	var target := current_target()
	if target != null:
		return Vector2(target.x - sim.lanes.x_m, target.d - sim.vehicle.distance_m)
	if is_aiming():
		return aim_direction() * 20.0
	return null


func _fire_at(target: RaiderModel) -> void:
	var px := sim.lanes.x_m
	var pd := sim.vehicle.distance_m
	var pv := sim.vehicle.speed_mps
	var rel := Vector2(target.x - px, target.d - pd)
	var rel_vel := Vector2(target.lateral_velocity, target.speed - pv)
	var t := rel.length() / PROJECTILE_SPEED
	var aim_point := rel + rel_vel * t
	var dir := aim_point.normalized() if aim_point.length() > 0.01 else Vector2(0, 1)
	_spawn_projectile(dir, target.id)


func _spawn_projectile(dir: Vector2, target_id: int) -> void:
	var px := sim.lanes.x_m
	var pd := sim.vehicle.distance_m
	var pv := sim.vehicle.speed_mps
	var p := {
		"id": _next_projectile_id,
		"x": px, "d": pd + 0.3,
		"vx": dir.x * PROJECTILE_SPEED,
		"vd": dir.y * PROJECTILE_SPEED + pv,
		"age": 0.0,
		"target": target_id,
		"alive": true,
	}
	_next_projectile_id += 1
	projectiles.append(p)
	shot_fired.emit(p)


func _update_projectiles(delta: float) -> void:
	for p in projectiles:
		if not p["alive"]:
			continue
		var x0: float = p["x"]
		var d0: float = p["d"]
		var x1: float = x0 + float(p["vx"]) * delta
		var d1: float = d0 + float(p["vd"]) * delta
		p["x"] = x1
		p["d"] = d1
		p["age"] = float(p["age"]) + delta
		for r in raiders:
			if not r.is_alive():
				continue
			if _segment_point_distance(Vector2(x0, d0), Vector2(x1, d1), Vector2(r.x, r.d)) < HIT_RADIUS:
				p["alive"] = false
				r.hit_flash = 0.25
				raider_hit.emit(r)
				_damage(r, projectile_damage, DestroyCause.SHOT)
				break
		if p["alive"]:
			_hit_wrecks(p, Vector2(x0, d0), Vector2(x1, d1))
		if float(p["age"]) > PROJECTILE_MAX_AGE_S:
			p["alive"] = false


## Pocisk trafia we wrak: dwa trafienia rozbijają go i zwalniają pas.
func _hit_wrecks(p: Dictionary, from: Vector2, to: Vector2) -> void:
	for item in sim.items:
		if item.consumed or not item.is_wreck():
			continue
		var c := Vector2(sim.lane_x(item.lane), item.distance_m)
		if _segment_point_distance(from, to, c) < sim.wreck_half_width_m + 0.3:
			p["alive"] = false
			item.hp -= projectile_damage
			if item.hp <= 0:
				item.consumed = true
				wreck_destroyed.emit(item)
			return


func _damage(r: RaiderModel, amount: int, cause: int) -> void:
	if not r.is_alive():
		return
	r.hp -= amount
	if r.hp <= 0:
		r.hp = 0
		r.set_state(RaiderModel.State.DESTROYED)
		raiders_destroyed += 1
		sim.expedition.raiders_destroyed += 1
		var dropped := _drop_scrap(r)
		raider_destroyed.emit(r, dropped, cause)


## Zniszczony wróg gubi złom na pasach przed graczem – nagroda za walkę.
func _drop_scrap(r: RaiderModel) -> int:
	var count := 3 + r.variant
	var base_d := maxf(r.d, sim.vehicle.distance_m) + 14.0
	var lane := sim.lanes.target_lane
	var new_items: Array[TrackItem] = []
	for i in count:
		var item := TrackItem.new(1_000_000 + r.id * 16 + i, TrackItem.Kind.SCRAP, lane, base_d + i * 3.5, 1, 0)
		new_items.append(item)
	sim.add_items(new_items)
	return count


func _prune() -> void:
	var pd := sim.vehicle.distance_m
	var kept: Array[RaiderModel] = []
	for r in raiders:
		var gone := (r.state == RaiderModel.State.RETREAT and r.d < pd - SPAWN_BEHIND_M - 5.0)
		gone = gone or (r.state == RaiderModel.State.DESTROYED and r.timer > 3.0)
		if not gone:
			kept.append(r)
	raiders = kept
	var live: Array[Dictionary] = []
	for p in projectiles:
		if p["alive"]:
			live.append(p)
	projectiles = live


static func _segment_point_distance(a: Vector2, b: Vector2, p: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 1e-9:
		return a.distance_to(p)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return (a + ab * t).distance_to(p)
