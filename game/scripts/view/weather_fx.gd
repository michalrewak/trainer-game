class_name WeatherFx
extends Node3D
## Reżyser wyglądu wyprawy (docs/swiat.md): pora dnia i burza iskrowa.
## - dzień „Fury Road”: ostre pomarańczowe słońce, turkusowe cienie, ściana burzy na horyzoncie,
## - zmierzch: niskie czerwone słońce, fioletowe niebo,
## - noc „Nocny konwój”: światło księżyca, reflektory, świecące pociski i złom,
## - burza iskrowa (interwały, ucieczki): mrok, gęsty pył, błyskawice, jazda w reflektorach.
## Pora (0 = dzień, 0.5 = zmierzch, 1 = noc) i siła burzy (0..1) mieszają się płynnie.

const DAY := {
	"sun_color": Color(1.0, 0.82, 0.58), "sun_energy": 2.4, "sun_dir": Vector3(-0.55, -0.5, -0.45),
	"amb_color": Color(0.25, 0.55, 0.62), "amb_energy": 1.1,
	"fog_color": Color(0.93, 0.62, 0.36), "fog_density": 0.0035,
	"sky_top": Color(0.16, 0.42, 0.55), "sky_horizon": Color(0.96, 0.68, 0.42),
	"saturation": 1.3, "contrast": 1.12, "headlights": 0.0,
}
const DUSK := {
	"sun_color": Color(1.0, 0.45, 0.22), "sun_energy": 1.8, "sun_dir": Vector3(-0.85, -0.2, -0.4),
	"amb_color": Color(0.32, 0.3, 0.5), "amb_energy": 0.8,
	"fog_color": Color(0.75, 0.36, 0.3), "fog_density": 0.004,
	"sky_top": Color(0.18, 0.16, 0.36), "sky_horizon": Color(0.98, 0.45, 0.25),
	"saturation": 1.25, "contrast": 1.15, "headlights": 0.6,
}
const NIGHT := {
	"sun_color": Color(0.55, 0.68, 1.0), "sun_energy": 0.85, "sun_dir": Vector3(0.4, -0.7, -0.35),
	"amb_color": Color(0.12, 0.2, 0.36), "amb_energy": 1.3,
	"fog_color": Color(0.05, 0.08, 0.16), "fog_density": 0.006,
	"sky_top": Color(0.02, 0.04, 0.1), "sky_horizon": Color(0.1, 0.16, 0.3),
	"saturation": 1.1, "contrast": 1.1, "headlights": 1.0,
}
const STORM := {
	"sun_color": Color(0.9, 0.5, 0.25), "sun_energy": 0.35, "sun_dir": Vector3(-0.55, -0.5, -0.45),
	"amb_color": Color(0.3, 0.17, 0.09), "amb_energy": 0.7,
	"fog_color": Color(0.36, 0.2, 0.1), "fog_density": 0.03,
	"sky_top": Color(0.2, 0.11, 0.06), "sky_horizon": Color(0.24, 0.13, 0.07),
	"saturation": 1.0, "contrast": 1.2, "headlights": 1.0,
}

var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _flash: DirectionalLight3D
var _streaks: CPUParticles3D
var _headlight: SpotLight3D
var _fill: OmniLight3D
var _wall: Node3D
var _wall_mat: StandardMaterial3D
var _storm_target := 0.0
var _storm := 0.0
var _time_target := 0.0
var _time := 0.0
var _flash_t := 0.0
var _next_flash := 3.0
var _rng := RandomNumberGenerator.new()


func setup(world: WorldEnvironment, sun: DirectionalLight3D) -> void:
	_env = world.environment.duplicate(true) as Environment
	world.environment = _env
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.adjustment_enabled = true
	_sky = _env.sky.sky_material as ProceduralSkyMaterial
	_sun = sun
	_sun.directional_shadow_max_distance = 140.0
	_flash = DirectionalLight3D.new()
	_flash.light_color = Color(0.8, 0.88, 1.0)
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	add_child(_flash)
	_flash.look_at_from_position(Vector3.ZERO, Vector3(0.3, -0.8, -0.5), Vector3.UP)
	_build_streaks()
	_build_storm_wall()
	_apply(0.0)


## Reflektory i światło pozycyjne pojazdu (noc, zmierzch, burza).
func attach_headlights(vehicle: Node3D) -> void:
	_headlight = SpotLight3D.new()
	_headlight.light_color = Color(1.0, 0.9, 0.7)
	_headlight.spot_range = 55.0
	_headlight.spot_angle = 30.0
	_headlight.spot_attenuation = 0.6
	_headlight.shadow_enabled = true
	_headlight.light_energy = 0.0
	vehicle.add_child(_headlight)
	_headlight.position = Vector3(0, 1.3, -1.4)
	_headlight.rotation = Vector3(deg_to_rad(-9.0), 0, 0)
	_fill = OmniLight3D.new()
	_fill.light_color = Color(1.0, 0.75, 0.5)
	_fill.omni_range = 7.0
	_fill.light_energy = 0.0
	vehicle.add_child(_fill)
	_fill.position = Vector3(0, 3.2, 1.0)


func set_storm(strength: float) -> void:
	_storm_target = clampf(strength, 0.0, 1.0)


## Pora: 0 = dzień, 0.5 = zmierzch, 1 = noc.
func set_time(t: float, instant: bool = false) -> void:
	_time_target = clampf(t, 0.0, 1.0)
	if instant:
		_time = _time_target


