class_name WeatherFx
extends Node3D
## Burza piaskowa (interwały treningu, ucieczki w trybie wolnym): gęstnieje mgła, słońce
## przygasa, wiatr niesie smugi piasku. Siła 0..1 zmienia się płynnie.

var _env: Environment
var _sun: DirectionalLight3D
var _streaks: CPUParticles3D
var _target := 0.0
var _strength := 0.0
var _base_density := 0.0045
var _base_fog := Color.WHITE
var _base_sun := 1.35
var _storm_fog := Color(0.82, 0.6, 0.38)


func setup(world: WorldEnvironment, sun: DirectionalLight3D) -> void:
	_env = world.environment.duplicate(true) as Environment
	world.environment = _env
	_sun = sun
	_base_density = _env.fog_density
	_base_fog = _env.fog_light_color
	_base_sun = sun.light_energy
	_build_streaks()


func set_storm(strength: float) -> void:
	_target = clampf(strength, 0.0, 1.0)


func storm_strength() -> float:
	return _strength


func _process(delta: float) -> void:
	if _env == null:
		return
	_strength = move_toward(_strength, _target, delta / 4.0)
	_env.fog_density = lerpf(_base_density, 0.028, _strength)
	_env.fog_light_color = _base_fog.lerp(_storm_fog, _strength)
	_sun.light_energy = lerpf(_base_sun, 0.55, _strength)
	_streaks.emitting = _strength > 0.05
	_streaks.amount_ratio = clampf(_strength, 0.0, 1.0)


func _build_streaks() -> void:
	_streaks = CPUParticles3D.new()
	_streaks.amount = 420
	_streaks.lifetime = 1.4
	_streaks.preprocess = 1.0
	_streaks.emitting = false
	_streaks.local_coords = false
	_streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_streaks.emission_box_extents = Vector3(26.0, 5.0, 30.0)
	_streaks.position = Vector3(-8.0, 4.0, -18.0)
	_streaks.direction = Vector3(1.0, -0.05, 0.45)
	_streaks.spread = 8.0
	_streaks.gravity = Vector3.ZERO
	_streaks.initial_velocity_min = 22.0
	_streaks.initial_velocity_max = 34.0
	_streaks.particle_flag_align_y = true
	var streak := BoxMesh.new()
	streak.size = Vector3(0.04, 1.6, 0.04)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.78, 0.55, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.material = mat
	_streaks.mesh = streak
	add_child(_streaks)
