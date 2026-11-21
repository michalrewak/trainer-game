class_name RaidDirector
extends RefCounted
## Napady na osady (docs/swiat.md, filar „decyzje na trasie i zwiad”). Czysta logika.
##
## Cykl: IDLE -> SCOUTING (zwiad: 500 m przed zjazdem gracz widzi łup, obronę i koszt
## wysiłku) -> na zjeździe decyzja pasem: skrajny pas od strony osady = napad, każdy inny
## = jazda dalej bez kary -> RAIDING: podjazd pod ostrzałem wież, brama (rozstrzelać,
## staranować albo wyłamać z utratą prędkości), plądrowanie (gęsty złom, straż) ->
## ucieczka: łup jedzie na doczepionej przyczepie i trzeba go dowieźć (ESCAPING) – każde
## udane taranowanie przez pościg wysypuje część ładunku. Łup jest tym większy, im dłużej
## moc była w widełkach.
## Przegrana to „odparcie” (brak łupu z osady), nigdy koniec jazdy.

signal scouted(settlement: Dictionary)
signal skipped(settlement: Dictionary)
signal started(settlement: Dictionary)
signal shell_fired(shell: Dictionary)
signal shell_landed(shell: Dictionary, hit: bool, blocked: bool, scrap_lost: int)
signal gate_broken(how: int)
signal looting_started(settlement: Dictionary)
signal escape_started(settlement: Dictionary, loot_scrap: int, loot_fuel: int)
signal loot_spilled(scrap_lost: int)
signal finished(settlement: Dictionary, loot_scrap: int, loot_fuel: int, repelled: bool)

enum State { IDLE, SCOUTING, RAIDING, ESCAPING }
enum Phase { APPROACH, LOOT }
enum GateBreak { SHOT, RAM, CRASH }

const SCOUT_M := 500.0
const APPROACH_M := 260.0
const SHELL_FLIGHT_S := 1.7
const SHELL_CAPACITOR_COST := 0.3
const BAND_TOL := TargetBand.CHALLENGE_TOL
## Jak długo trzeba wieźć łup, zanim będzie bezpieczny, i ile wysypuje się przy taranowaniu.
const ESCAPE_S := 40.0
const SPILL_FRACTION := 0.25

## Rodzaje osad: im bogatsza, tym mocniej broniona i dłuższy, cięższy wysiłek.
const TIERS: Array[Dictionary] = [
	{"name": "Obóz zbieraczy", "stars": 1, "towers": 1, "guards": 0, "gate_hp": 4, "loot_scrap": 45, "loot_fuel": 0, "duration_s": 60.0, "ftp": 0.9},
	{"name": "Osada gangu", "stars": 2, "towers": 2, "guards": 2, "gate_hp": 7, "loot_scrap": 100, "loot_fuel": 1, "duration_s": 120.0, "ftp": 1.0},
	{"name": "Twierdza Tłustych", "stars": 3, "towers": 3, "guards": 3, "gate_hp": 10, "loot_scrap": 180, "loot_fuel": 3, "duration_s": 180.0, "ftp": 1.05},
]

var enabled := false
var ftp_w := 200.0
## Dystans do pierwszego zjazdu i odstęp między kolejnymi osadami.
var first_fork_m := 1100.0
var gap_m := 1700.0

var state: State = State.IDLE
var phase: Phase = Phase.APPROACH
var current: Dictionary = {}
var shells: Array[Dictionary] = []
var gate_d := 0.0
var gate_hp := 0
var gate_hp_max := 0
var gate_shot := false
var raid_time := 0.0
var hold_time := 0.0
var raids_done := 0
var pending_scrap := 0
var pending_fuel := 0
var escape_left_s := 0.0

var _sim_ref: WeakRef
var _rng := RandomNumberGenerator.new()
var _next_fork_m := 0.0
var _shell_timer := 0.0
var _next_shell_id := 1
var _saved_gaps: Dictionary = {}


func _init(sim: RunSimulation, seed_value: int = 0) -> void:
	_sim_ref = weakref(sim)
	_rng.seed = seed_value + 5501
	_next_fork_m = first_fork_m
	sim.combat.ram_resolved.connect(_on_ram_resolved)


func set_first_fork(distance_m: float) -> void:
	first_fork_m = distance_m
	_next_fork_m = distance_m


func is_raiding() -> bool:
	return state == State.RAIDING


## Czy pojazd ciągnie przyczepę z łupem (zadanie „dowieź łup”).
func is_towing() -> bool:
	return state == State.ESCAPING


func target_w() -> float:
	if current.is_empty():
		return 0.0
	return roundf(ftp_w * float(current["ftp"]) / 5.0) * 5.0


func time_left_s() -> float:
	return maxf(0.0, float(current.get("duration_s", 0.0)) - raid_time) if is_raiding() else 0.0