func storm_strength() -> float:
	return _storm


func darkness() -> float:
	return maxf(_time, _storm)


func _process(delta: float) -> void:
	if _env == null:
		return
	_storm = move_toward(_storm, _storm_target, delta / 4.0)
	_time = move_toward(_time, _time_target, delta / 20.0)
	_apply(delta)


func _apply(delta: float) -> void:
	var base := _lerp_look(DAY, DUSK, _time * 2.0) if _time < 0.5 else _lerp_look(DUSK, NIGHT, _time * 2.0 - 1.0)
	var storm := STORM.duplicate()
	# Burza w nocy jest jeszcze ciemniejsza.
	var night_dim := lerpf(1.0, 0.45, _time)
	storm["fog_color"] = (storm["fog_color"] as Color) * night_dim
	storm["sky_top"] = (storm["sky_top"] as Color) * night_dim
	storm["sky_horizon"] = (storm["sky_horizon"] as Color) * night_dim
	var look := _lerp_look(base, storm, _storm)

	_sun.light_color = look["sun_color"]
	_sun.light_energy = look["sun_energy"]
	_sun.look_at_from_position(Vector3.ZERO, look["sun_dir"], Vector3.UP)
	_env.ambient_light_color = look["amb_color"]
	_env.ambient_light_energy = look["amb_energy"]
	_env.fog_light_color = look["fog_color"]
	_env.fog_density = look["fog_density"]
	_env.adjustment_saturation = look["saturation"]
	_env.adjustment_contrast = look["contrast"]
	if _sky != null:
		_sky.sky_top_color = look["sky_top"]
		_sky.sky_horizon_color = look["sky_horizon"]
		_sky.ground_horizon_color = look["sky_horizon"]
		_sky.ground_bottom_color = (look["fog_color"] as Color).darkened(0.3)
	var lights: float = look["headlights"]
	if _headlight != null:
		_headlight.light_energy = lights * 16.0
		_headlight.visible = lights > 0.02
		_fill.light_energy = lights * 1.6
	_streaks.emitting = _storm > 0.05
	# Ściana burzy na horyzoncie: widoczna w dzień, o zmierzchu ciemnieje.
	_wall_mat.albedo_color = (look["fog_color"] as Color).lerp(Color(0.3, 0.13, 0.06), 0.75) * lerpf(1.0, 0.25, _time)
	_tick_lightning(delta)


func _tick_lightning(delta: float) -> void:
	if _storm < 0.4:
		_flash.light_energy = 0.0
		return
	_next_flash -= delta
	if _next_flash <= 0.0:
		_next_flash = _rng.randf_range(2.0, 6.0)
		_flash_t = 0.45
	if _flash_t > 0.0:
		_flash_t -= delta
		# Dwa szybkie błyski.
		var k := _flash_t / 0.45
		var pulse := maxf(0.0, sin(k * PI * 2.0)) * (0.6 + 0.4 * k)
		_flash.light_energy = pulse * 3.2 * _storm
		_env.fog_light_color = _env.fog_light_color.lerp(Color(0.75, 0.8, 0.95), pulse * 0.5)
	else:
		_flash.light_energy = 0.0


static func _lerp_look(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var k := clampf(t, 0.0, 1.0)
	var out := {}
	for key in a:
		var va: Variant = a[key]
		var vb: Variant = b[key]
		if va is Color:
			out[key] = (va as Color).lerp(vb, k)
		elif va is Vector3:
			out[key] = (va as Vector3).lerp(vb, k).normalized()
		else:
			out[key] = lerpf(float(va), float(vb), k)
	return out


func _build_storm_wall() -> void:
	_wall = Node3D.new()
	add_child(_wall)
	_wall_mat = StandardMaterial3D.new()
	_wall_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wall_mat.disable_fog = true
	_wall_mat.albedo_color = Color(0.4, 0.2, 0.1)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 10
	sphere.rings = 5
	_rng.seed = 77
	for i in 26:
		var mi := MeshInstance3D.new()
		mi.mesh = sphere
		mi.material_override = _wall_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var r := _rng.randf_range(34.0, 68.0)
		mi.scale = Vector3(r * 1.5, r, r)
		mi.position = Vector3(-620.0 + i * 50.0 + _rng.randf_range(-20.0, 20.0), _rng.randf_range(-22.0, 6.0), -540.0 - _rng.randf_range(0.0, 30.0))
		_wall.add_child(mi)


func _build_streaks() -> void:
	_streaks = CPUParticles3D.new()
	_streaks.amount = 520
	_streaks.lifetime = 1.4
	_streaks.preprocess = 1.0
	_streaks.emitting = false
	_streaks.local_coords = false
	_streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_streaks.emission_box_extents = Vector3(30.0, 6.0, 34.0)
	_streaks.position = Vector3(-8.0, 5.0, -20.0)
	_streaks.direction = Vector3(1.0, -0.05, 0.45)
	_streaks.spread = 8.0
	_streaks.gravity = Vector3.ZERO
	_streaks.initial_velocity_min = 22.0
	_streaks.initial_velocity_max = 34.0
	_streaks.particle_flag_align_y = true
	var streak := BoxMesh.new()
	streak.size = Vector3(0.04, 1.1, 0.04)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.7, 0.45, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.material = mat
	_streaks.mesh = streak
	add_child(_streaks)
