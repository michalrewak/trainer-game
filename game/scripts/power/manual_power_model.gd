class_name ManualPowerModel
extends RefCounted
## Czysta logika symulowanej mocy (bez Input): trigger 0..1 -> 0..350 W z wygładzaniem,
## tempomat blokujący moc oraz kroki +/-10 W. Używana przez GamepadPowerSource,
## testowana bez sceny.
##
## Zasady:
## - Bez tempomatu cel = trigger * trigger_max_watts.
## - Tempomat (toggle_cruise) zapamiętuje bieżącą moc (zaokrągloną do 5 W).
##   Gdy jest włączony, cel = max(moc tempomatu, trigger) – można chwilowo docisnąć.
## - nudge(+1/-1) zmienia moc tempomatu o step_watts; jeśli tempomat był wyłączony,
##   najpierw go włącza na bieżącej mocy (tak działa klawiatura W/S i krzyżak góra/dół).
## - Moc wyjściowa dąży do celu wykładniczo ze stałą czasową smoothing_tau_s.

const LOCK_ROUNDING_W := 5.0

var trigger_max_watts := 350.0
var max_watts := 1000.0
var step_watts := 10.0
var smoothing_tau_s := 0.6
var cadence_tau_s := 1.5

var cruise_locked := false
var cruise_watts := 0.0

var _trigger := 0.0
var _power := 0.0
var _cadence := 0.0
var _time := 0.0


func toggle_cruise() -> void:
	if cruise_locked:
		cruise_locked = false
	else:
		cruise_locked = true
		cruise_watts = _round_lock(_power)


func nudge(steps: int) -> void:
	if not cruise_locked:
		cruise_locked = true
		cruise_watts = _round_lock(_power)
	cruise_watts = clampf(cruise_watts + steps * step_watts, 0.0, max_watts)


## Tryb cyfrowego triggera: przytrzymanie RT podnosi moc tempomatu (W/s), puszczenie trzyma.
func ramp(delta: float, watts_per_s: float) -> void:
	if not cruise_locked:
		cruise_locked = true
		cruise_watts = _round_lock(_power)
	cruise_watts = clampf(cruise_watts + watts_per_s * delta, 0.0, trigger_max_watts)


func get_target_watts() -> float:
	var from_trigger := _trigger * trigger_max_watts
	if cruise_locked:
		return maxf(cruise_watts, from_trigger)
	return from_trigger


func step(delta: float, trigger: float) -> void:
	if delta <= 0.0:
		return
	_time += delta
	_trigger = clampf(trigger, 0.0, 1.0)
	var target := get_target_watts()
	if smoothing_tau_s <= 0.0:
		_power = target
	else:
		_power += (target - _power) * (1.0 - exp(-delta / smoothing_tau_s))
		if absf(_power - target) < 0.05:
			_power = target
	var cadence_target := cadence_for_power(_power, _time)
	_cadence += (cadence_target - _cadence) * (1.0 - exp(-delta / cadence_tau_s))
	if cadence_target == 0.0 and _cadence < 1.0:
		_cadence = 0.0


func get_power() -> float:
	return _power


func get_cadence() -> float:
	return _cadence


## Wiarygodna kadencja dla danej mocy: 0 przy braku mocy, ~84 obr./min przy 200 W.
static func cadence_for_power(power_w: float, time_s: float = 0.0) -> float:
	if power_w < 5.0:
		return 0.0
	var base := clampf(72.0 + 0.06 * power_w, 60.0, 105.0)
	return base + 1.5 * sin(time_s * TAU / 7.0)


static func _round_lock(power_w: float) -> float:
	return snappedf(power_w, LOCK_ROUNDING_W)