func hold_ratio() -> float:
	return hold_time / raid_time if raid_time > 0.0 else 0.0


## Dystans do zjazdu (zwiad) albo do bramy (podjazd); 0 poza tymi fazami.
func distance_to_next_m() -> float:
	var sim := _sim()
	if state == State.SCOUTING:
		return maxf(0.0, float(current["fork_d"]) - sim.vehicle.distance_m)
	if is_raiding() and phase == Phase.APPROACH:
		return maxf(0.0, gate_d - sim.vehicle.distance_m)
	return 0.0


## Pas, którym trzeba jechać na zjeździe, żeby napaść na osadę.
func exit_lane() -> int:
	var sim := _sim()
	return 0 if int(current.get("side", 1)) < 0 else sim.lanes.lane_count - 1


func step(delta: float, power_w: float) -> void:
	var sim := _sim()
	if sim == null or delta <= 0.0:
		return
	match state:
		State.IDLE:
			_maybe_scout(sim)
		State.SCOUTING:
			if sim.vehicle.distance_m >= float(current["fork_d"]):
				if sim.lanes.target_lane == exit_lane():
					_start(sim)
				else:
					_skip(sim)
		State.RAIDING:
			_raid(sim, delta, power_w)
		State.ESCAPING:
			escape_left_s -= delta
			if escape_left_s <= 0.0 or sim.expedition.finished:
				_bank(sim)


## Pocisk z wieżyczki gracza trafia w bramę.
func damage_gate(amount: int) -> void:
	if not is_raiding() or phase != Phase.APPROACH or gate_hp <= 0:
		return
	gate_hp = maxi(0, gate_hp - amount)
	if gate_hp == 0:
		gate_shot = true
		gate_broken.emit(GateBreak.SHOT)


func _maybe_scout(sim: RunSimulation) -> void:
	if not enabled or sim.expedition.finished or sim.safe_zone:
		return
	var d := sim.vehicle.distance_m
	if sim.convoys.is_active():
		# Konwój ma pierwszeństwo: rozwidlenie odsuwa się za pole walki.
		_next_fork_m = maxf(_next_fork_m, d + SCOUT_M + 150.0)
		return
	if d < _next_fork_m - SCOUT_M or sim.challenges.phase != ChallengeDirector.Phase.IDLE:
		return
	# Osada musi zmieścić się w pozostałym czasie wyprawy (dojazd ~1 min + napad).
	var budget := sim.expedition.time_left_s() - 75.0
	var best := -1
	var max_tier := 0 if sim.expedition.progress() < 0.2 else (1 if sim.expedition.progress() < 0.55 else 2)
	for i in range(mini(max_tier, TIERS.size() - 1), -1, -1):
		if float(TIERS[i]["duration_s"]) <= budget:
			best = i
			break
	if best < 0:
		_next_fork_m = d + gap_m
		return
	# Losowo trochę słabsza osada, żeby nie zawsze najcięższa.
	if best > 0 and _rng.randf() < 0.35:
		best -= 1
	current = TIERS[best].duplicate()
	current["tier"] = best
	current["side"] = -1 if _rng.randf() < 0.5 else 1
	current["fork_d"] = d + SCOUT_M
	state = State.SCOUTING
	scouted.emit(current)


func _skip(sim: RunSimulation) -> void:
	state = State.IDLE
	_next_fork_m = sim.vehicle.distance_m + gap_m
	skipped.emit(current)


func _start(sim: RunSimulation) -> void:
	state = State.RAIDING
	phase = Phase.APPROACH
	gate_d = float(current["fork_d"]) + APPROACH_M
	gate_hp_max = int(current["gate_hp"])
	gate_hp = gate_hp_max
	gate_shot = false
	raid_time = 0.0
	hold_time = 0.0
	_shell_timer = 2.0
	shells.clear()
	# Za bramą leży łup: złom i paliwo trzy razy gęściej (generator pracuje z wyprzedzeniem).
	var g := sim.generator
	_saved_gaps = {"easy": g.scrap_gap_easy_m, "hard": g.scrap_gap_hard_m, "fuel": g.fuel_every_m}
	g.scrap_gap_easy_m /= 3.0
	g.scrap_gap_hard_m /= 3.0
	g.fuel_every_m /= 3.0
	started.emit(current)


func _raid(sim: RunSimulation, delta: float, power_w: float) -> void:
	raid_time += delta
	if TargetBand.is_in_band(power_w, target_w(), BAND_TOL, BAND_TOL):
		hold_time += delta
	_update_shells(sim, delta)
	if phase == Phase.APPROACH and sim.vehicle.distance_m >= gate_d - 2.0:
		_enter_town(sim)
	if raid_time >= float(current["duration_s"]) or sim.expedition.finished:
		_finish(sim)


