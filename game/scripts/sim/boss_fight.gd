class_name BossFight
extends RefCounted
## Walka z bossem kampanii – machiną Barona Smalca. Trening ma być zrealizowany w 100%,
## więc walka niczego nie wymaga poza samym treningiem: każdy ciężki interwał planu to
## NATARCIE, a każda sekunda natarcia z mocą w widełkach zadaje machinie obrażenia.
## Między natarciami (regeneracja) machina odjeżdża do przodu. Kto utrzyma widełki przez
## 85% czasu natarć, rozbija ją przed końcem planu; słabszy wynik to machina ranna, która
## ucieka – i mniejszy łup. Kierować ani strzelać nie trzeba (pole bezpieczne), działko
## pali samo. Czysta logika; machinę rysuje ConvoyPartView (ciągnik z tronem Barona).

signal round_started(index: int)
signal round_ended(index: int)
signal destroyed

## Taki odsetek czasu natarć w widełkach wystarcza, żeby rozbić machinę.
const KILL_RATIO := 0.85
const NEAR_M := 24.0
const FAR_M := 78.0
const REWARD_SCRAP := 400
const REWARD_FUEL := 3
const REWARD_CREW := 2

var active := false
var boss_name := ""
## Wytrzymałość machiny 1..0.
var hp := 1.0
var defeated := false
var rounds := 0
var round_index := -1
var boss: RaiderModel

var _sim_ref: WeakRef
var _hard_total_s := 1.0
var _gap := FAR_M
var _in_round := false


## hard_total_s: łączny czas ciężkich kroków planu; p_rounds: liczba natarć (ciężkich bloków).
func setup(sim: RunSimulation, p_name: String, hard_total_s: float, p_rounds: int) -> void:
	_sim_ref = weakref(sim)
	boss_name = p_name
	_hard_total_s = maxf(hard_total_s, 1.0)
	rounds = p_rounds
	boss = sim.combat.add_convoy_part(RaiderModel.Part.TRACTOR, 100, 2)
	boss.invulnerable = true
	boss.half_length = 3.2
	boss.hit_radius = 1.1
	boss.exposed = false
	active = true
	_place(sim, false)


func step(delta: float, hard_now: bool, in_band: bool) -> void:
	var sim := _sim_ref.get_ref() as RunSimulation if _sim_ref != null else null
	if not active or sim == null or delta <= 0.0:
		return
	if hard_now != _in_round:
		_in_round = hard_now
		if hard_now:
			round_index += 1
			round_started.emit(round_index)
		else:
			round_ended.emit(round_index)
	if defeated:
		return
	_gap = move_toward(_gap, NEAR_M if hard_now else FAR_M, 14.0 * delta)
	_place(sim, hard_now)
	if hard_now and in_band:
		hp = maxf(0.0, hp - delta / (_hard_total_s * KILL_RATIO))
		boss.hp = maxi(1, ceili(hp * 100.0))
		if hp <= 0.0:
			_destroy(sim)


## Łup za machinę, która uciekła ranna: połowa nagrody za zadane obrażenia.
func partial_scrap() -> int:
	return 0 if defeated else roundi(REWARD_SCRAP * (1.0 - hp) * 0.5)


func _place(sim: RunSimulation, hard_now: bool) -> void:
	boss.d = sim.vehicle.distance_m + _gap + 4.0
	boss.x = sim.lane_x(floori((sim.lanes.lane_count - 1) / 2.0))
	boss.speed = sim.vehicle.speed_mps
	boss.braking = not hard_now
	# Działko sięga machiny tylko w natarciu, z bliska.
	boss.exposed = hard_now and _gap < 60.0


func _destroy(sim: RunSimulation) -> void:
	defeated = true
	boss.exposed = false
	boss.hp = 0
	boss.set_state(RaiderModel.State.DESTROYED)
	sim.expedition.add_scrap(REWARD_SCRAP)
	sim.expedition.add_fuel(REWARD_FUEL)
	sim.expedition.pedalers_freed += REWARD_CREW
	destroyed.emit()
