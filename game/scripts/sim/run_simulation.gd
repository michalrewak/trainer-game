class_name RunSimulation
extends RefCounted
## Cała pętla wyprawy bez węzłów i bez silnika fizyki: pojazd, pasy, trasa, kolizje,
## złom i czas. Widok (RunController + widoki 3D) tylko ją rysuje, więc całą rozgrywkę
## da się przetestować headless.
##
## Kolizje liczone są „przemiataniem” po dystansie (od pozycji z poprzedniego kroku do
## bieżącej), więc nie da się przeskoczyć wraku nawet przy dużym kroku czasu.

signal wreck_hit(item: TrackItem, scrap_lost: int)
signal scrap_collected(item: TrackItem)
signal finished

const LOOKAHEAD_M := 260.0
const KEEP_BEHIND_M := 30.0

var vehicle := VehicleModel.new()
var lanes := LaneModel.new()
var generator: TrackGenerator
var expedition: Expedition
var items: Array[TrackItem] = []

var impact_speed_factor := 0.35
var invulnerability_s := 1.2
var vehicle_half_length_m := 1.2
var vehicle_half_width_m := 0.95
var wreck_half_length_m := 1.6
var wreck_half_width_m := 1.3
var scrap_half_length_m := 0.9
var scrap_half_width_m := 1.2

var invulnerable_left_s := 0.0
var last_power_w := 0.0


func _init(duration_s: float = 900.0, seed_value: int = 0) -> void:
	expedition = Expedition.new(duration_s)
	generator = TrackGenerator.new(seed_value, lanes.lane_count)
	_refill()


func request_lane_change(direction: int) -> bool:
	if expedition.finished:
		return false
	return lanes.request_change(direction)


func step(delta: float, power_w: float) -> void:
	if expedition.finished or delta <= 0.0:
		return
	last_power_w = power_w
	var d0 := vehicle.distance_m
	vehicle.step(delta, power_w)
	lanes.step(delta)
	invulnerable_left_s = maxf(0.0, invulnerable_left_s - delta)
	expedition.tick(delta, power_w, vehicle.speed_mps, vehicle.distance_m)
	_resolve_contacts(d0, vehicle.distance_m)
	generator.difficulty = expedition.progress()
	generator.speed_hint_mps = maxf(vehicle.speed_mps, 8.0)
	_refill()
	_prune()
	if expedition.finished:
		finished.emit()


func is_invulnerable() -> bool:
	return invulnerable_left_s > 0.0


func lane_x(lane: int) -> float:
	return lanes.lane_center(lane)


## Obiekty w zasięgu [from_d, to_d] (nie skonsumowane), np. dla autopilota.
func items_between(from_d: float, to_d: float) -> Array[TrackItem]:
	var out: Array[TrackItem] = []
	for item in items:
		if not item.consumed and item.distance_m >= from_d and item.distance_m <= to_d:
			out.append(item)
	return out


func _resolve_contacts(d0: float, d1: float) -> void:
	var x := lanes.x_m
	for item in items:
		if item.consumed:
			continue
		var half_len := wreck_half_length_m if item.is_wreck() else scrap_half_length_m
		var half_w := wreck_half_width_m if item.is_wreck() else scrap_half_width_m
		if item.distance_m + half_len < d0 - vehicle_half_length_m:
			continue
		if item.distance_m - half_len > d1 + vehicle_half_length_m:
			continue
		if absf(lane_x(item.lane) - x) > half_w + vehicle_half_width_m:
			continue
		if item.is_wreck():
			if is_invulnerable():
				continue
			item.consumed = true
			vehicle.apply_impact(impact_speed_factor)
			invulnerable_left_s = invulnerability_s
			var lost := expedition.lose_scrap_on_hit()
			wreck_hit.emit(item, lost)
		else:
			item.consumed = true
			expedition.add_scrap(item.value)
			scrap_collected.emit(item)


func _refill() -> void:
	var target := vehicle.distance_m + LOOKAHEAD_M
	if target > generator.generated_until():
		items.append_array(generator.generate_until(target))


func _prune() -> void:
	var limit := vehicle.distance_m - KEEP_BEHIND_M
	var kept: Array[TrackItem] = []
	for item in items:
		if item.distance_m >= limit:
			kept.append(item)
	if kept.size() != items.size():
		items = kept
