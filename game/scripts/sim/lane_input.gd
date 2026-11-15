class_name LaneInput
extends RefCounted
## Zamienia „siłę” akcji lane_left / lane_right (krzyżak = 1.0, gałka = 0..1)
## na pojedyncze polecenia zmiany pasa: -1, 0 albo +1.
## Histereza (wciśnięcie > 0.55, puszczenie < 0.3) chroni przed drganiem gałki,
## przytrzymanie powtarza zmianę pasa.

var press_threshold := 0.55
var release_threshold := 0.3
var repeat_delay_s := 0.35
var repeat_interval_s := 0.25

var _held := 0
var _hold_time := 0.0
var _next_repeat := 0.0


func update(delta: float, left_strength: float, right_strength: float) -> int:
	var dir := 0
	if left_strength > press_threshold and left_strength >= right_strength:
		dir = -1
	elif right_strength > press_threshold:
		dir = 1
	elif _held == -1 and left_strength > release_threshold:
		dir = -1
	elif _held == 1 and right_strength > release_threshold:
		dir = 1

	if dir == 0:
		_held = 0
		return 0
	if dir != _held:
		_held = dir
		_hold_time = 0.0
		_next_repeat = repeat_delay_s
		return dir
	_hold_time += delta
	if _hold_time >= _next_repeat:
		_next_repeat += repeat_interval_s
		return dir
	return 0
