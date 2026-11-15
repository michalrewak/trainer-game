class_name TargetBand
extends RefCounted
## Widełki mocy docelowej. Na treningu za mało i za dużo to błąd: poniżej dolnej granicy
## zasilanie słabnie proporcjonalnie, w widełkach jest pełne, a powyżej górnej generator
## się „przegrzewa” – zasilanie spada (słabsza tarcza i wolniejszy ogień).
## Tolerancje są względem celu: low_tol = 0.05 oznacza dolną granicę 95% celu.

enum Status { BELOW, IN_BAND, ABOVE }

## Jazda swobodna: cel to spokojne tempo, więc u góry dużo luzu.
const FREE_RIDE_LOW := 0.10
const FREE_RIDE_HIGH := 0.40
## Wyzwania trybu wolnego.
const CHALLENGE_TOL := 0.08
## Kroki planu treningowego (etap 4).
const WORKOUT_TOL := 0.05
## Ile ponad górną granicę (jako ułamek celu) zbija zasilanie do minimum.
const OVERHEAT_SPAN := 0.3
const OVERHEAT_MIN_SUPPLY := 0.4


static func low(target_w: float, low_tol: float) -> float:
	return target_w * (1.0 - low_tol)


static func high(target_w: float, high_tol: float) -> float:
	return target_w * (1.0 + high_tol)


static func status(power_w: float, target_w: float, low_tol: float, high_tol: float) -> Status:
	if power_w < low(target_w, low_tol):
		return Status.BELOW
	if power_w > high(target_w, high_tol):
		return Status.ABOVE
	return Status.IN_BAND


static func is_in_band(power_w: float, target_w: float, low_tol: float, high_tol: float) -> bool:
	return status(power_w, target_w, low_tol, high_tol) == Status.IN_BAND


## Zasilanie generatora 0..1 dla danej mocy i widełek.
static func supply(power_w: float, target_w: float, low_tol: float, high_tol: float) -> float:
	if target_w <= 0.0:
		return 1.0
	var lo := low(target_w, low_tol)
	var hi := high(target_w, high_tol)
	if power_w < lo:
		return clampf(power_w / lo, 0.0, 1.0)
	if power_w <= hi:
		return 1.0
	var over := (power_w - hi) / (OVERHEAT_SPAN * target_w)
	return clampf(1.0 - over * (1.0 - OVERHEAT_MIN_SUPPLY), OVERHEAT_MIN_SUPPLY, 1.0)


## Tekst zakresu do HUD, np. "160–190 W".
static func range_text(target_w: float, low_tol: float, high_tol: float) -> String:
	return "%d–%d W" % [roundi(low(target_w, low_tol)), roundi(high(target_w, high_tol))]
