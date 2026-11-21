class_name CourseProfile
extends RefCounted
## Ukształtowanie trasy: płynne wzniesienia i doliny (nachylenie w funkcji dystansu).
## Suma trzech sinusoid o różnych długościach fali – deterministyczna dla ziarna.
## Pierwsze 400 m płasko, potem teren łagodnie „wchodzi”. Typowo ±3%, szczytowo ±6%.

const FLAT_START_M := 400.0
const BLEND_M := 300.0

var amplitude := 1.0
## Skala zakrętów (0 = prosta droga).
var curve_amplitude := 1.0
var _phases: Array[float] = []
var _curve_phases: Array[float] = []
## Zakręty: [długość fali m, amplituda boczna m] – muszą zgadzać się z bend.gdshaderinc.
const CURVES := [[700.0, 30.0], [290.0, 6.0]]
const CURVE_START_M := 250.0
const WAVES := [[1700.0, 0.030], [650.0, 0.020], [260.0, 0.010]]


func _init(seed_value: int = 0, p_amplitude: float = 1.0) -> void:
	amplitude = p_amplitude
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 4242
	for i in WAVES.size():
		_phases.append(rng.randf_range(0.0, TAU))
	for i in CURVES.size():
		_curve_phases.append(rng.randf_range(0.0, TAU))


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


## Boczne położenie osi trasy [m] – zakręty. Tylko do obrazu (shader) i testów.
func lateral_at(distance_m: float) -> float:
	var x := 0.0
	for i in CURVES.size():
		var c: Array = CURVES[i]
		x += float(c[1]) * sin(distance_m / float(c[0]) * TAU + _curve_phases[i])
	# smoothstep: zakręty „wchodzą” płynnie, bez załamania drogi na początku i końcu przejścia.
	return x * curve_amplitude * smoothstep(CURVE_START_M, CURVE_START_M + BLEND_M, distance_m)


## Krzywizna trasy [1/m] (dodatnia = skręt w prawo) – np. do przechyłu pojazdu.
func curvature_at(distance_m: float) -> float:
	return (lateral_at(distance_m + 2.0) - 2.0 * lateral_at(distance_m) + lateral_at(distance_m - 2.0)) / 4.0


## Parametry dla shadera wyginającego świat.
func hill_phases() -> Vector3:
	return Vector3(_phases[0], _phases[1], _phases[2])


func curve_phases() -> Vector2:
	return Vector2(_curve_phases[0], _curve_phases[1])
