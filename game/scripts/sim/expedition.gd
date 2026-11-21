class_name Expedition
extends RefCounted
## Stan jednej wyprawy: czas (odliczany do zadanej długości), dystans, złom, statystyki mocy.
## Kończy się wyłącznie po czasie – nigdy przez porażkę.

var duration_s := 900.0
var elapsed_s := 0.0
var distance_m := 0.0
var scrap := 0
var scrap_collected := 0
var scrap_lost := 0
var collisions := 0
var raids_lost := 0
var raiders_destroyed := 0
var fuel := 0
var challenges_completed := 0
var raids_done := 0
## Ulepszenia (etap 3): pancerz zmniejsza straty, przyczepa dokłada część złomu.
var scrap_loss_factor := 1.0
var scrap_bonus := 0.0
var _bonus_acc := 0.0
var energy_j := 0.0
var max_power_w := 0.0
var max_speed_mps := 0.0
var finished := false
## Wartości treningowe (strefy, NP, IF, TSS). FTP ustawia kontroler wyprawy.
var metrics := TrainingMetrics.new()


func _init(p_duration_s: float = 900.0) -> void:
	duration_s = maxf(1.0, p_duration_s)


func tick(delta: float, power_w: float, speed_mps: float, p_distance_m: float) -> void:
	if finished or delta <= 0.0:
		return
	var step := minf(delta, duration_s - elapsed_s)
	elapsed_s += step
	energy_j += maxf(power_w, 0.0) * step
	metrics.tick(step, power_w)
	max_power_w = maxf(max_power_w, power_w)
	max_speed_mps = maxf(max_speed_mps, speed_mps)
	distance_m = p_distance_m
	if elapsed_s >= duration_s - 1e-6:
		elapsed_s = duration_s
		finished = true


func add_scrap(amount: int) -> void:
	_bonus_acc += amount * scrap_bonus
	var extra := floori(_bonus_acc)
	_bonus_acc -= extra
	scrap += amount + extra
	scrap_collected += amount + extra


func add_fuel(amount: int) -> void:
	fuel += amount


## Utrata części złomu przy zderzeniu: 15% (w górę), co najmniej 3, nie więcej niż jest.
## Pancerz (scrap_loss_factor) zmniejsza stratę.
func lose_scrap_on_hit() -> int:
	collisions += 1
	return _lose(maxi(3, ceili(scrap * 0.15)))


## Rabunek przy udanym taranowaniu przez gang: 10% (w górę), co najmniej 2.
func lose_scrap_to_raid() -> int:
	raids_lost += 1
	return _lose(maxi(2, ceili(scrap * 0.10)))


## Trafienie pociskiem z wieży osady: 6% złomu (w górę), co najmniej 2.
func lose_scrap_to_shell() -> int:
	return _lose(maxi(2, ceili(scrap * 0.06)))


func _lose(base: int) -> int:
	if scrap <= 0:
		return 0
	var lost := mini(scrap, ceili(base * scrap_loss_factor))
	scrap -= lost
	scrap_lost += lost
	return lost


func time_left_s() -> float:
	return maxf(0.0, duration_s - elapsed_s)


func progress() -> float:
	return clampf(elapsed_s / duration_s, 0.0, 1.0)


func average_power_w() -> float:
	return energy_j / elapsed_s if elapsed_s > 0.0 else 0.0


func average_speed_kmh() -> float:
	return distance_m / elapsed_s * 3.6 if elapsed_s > 0.0 else 0.0


## Podsumowanie do ekranu końcowego i zapisu postępu.
func to_summary(completed: bool) -> Dictionary:
	var out := {
		"completed": completed,
		"planned_duration_s": roundi(duration_s),
		"duration_s": roundi(elapsed_s),
		"distance_m": roundi(distance_m),
		"scrap": scrap,
		"scrap_collected": scrap_collected,
		"scrap_lost": scrap_lost,
		"fuel": fuel,
		"challenges_completed": challenges_completed,
		"raids_done": raids_done,
		"collisions": collisions,
		"raids_lost": raids_lost,
		"raiders_destroyed": raiders_destroyed,
		"avg_power_w": roundi(average_power_w()),
		"max_power_w": roundi(max_power_w),
		"avg_speed_kmh": snappedf(average_speed_kmh(), 0.1),
		"max_speed_kmh": snappedf(max_speed_mps * 3.6, 0.1),
		"energy_kj": roundi(energy_j / 1000.0),
	}
	out.merge(metrics.to_summary())
	return out
