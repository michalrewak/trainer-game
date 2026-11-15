class_name GamepadPowerSource
extends PowerSource
## Symulacja mocy z pada (etapy 1–4, zanim podłączymy trenażer).
## - prawy trigger (akcja power_trigger, oś 5) = 0–350 W z wygładzaniem,
## - LB (akcja cruise_toggle) blokuje bieżącą moc – tempomat,
## - W/S i krzyżak góra/dół (power_up / power_down) zmieniają moc o 10 W, przytrzymanie
##   powtarza krok; przy wciśniętym lewo/prawo góra/dół jest ignorowane (skosy krzyżaka).
## Pady GameSir po Bluetooth w trybie Switch/Android mają cyfrowy trigger (tylko 0 albo 1):
## wykrywamy to i wtedy przytrzymanie RT podnosi moc tempomatu o 40 W/s.
## Cała arytmetyka mocy siedzi w ManualPowerModel – tu tylko czytamy Input.

const ACTION_TRIGGER := &"power_trigger"
const ACTION_CRUISE := &"cruise_toggle"
const ACTION_UP := &"power_up"
const ACTION_DOWN := &"power_down"

const REPEAT_DELAY_S := 0.4
const REPEAT_INTERVAL_S := 0.12
## Pasmo triggera: martwa strefa na dole i „pełne” 350 W, zanim trigger dojdzie do 1.0.
const TRIGGER_LOW := 0.04
const TRIGGER_HIGH := 0.97
const DIGITAL_RAMP_W_PER_S := 40.0

var model := ManualPowerModel.new()
var trigger_is_digital := false

var _repeat_timers := {ACTION_UP: 0.0, ACTION_DOWN: 0.0}
var _seen_analog := false
var _full_presses := 0
var _was_released := true
var _warned_unknown := false
var _erg_active := false
var _pre_erg_locked := false
var _pre_erg_watts := 0.0


func update(delta: float) -> void:
	if Input.is_action_just_pressed(ACTION_CRUISE):
		model.toggle_cruise()
	if not _lane_held():
		_handle_step(ACTION_UP, 1, delta)
		_handle_step(ACTION_DOWN, -1, delta)
	var raw := _read_trigger_raw()
	_detect_digital(raw)
	if trigger_is_digital:
		if raw > 0.5:
			model.ramp(delta, DIGITAL_RAMP_W_PER_S)
		model.step(delta, 0.0)
	else:
		model.step(delta, band(raw))


func get_power_watts() -> float:
	return model.get_power()


func get_cadence() -> float:
	return model.get_cadence()


func get_label() -> String:
	return "PAD"


## Symulacja ERG na padzie (etap 4): tempomat sam ustawia się na moc z planu treningu,
## tak jak zrobi to trenażer w trybie ERG. Trigger nadal może chwilowo dodać mocy,
## a krzyżak ↑/↓ – skorygować o ±10 W do następnego kroku planu.
func set_erg_target(watts: float) -> void:
	if watts <= 0.0:
		# Koniec ERG: wracamy do stanu tempomatu sprzed ERG.
		if _erg_active:
			_erg_active = false
			model.cruise_locked = _pre_erg_locked
			model.cruise_watts = _pre_erg_watts
		return
	if not _erg_active:
		_erg_active = true
		_pre_erg_locked = model.cruise_locked
		_pre_erg_watts = model.cruise_watts
	model.cruise_locked = true
	model.cruise_watts = clampf(roundf(watts), 0.0, model.max_watts)


func get_erg_target() -> float:
	return model.cruise_watts if _erg_active else 0.0


func get_hint() -> String:
	if _erg_active:
		return "ERG %d W (symulacja)" % roundi(model.cruise_watts)
	if model.cruise_locked:
		return "TEMPOMAT %d W" % roundi(model.cruise_watts)
	return ""


## Mapuje surową wartość triggera na 0..1 z pasmem TRIGGER_LOW..TRIGGER_HIGH.
static func band(raw: float) -> float:
	return clampf(inverse_lerp(TRIGGER_LOW, TRIGGER_HIGH, raw), 0.0, 1.0)


func _read_trigger_raw() -> float:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return 0.0
	var any_known := false
	for id in pads:
		if Input.is_joy_known(id):
			any_known = true
	if not any_known:
		# Nierozpoznany pad: osie przychodzą „na surowo” (-1..1, dowolne indeksy) – nie ufamy im.
		if not _warned_unknown:
			_warned_unknown = true
			push_notice("Pad nierozpoznany – moc ustawiaj krzyżakiem ↑↓ albo W/S")
		return 0.0
	return Input.get_action_raw_strength(ACTION_TRIGGER)


func _detect_digital(raw: float) -> void:
	if trigger_is_digital or _seen_analog:
		return
	if raw > 0.02 and raw < 0.98:
		_seen_analog = true
		return
	if raw >= 0.98 and _was_released:
		_full_presses += 1
		_was_released = false
	elif raw <= 0.02:
		_was_released = true
	if _full_presses >= 3:
		trigger_is_digital = true
		push_notice("Trigger pada jest cyfrowy: trzymaj RT, by dodawać moc; krzyżak ↑↓ = ±10 W")


func _lane_held() -> bool:
	return Input.get_action_raw_strength(&"lane_left") > 0.5 or Input.get_action_raw_strength(&"lane_right") > 0.5


func _handle_step(action: StringName, direction: int, delta: float) -> void:
	if Input.is_action_just_pressed(action):
		model.nudge(direction)
		_repeat_timers[action] = -REPEAT_DELAY_S
	elif Input.is_action_pressed(action):
		_repeat_timers[action] += delta
		while _repeat_timers[action] >= REPEAT_INTERVAL_S:
			_repeat_timers[action] -= REPEAT_INTERVAL_S
			model.nudge(direction)
