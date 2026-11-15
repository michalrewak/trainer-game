class_name ChallengeDirector
extends RefCounted
## Tryb wolny (etap 6): gra sama proponuje wyzwania i dyktuje opór trenażera.
## - UCIECZKA: gang w pościgu – utrzymaj moc (ERG) przez minutę, inaczej dogonią.
## - PODJAZD: nachylenie (symulacja trenażera) – utrzymaj moc na wzniesieniu.
## - SPRINT: krótki zryw za ciężarówką z zaopatrzeniem.
## Cykl: IDLE -> ANNOUNCE (odliczanie) -> ACTIVE -> RESULT -> IDLE. Czysta logika.

signal announced(challenge: Dictionary)
signal started(challenge: Dictionary)
signal finished(challenge: Dictionary, success: bool)

enum Kind { ESCAPE, CLIMB, SPRINT }
enum Phase { IDLE, ANNOUNCE, ACTIVE, RESULT }

const ANNOUNCE_S := 6.0
const RESULT_S := 4.0
## Widełki wyzwania: liczy się czas w zakresie celu ±8% – za mocno też jest błędem.
const BAND_TOL := TargetBand.CHALLENGE_TOL
const SUCCESS_RATIO := 0.8

const DEFS := {
	Kind.ESCAPE: {"name": "UCIECZKA", "duration": 60.0, "ftp": 0.95, "grade": 0.0, "reward_scrap": 30, "reward_fuel": 0,
		"brief": "Gang w pościgu! Utrzymaj moc, aż zgubisz ogon."},
	Kind.CLIMB: {"name": "PODJAZD", "duration": 90.0, "ftp": 0.88, "grade": 5.0, "reward_scrap": 10, "reward_fuel": 2,
		"brief": "Wzniesienie 5%: trenażer stawia opór, trzymaj tempo do szczytu."},
	Kind.SPRINT: {"name": "SPRINT", "duration": 25.0, "ftp": 1.3, "grade": 0.0, "reward_scrap": 40, "reward_fuel": 0,
		"brief": "Ciężarówka z zaopatrzeniem! Krótki zryw, a ładunek twój."},
}

var enabled := true
var ftp_w := 200.0
var first_after_s := 120.0
var gap_s := 200.0

var phase: Phase = Phase.IDLE
var current: Dictionary = {}
var phase_time := 0.0
var hold_time := 0.0
var energy_j := 0.0
var completed := 0
var failed := 0

var _next_at_s := 0.0
var _order: Array[Kind] = [Kind.CLIMB, Kind.ESCAPE, Kind.SPRINT]
var _index := 0


func _init(p_ftp_w: float = 200.0) -> void:
	ftp_w = p_ftp_w
	_next_at_s = first_after_s


func set_first_after(seconds: float) -> void:
	first_after_s = seconds
	_next_at_s = seconds


func is_active() -> bool:
	return phase == Phase.ACTIVE


func target_w() -> float:
	if current.is_empty():
		return 0.0
	return roundf(ftp_w * float(current["ftp"]) / 5.0) * 5.0


## Nachylenie w procentach dyktowane trenażerowi (tylko w czasie aktywnego podjazdu).
func grade_percent() -> float:
	return float(current.get("grade", 0.0)) if phase == Phase.ACTIVE else 0.0


func time_left_s() -> float:
	match phase:
		Phase.ANNOUNCE:
			return ANNOUNCE_S - phase_time
		Phase.ACTIVE:
			return float(current["duration"]) - phase_time
		Phase.RESULT:
			return RESULT_S - phase_time
	return 0.0


## Odsetek dotychczasowego czasu wyzwania w strefie mocy (0..1).
func hold_ratio() -> float:
	return hold_time / phase_time if phase == Phase.ACTIVE and phase_time > 0.0 else 0.0


func step(delta: float, elapsed_s: float, time_left_in_run_s: float, power_w: float) -> void:
	if not enabled or delta <= 0.0:
		return
	phase_time += delta
	match phase:
		Phase.IDLE:
			if elapsed_s >= _next_at_s and time_left_in_run_s > 30.0:
				_announce(time_left_in_run_s)
		Phase.ANNOUNCE:
			if phase_time >= ANNOUNCE_S:
				phase = Phase.ACTIVE
				phase_time = 0.0
				hold_time = 0.0
				energy_j = 0.0
				started.emit(current)
		Phase.ACTIVE:
			energy_j += power_w * delta
			if TargetBand.is_in_band(power_w, target_w(), BAND_TOL, BAND_TOL):
				hold_time += delta
			if phase_time >= float(current["duration"]):
				var ok := _evaluate()
				if ok:
					completed += 1
				else:
					failed += 1
				current["success"] = ok
				phase = Phase.RESULT
				phase_time = 0.0
				finished.emit(current, ok)
		Phase.RESULT:
			if phase_time >= RESULT_S:
				phase = Phase.IDLE
				phase_time = 0.0
				_next_at_s = elapsed_s + gap_s


func _announce(time_left_in_run_s: float) -> void:
	var kind: Kind = _order[_index % _order.size()]
	_index += 1
	current = (DEFS[kind] as Dictionary).duplicate()
	current["kind"] = kind
	# Wyzwanie nie może wyjść poza koniec wyprawy.
	current["duration"] = minf(float(current["duration"]), maxf(15.0, time_left_in_run_s - ANNOUNCE_S - 5.0))
	phase = Phase.ANNOUNCE
	phase_time = 0.0
	announced.emit(current)


func _evaluate() -> bool:
	if int(current["kind"]) == Kind.SPRINT:
		# Sprint to zryw na maksa – liczy się tylko, czy średnia sięgnęła dolnej granicy.
		var avg := energy_j / maxf(phase_time, 0.001)
		return avg >= TargetBand.low(target_w(), BAND_TOL)
	return phase_time > 0.0 and hold_time / phase_time >= SUCCESS_RATIO
