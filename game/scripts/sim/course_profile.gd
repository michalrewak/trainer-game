class_name CourseProfile
extends RefCounted
## Ukształtowanie trasy: płynne wzniesienia i doliny (nachylenie w funkcji dystansu).
## Suma trzech sinusoid o różnych długościach fali – deterministyczna dla ziarna.
## Pierwsze 400 m płasko, potem teren łagodnie „wchodzi”. Typowo ±3%, szczytowo ±6%.

const FLAT_START_M := 400.0
const BLEND_M := 300.0

var amplitude := 1.0
var _phases: Array[float] = []
const WAVES := [[1700.0, 0.030], [650.0, 0.020], [260.0, 0.010]]


func _init(seed_value: int = 0, p_amplitude: float = 1.0) -> void:
	amplitude = p_amplitude
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 4242
	for i in WAVES.size():
		_phases.append(rng.randf_range(0.0, TAU))


## Nachylenie jako ułamek (0.04 = 4%) na danym dystansie.
func grade_at(distance_m: float) -> float:
	if distance_m <= FLAT_START_M:
		return 0.0
	var g := 0.0
	for i in WAVES.size():
		var wave: Array = WAVES[i]
		g += float(wave[1]) * sin(distance_m / float(wave[0]) * TAU + _phases[i])
	var blend := clampf((distance_m - FLAT_START_M) / BLEND_M, 0.0, 1.0)
	return g * amplitude * blend
