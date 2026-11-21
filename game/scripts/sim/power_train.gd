class_name PowerTrain
extends RefCounted
## Układ napędowy: jak moc z nóg staje się mocą na kołach.
##
##   moc na kołach = moc z nóg × akceleratory × dopalacz
##
## Akceleratory działają stale: generator (moduł – VehicleModel.engine_multiplier) i załoga,
## czyli uwolnieni pedalarze, którzy kręcą razem z tobą. Dopalacz działa chwilowo: wtrysk
## czystego paliwa z zaplombowanego kanistra. Ładunki uzupełniają kanistry zebrane na trasie.
## Wartości treningowe (kJ, NP, TSS, strefy) zawsze liczą się z samej mocy z nóg.

signal boost_started
signal boost_ended

## Każdy pedalarz w załodze dokłada 2% mocy.
const CREW_BONUS_EACH := 0.02

var crew := 0
var boost_gain := 0.25
var boost_duration_s := 6.0
var max_charges := 1
var charges := 1
var boost_left_s := 0.0
var boosts_used := 0


func crew_multiplier() -> float:
	return 1.0 + CREW_BONUS_EACH * maxi(crew, 0)


func is_boosting() -> bool:
	return boost_left_s > 0.0


## Mnożnik mocy z załogi i dopalacza (generator liczy osobno VehicleModel).
func multiplier() -> float:
	return crew_multiplier() * ((1.0 + boost_gain) if is_boosting() else 1.0)


## Odpala dopalacz. False, gdy brak ładunków albo poprzedni jeszcze działa.
func trigger() -> bool:
	if charges <= 0 or is_boosting():
		return false
	charges -= 1
	boosts_used += 1
	boost_left_s = boost_duration_s
	boost_started.emit()
	return true


## Kanister z trasy uzupełnia ładunek. Zwraca, ile ładunków faktycznie przybyło.
func refill(amount: int = 1) -> int:
	var before := charges
	charges = mini(max_charges, charges + maxi(amount, 0))
	return charges - before


func step(delta: float) -> void:
	if boost_left_s <= 0.0:
		return
	boost_left_s = maxf(0.0, boost_left_s - delta)
	if boost_left_s <= 0.0:
		boost_ended.emit()
