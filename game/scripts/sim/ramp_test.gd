class_name RampTest
extends RefCounted
## Test FTP jako „Rytuał Progu”: test narastający (ramp test). Po rozgrzewce cel rośnie
## co minutę o stały stopień, aż zawodnik nie utrzyma mocy. Wynik: FTP = 75% najlepszej
## średniej mocy z jednej minuty – standardowy przelicznik testu narastającego.
## Test kończy się sam: gdy moc przez kilka sekund jest wyraźnie poniżej celu, plan zostaje
## obcięty w tym miejscu i dostaje krótkie schłodzenie. Czysta logika.

signal step_reached(number: int, target_w: float)
signal finished(result_ftp_w: float, steps_done: int)

## Moc poniżej tylu celu przez FAIL_S sekund = koniec testu.
const FAIL_RATIO := 0.85
const FAIL_S := 8.0
## Wynik liczy się dopiero po tylu ukończonych stopniach (krótszy test nic nie mówi).
const MIN_STEPS := 4
const FTP_FACTOR := 0.75
const COOLDOWN_S := 180.0

var plan: WorkoutPlan
var ftp_w := 200.0
var done := false
## Ukończone pełne stopnie.
var steps_done := 0
## Nowe FTP [W]; 0 = test za krótki, wynik nieważny.
var result_ftp_w := 0.0

var _below_s := 0.0
var _last_index := 0


func _init(p_plan: WorkoutPlan, p_ftp_w: float) -> void:
	plan = p_plan
	ftp_w = p_ftp_w


## Wołane co klatkę. Zwraca true w klatce, w której test właśnie się zakończył
## (plan jest już wtedy obcięty – wołający powinien skrócić wyprawę do długości planu).
func step(delta: float, t: float, power_w: float, metrics: TrainingMetrics) -> bool:
	if done or delta <= 0.0:
		return false
	var i := plan.step_index_at(t)
	if i <= 0:
		# Rozgrzewka (krok 0) albo koniec planu bez porażki: zawodnik przeszedł wszystkie stopnie.
		if i < 0:
			_finish(plan.total_duration_s() - 0.01, metrics)
			return true
		return false
	if i != _last_index:
		_last_index = i
		steps_done = i - 1
		step_reached.emit(i, roundf(plan.target_watts_at(t, ftp_w)))
	var target := plan.target_watts_at(t, ftp_w)
	_below_s = _below_s + delta if power_w < target * FAIL_RATIO else 0.0
	if _below_s >= FAIL_S:
		_finish(t, metrics)
		return true
	return false


func _finish(t: float, metrics: TrainingMetrics) -> void:
	done = true
	var best_minute := metrics.best_power(1)
	result_ftp_w = roundf(best_minute * FTP_FACTOR) if steps_done >= MIN_STEPS and best_minute > 0.0 else 0.0
	# Plan kończy się tu i teraz: obcięty krok plus schłodzenie.
	var i := plan.step_index_at(t)
	if i >= 0:
		plan.steps[i].duration_s = maxf(1.0, plan.time_in_step_s(t))
		plan.steps.resize(i + 1)
	plan.add_step(WorkoutStep.new(WorkoutStep.Kind.COOLDOWN, COOLDOWN_S, 0.5, 0.4, 0.0, "Schłodzenie"))
	finished.emit(result_ftp_w, steps_done)
