class_name WorkoutRunner
extends RefCounted
## Tryb treningowy (etap 4): prowadzi plan w czasie wyprawy. Plan „rzeźbi” trasę:
## ciężkie kroki to burza piaskowa (pole bezpieczne – bez wraków i gangów), lekkie to
## zbieranie złomu. Cel mocy ma widełki ±5% – za mało i za dużo to błąd.
## Liczy zgodność: odsetek czasu z celem w widełkach.

signal step_changed(index: int, step: WorkoutStep)

var plan: WorkoutPlan
var ftp_w := 200.0
var tol := TargetBand.WORKOUT_TOL
var current_index := -1
var in_band_s := 0.0
var with_target_s := 0.0


func _init(p_plan: WorkoutPlan, p_ftp_w: float) -> void:
	plan = p_plan
	ftp_w = p_ftp_w


func duration_s() -> float:
	return plan.total_duration_s()


func target_w(t: float) -> float:
	return roundf(plan.target_watts_at(t, ftp_w))


func is_hard_now(t: float) -> bool:
	var i := plan.step_index_at(t)
	return i >= 0 and plan.is_hard_step(i)


## Wołane co klatkę z czasem wyprawy i mocą; emituje step_changed przy zmianie kroku.
func step(t: float, delta: float, power_w: float) -> void:
	var i := plan.step_index_at(t)
	if i != current_index:
		current_index = i
		if i >= 0:
			step_changed.emit(i, plan.steps[i])
	if i < 0 or not plan.steps[i].has_target():
		return
	with_target_s += delta
	if TargetBand.is_in_band(power_w, target_w(t), tol, tol):
		in_band_s += delta


func compliance() -> float:
	return in_band_s / with_target_s if with_target_s > 0.0 else 0.0


## Bloki do profilu w HUD (WorkoutProfile).
func blocks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in plan.steps.size():
		var s := plan.steps[i]
		out.append({"start": plan.step_start_s(i), "duration": s.duration_s, "from": s.power_start, "to": s.power_end})
	return out


## Dane do panelu treningu w HUD.
func info(t: float) -> Dictionary:
	var i := plan.step_index_at(t)
	var label := "Koniec planu"
	var next_label := ""
	if i >= 0:
		var s := plan.steps[i]
		label = "%s %s" % [s.display_label(), TargetBand.range_text(target_w(t), tol, tol)]
		if i + 1 < plan.steps.size():
			var n := plan.steps[i + 1]
			next_label = "Dalej: %s %s · %d W" % [n.display_label(), WorkoutStep.format_duration(n.duration_s), roundi(ftp_w * n.average_fraction())]
	return {
		"now_s": t,
		"step_label": label,
		"step_left_s": plan.time_left_in_step_s(t) if i >= 0 else 0.0,
		"next_label": next_label,
		"target_w": target_w(t),
	}
