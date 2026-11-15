class_name LaneModel
extends RefCounted
## Pasy ruchu: docelowy pas i płynna pozycja boczna pojazdu (w metrach, 0 = środek).
## Zmiana pasa: szybki start i miękkie dojście (ok. 0,3 s na jeden pas).

var lane_count := 3
var lane_width_m := 3.6
var max_lateral_speed_mps := 16.0
var settle_tau_s := 0.08

var target_lane := 1
var x_m := 0.0
var lateral_velocity_mps := 0.0


func _init(p_lane_count: int = 3, p_lane_width_m: float = 3.6) -> void:
	lane_count = p_lane_count
	lane_width_m = p_lane_width_m
	target_lane = floori((lane_count - 1) / 2.0)
	x_m = lane_center(target_lane)


func lane_center(lane: int) -> float:
	return (lane - (lane_count - 1) * 0.5) * lane_width_m


## Zwraca true, jeśli pas docelowy się zmienił (na krawędzi trasy – false).
func request_change(direction: int) -> bool:
	var new_lane := clampi(target_lane + direction, 0, lane_count - 1)
	if new_lane == target_lane:
		return false
	target_lane = new_lane
	return true


func step(delta: float) -> void:
	if delta <= 0.0:
		return
	var target_x := lane_center(target_lane)
	var gap := target_x - x_m
	var speed := minf(max_lateral_speed_mps, absf(gap) / settle_tau_s)
	var new_x := move_toward(x_m, target_x, speed * delta)
	if absf(target_x - new_x) < 0.005:
		new_x = target_x
	lateral_velocity_mps = (new_x - x_m) / delta
	x_m = new_x


## Pas najbliższy bieżącej pozycji bocznej.
func current_lane() -> int:
	var lane := roundi(x_m / lane_width_m + (lane_count - 1) * 0.5)
	return clampi(lane, 0, lane_count - 1)


func is_changing() -> bool:
	return absf(lane_center(target_lane) - x_m) > 0.01
