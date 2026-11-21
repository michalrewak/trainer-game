class_name LaneModel
extends RefCounted
## Pozycja boczna pojazdu na jezdni (w metrach, 0 = środek) – dwa sposoby kierowania naraz:
##
## - PŁYNNIE (lewa gałka): wychylenie nadaje prędkość boczną, pojazd może jechać w dowolnym
##   miejscu jezdni, także między pasami. Po puszczeniu gałki WSPOMAGANIE łagodnie dociąga
##   go do środka najbliższego pasa (można je wyłączyć – wtedy pojazd zostaje tam, gdzie był).
## - SKOKIEM (krzyżak, klawisze, autopilot): request_change przestawia o cały pas; szybki
##   start i miękkie dojście (ok. 0,3 s na jeden pas).
##
## target_lane to zawsze „pas, na którym jest gracz” (przy jeździe płynnej – najbliższy),
## więc reszta gry (gangi, zjazdy, konwój) nie musi wiedzieć, jak gracz kieruje.

var lane_count := 3
var lane_width_m := 3.6
var max_lateral_speed_mps := 16.0
var settle_tau_s := 0.08

## Jazda płynna: prędkość boczna przy pełnym wychyleniu gałki i czas reakcji.
var steer_speed_mps := 9.0
var steer_response_s := 0.07
## Ile poza środek skrajnego pasa wolno zjechać (do krawędzi jezdni).
var edge_margin_m := 1.0
## Wspomaganie: po puszczeniu gałki dociąga do najbliższego pasa z tą prędkością.
var assist_enabled := true
var assist_speed_mps := 5.5
var assist_tau_s := 0.16

var target_lane := 1
var x_m := 0.0
var lateral_velocity_mps := 0.0
## Czy pojazd jest prowadzony gałką (albo właśnie dociągany przez wspomaganie).
var free_steering := false
## Ustawiane na jedną klatkę, gdy gracz puszcza gałkę – symulacja może wtedy podpowiedzieć
## wspomaganiu lepszy pas (np. bez wraku).
var assist_started := false

var _steer_input := 0.0
var _steer_velocity := 0.0
var _was_steering := false


func _init(p_lane_count: int = 3, p_lane_width_m: float = 3.6) -> void:
	lane_count = p_lane_count
	lane_width_m = p_lane_width_m
	target_lane = floori((lane_count - 1) / 2.0)
	x_m = lane_center(target_lane)


func lane_center(lane: int) -> float:
	return (lane - (lane_count - 1) * 0.5) * lane_width_m


func min_x() -> float:
	return lane_center(0) - edge_margin_m


func max_x() -> float:
	return lane_center(lane_count - 1) + edge_margin_m


## Wychylenie gałki -1..1 (już po strefie martwej); 0 = gałka puszczona.
func steer(input: float) -> void:
	_steer_input = clampf(input, -1.0, 1.0)


func is_steering() -> bool:
	return absf(_steer_input) > 0.0


## Skok o pas. Zwraca true, jeśli pas docelowy się zmienił (na krawędzi trasy – false).
func request_change(direction: int) -> bool:
	var new_lane := clampi(target_lane + direction, 0, lane_count - 1)
	if new_lane == target_lane:
		return false
	target_lane = new_lane
	free_steering = false
	_was_steering = false
	return true


func step(delta: float) -> void:
	if delta <= 0.0:
		return
	assist_started = false
	if is_steering():
		_was_steering = true
		free_steering = true
		_steer_velocity = lerpf(_steer_velocity, _steer_input * steer_speed_mps, 1.0 - exp(-delta / steer_response_s))
		var steered := clampf(x_m + _steer_velocity * delta, min_x(), max_x())
		lateral_velocity_mps = (steered - x_m) / delta
		x_m = steered
		target_lane = current_lane()
		return
	if _was_steering:
		_was_steering = false
		assist_started = true
		target_lane = current_lane()
	_steer_velocity = 0.0
	if free_steering and not assist_enabled:
		# Bez wspomagania pojazd zostaje tam, gdzie go zostawiono.
		lateral_velocity_mps = 0.0
		target_lane = current_lane()
		return
	var target_x := lane_center(target_lane)
	var gap := target_x - x_m
	var top := assist_speed_mps if free_steering else max_lateral_speed_mps
	var tau := assist_tau_s if free_steering else settle_tau_s
	var speed := minf(top, absf(gap) / tau)
	var new_x := move_toward(x_m, target_x, speed * delta)
	if absf(target_x - new_x) < 0.005:
		new_x = target_x
		free_steering = false
	lateral_velocity_mps = (new_x - x_m) / delta
	x_m = new_x


## Pas najbliższy bieżącej pozycji bocznej.
func current_lane() -> int:
	var lane := roundi(x_m / lane_width_m + (lane_count - 1) * 0.5)
	return clampi(lane, 0, lane_count - 1)


func is_changing() -> bool:
	return absf(lane_center(target_lane) - x_m) > 0.01
