class_name ScriptedPowerSource
extends PowerSource
## Źródło mocy sterowane skryptem: stała moc z lekką falą. Używane przez autopilota
## (testy dymne, demo) i testy jednostkowe. Pokazuje też, że gra działa z dowolnym
## źródłem implementującym PowerSource.

var base_watts := 210.0
var wave_watts := 25.0
var wave_period_s := 40.0

var _time := 0.0
var _power := 0.0
var _saved_base := -1.0
var _saved_wave := 0.0


func _init(p_base_watts: float = 210.0, p_wave_watts: float = 25.0) -> void:
	base_watts = p_base_watts
	wave_watts = p_wave_watts


func update(delta: float) -> void:
	_time += delta
	_power = maxf(0.0, base_watts + wave_watts * sin(_time * TAU / wave_period_s))


func get_power_watts() -> float:
	return _power


func get_cadence() -> float:
	return ManualPowerModel.cadence_for_power(_power, _time)


## Autopilot jak posłuszny zawodnik: w ERG trzyma cel (z drobnym wahaniem ±2%).
func set_erg_target(watts: float) -> void:
	if watts > 0.0:
		if _saved_base < 0.0:
			_saved_base = base_watts
			_saved_wave = wave_watts
		base_watts = watts
		wave_watts = watts * 0.02
	elif _saved_base >= 0.0:
		base_watts = _saved_base
		wave_watts = _saved_wave
		_saved_base = -1.0


func get_label() -> String:
	return "AUTO"


func get_hint() -> String:
	return "AUTOPILOT"
