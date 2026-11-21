class_name Arrival
extends RefCounted
## Koniec wyprawy w świecie gry: zamiast „mety” jest brama osady. Wyprawy są na czas
## (trening ma swój plan, jazda swobodna – wybraną długość), więc osada stoi tam, dokąd
## gracz dojedzie w chwili, gdy czas się skończy: jej pozycja jest przeliczana z prędkości
## i pozostałego czasu, a tuż przed końcem zostaje zablokowana, żeby brama nie „pływała”.
## Czysta logika – widok (SettlementView) tylko ją rysuje.

## Brama pojawia się na horyzoncie, gdy do końca zostało tyle sekund.
const SHOW_S := 50.0
## Przez ostatnie sekundy pozycja bramy już się nie zmienia.
const LOCK_S := 5.0
## Wraki znikają z ostatnich metrów przed bramą i z placu za nią.
const CLEAR_BEFORE_M := 45.0
const MIN_SPEED := 3.0

## Dystans bramy od startu wyprawy [m]; ujemny = jeszcze jej nie widać.
var gate_d := -1.0
## Ustawiane na jeden krok, gdy brama pierwszy raz pojawia się na horyzoncie.
var just_sighted := false


func is_visible() -> bool:
	return gate_d >= 0.0


func distance_left_m(d: float) -> float:
	return maxf(0.0, gate_d - d) if is_visible() else -1.0


func step(delta: float, time_left_s: float, d: float, speed_mps: float) -> void:
	just_sighted = false
	if time_left_s > SHOW_S:
		gate_d = -1.0
		return
	var estimate := d + maxf(speed_mps, MIN_SPEED) * time_left_s
	if gate_d < 0.0:
		gate_d = estimate
		just_sighted = true
	elif time_left_s > LOCK_S:
		# Łagodna korekta: gracz przyspiesza albo zwalnia, osada „czeka” tam, gdzie dojedzie.
		gate_d = lerpf(gate_d, estimate, 1.0 - exp(-delta / 1.5))