func _update_shells(sim: RunSimulation, delta: float) -> void:
	var towers := int(current["towers"])
	_shell_timer -= delta
	if _shell_timer <= 0.0 and towers > 0:
		var interval := maxf(1.2, 3.2 / towers)
		_shell_timer = interval if phase == Phase.APPROACH else interval * 2.2
		var shell := {
			"id": _next_shell_id,
			"lane": sim.lanes.target_lane,
			"d": sim.vehicle.distance_m + maxf(sim.vehicle.speed_mps, 6.0) * SHELL_FLIGHT_S,
			"t_left": SHELL_FLIGHT_S,
		}
		_next_shell_id += 1
		shells.append(shell)
		shell_fired.emit(shell)
	for i in range(shells.size() - 1, -1, -1):
		var s: Dictionary = shells[i]
		s["t_left"] = float(s["t_left"]) - delta
		if float(s["t_left"]) > 0.0:
			continue
		shells.remove_at(i)
		var hit := absf(sim.lane_x(int(s["lane"])) - sim.lanes.x_m) < 1.7 and absf(float(s["d"]) - sim.vehicle.distance_m) < 4.5
		var blocked := false
		var lost := 0
		if hit:
			if sim.combat.capacitor >= SHELL_CAPACITOR_COST:
				sim.combat.capacitor -= SHELL_CAPACITOR_COST
				blocked = true
			else:
				sim.vehicle.apply_impact(0.85)
				lost = sim.expedition.lose_scrap_to_shell()
		shell_landed.emit(s, hit, blocked, lost)


func _enter_town(sim: RunSimulation) -> void:
	if gate_hp > 0:
		if sim.ram_ready():
			sim.ram_left_s = sim.ram_cooldown_s
			if not sim.ram_keeps_speed:
				sim.vehicle.apply_impact(0.75)
			gate_broken.emit(GateBreak.RAM)
		else:
			# Wyłom na siłę: brama puszcza, ale kosztuje to rozpęd.
			sim.vehicle.apply_impact(0.4)
			gate_broken.emit(GateBreak.CRASH)
		gate_hp = 0
	phase = Phase.LOOT
	for i in int(current["guards"]):
		sim.combat.spawn_raider(-1 if i % 2 == 0 else 1)
	looting_started.emit(current)


func _finish(sim: RunSimulation) -> void:
	var g := sim.generator
	if not _saved_gaps.is_empty():
		g.scrap_gap_easy_m = float(_saved_gaps["easy"])
		g.scrap_gap_hard_m = float(_saved_gaps["hard"])
		g.fuel_every_m = float(_saved_gaps["fuel"])
		_saved_gaps = {}
	shells.clear()
	if phase == Phase.APPROACH:
		# Nie dojechałeś do bramy przed końcem – odparty, bez łupu.
		state = State.IDLE
		_next_fork_m = sim.vehicle.distance_m + gap_m
		finished.emit(current, 0, 0, true)
		return
	# Skarbiec osady: połowa pewna, druga połowa za moc trzymaną w widełkach.
	var mult := 0.5 + 0.5 * clampf(hold_ratio(), 0.0, 1.0) + (0.1 if gate_shot else 0.0)
	pending_scrap = roundi(float(current["loot_scrap"]) * mult)
	pending_fuel = roundi(float(current["loot_fuel"]) * mult)
	# Ucieczka: łup jedzie na przyczepie, a z bogatszych osad rusza pościg.
	state = State.ESCAPING
	escape_left_s = ESCAPE_S
	if sim.combat.enabled:
		for i in int(current["tier"]):
			sim.combat.spawn_raider(-1 if i % 2 == 0 else 1)
	escape_started.emit(current, pending_scrap, pending_fuel)
	if sim.expedition.finished:
		_bank(sim)


## Łup dowieziony: trafia do zebranych w tej wyprawie.
func _bank(sim: RunSimulation) -> void:
	sim.expedition.add_scrap(pending_scrap)
	sim.expedition.add_fuel(pending_fuel)
	sim.expedition.raids_done += 1
	raids_done += 1
	var scrap := pending_scrap
	var fuel := pending_fuel
	pending_scrap = 0
	pending_fuel = 0
	state = State.IDLE
	_next_fork_m = sim.vehicle.distance_m + gap_m
	finished.emit(current, scrap, fuel, false)


## Pościg staranował pojazd z przyczepą: część ładunku wysypuje się na drogę.
func _on_ram_resolved(_raider: RaiderModel, outcome: int, _lost: int) -> void:
	if state != State.ESCAPING or outcome != CombatModel.RamOutcome.HIT:
		return
	var spilled := ceili(pending_scrap * SPILL_FRACTION)
	pending_scrap -= spilled
	loot_spilled.emit(spilled)


func _sim() -> RunSimulation:
	return _sim_ref.get_ref() as RunSimulation
