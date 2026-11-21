class_name TrainingMetrics
extends RefCounted
## Wartości treningowe wyprawy liczone z mocy względem FTP (standard Coggana):
## - strefy mocy Z1–Z7 i czas w każdej z nich,
## - moc znormalizowana NP (średnia krocząca 30 s, podniesiona do 4. potęgi),
## - współczynnik intensywności IF = NP / FTP,
## - obciążenie treningowe TSS = czas[h] * IF^2 * 100.
## Czysta logika – gra tylko wyświetla wynik.

## Górne granice stref jako ułamek FTP; powyżej ostatniej zaczyna się Z7.
const ZONE_LIMITS: Array[float] = [0.55, 0.75, 0.90, 1.05, 1.20, 1.50]
const ZONE_NAMES: Array[String] = ["Z1 regeneracja", "Z2 wytrzymałość", "Z3 tempo", "Z4 próg", "Z5 VO2max", "Z6 beztlenowa", "Z7 sprint"]
const ZONE_COLORS: Array[Color] = [Color("8a8f96"), Color("4a9fd8"), Color("5cc46a"), Color("f2c94c"), Color("f2994a"), Color("eb5757"), Color("c04ad8")]
const WINDOW_S := 30

var ftp_w := 200.0
var zone_s: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var duration_s := 0.0

var _second_energy := 0.0
var _second_time := 0.0
var _window: Array[float] = []
var _window_sum := 0.0
var _fourth_sum := 0.0
var _samples := 0


func _init(p_ftp_w: float = 200.0) -> void:
	ftp_w = maxf(p_ftp_w, 1.0)


## Numer strefy 0..6 (Z1..Z7) dla danej mocy.
static func zone_index(power_w: float, p_ftp_w: float) -> int:
	var f := power_w / maxf(p_ftp_w, 1.0)
	for i in ZONE_LIMITS.size():
		if f <= ZONE_LIMITS[i]:
			return i
	return ZONE_LIMITS.size()


static func zone_name(power_w: float, p_ftp_w: float) -> String:
	return ZONE_NAMES[zone_index(power_w, p_ftp_w)]


func tick(delta: float, power_w: float) -> void:
	if delta <= 0.0:
		return
	var p := maxf(power_w, 0.0)
	duration_s += delta
	zone_s[zone_index(p, ftp_w)] += delta
	# Próbki sekundowe do średniej kroczącej 30 s.
	var left := delta
	while left > 0.0:
		var take := minf(left, 1.0 - _second_time)
		_second_energy += p * take
		_second_time += take
		left -= take
		if _second_time >= 1.0 - 1e-9:
			_push_second(_second_energy)
			_second_energy = 0.0
			_second_time = 0.0


func _push_second(avg_w: float) -> void:
	_window.append(avg_w)
	_window_sum += avg_w
	if _window.size() > WINDOW_S:
		_window_sum -= _window.pop_front()
	var rolling := _window_sum / _window.size()
	_fourth_sum += pow(rolling, 4.0)
	_samples += 1


func normalized_power() -> float:
	return pow(_fourth_sum / _samples, 0.25) if _samples > 0 else 0.0


func intensity_factor() -> float:
	return normalized_power() / ftp_w


func tss() -> float:
	var i := intensity_factor()
	return duration_s / 3600.0 * i * i * 100.0


## Pola do podsumowania wyprawy i zapisu.
func to_summary() -> Dictionary:
	var zones: Array[int] = []
	for s in zone_s:
		zones.append(roundi(s))
	return {
		"ftp_w": roundi(ftp_w),
		"np_w": roundi(normalized_power()),
		"intensity_factor": snappedf(intensity_factor(), 0.01),
		"tss": snappedf(tss(), 0.1),
		"zones_s": zones,
	}
