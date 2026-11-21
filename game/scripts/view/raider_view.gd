class_name RaiderView
extends Node3D
## Pojazd gangu: ciemny, kolczasty buggy z płytą taranującą od strony gracza.
## Ostrzeżenie przed atakiem: migające czerwone światła i „!” nad pojazdem.

var _body: Node3D
var _warn_lights: Array[MeshInstance3D] = []
var _warn_mat: ShaderMaterial
var _flash_mat: ShaderMaterial
var _hull_mats: Array[MeshInstance3D] = []
var _exclaim: Label3D
var _wheels: Array[Node3D] = []
var _smoke: CPUParticles3D
var _shown_x := 0.0
var _initialized := false
var _wheel_angle := 0.0
var _time := 0.0


func build(variant: int, side: int) -> void:
	_body = Node3D.new()
	add_child(_body)
	var hull_colors: Array[Color] = [Color("2b2522"), Color("4a1f1a"), Color("33302a")]
	var hull := Palette.mat(hull_colors[posmod(variant, 3)], 0.7, 0.3)
	var rust := Palette.mat(Palette.RUST, 0.9, 0.2)
	var spike := Palette.mat(Color("b9b2a6"), 0.4, 0.8)
	var tire := Palette.mat(Palette.TIRE)
	_flash_mat = Palette.glow(Color("ffffff"), 4.0)
	_warn_mat = Palette.glow(Color("ff2a1a"), 3.0).duplicate() as ShaderMaterial

	var chassis := LowPoly.box(Vector3(1.7, 0.55, 2.8), hull, Vector3(0, 0.75, 0))
	_body.add_child(chassis)
	_hull_mats.append(chassis)
	_body.add_child(LowPoly.box(Vector3(1.2, 0.45, 1.1), rust, Vector3(0, 1.25, 0.3)))
	# Płyta taranująca z kolcami – po stronie gracza (przeciwnej do strony ataku).
	var ram_x := -side * 0.92
	_body.add_child(LowPoly.box(Vector3(0.14, 0.7, 2.4), rust, Vector3(ram_x, 0.85, 0)))
	for i in 4:
		_body.add_child(LowPoly.cylinder(0.07, 0.5, spike, Vector3(ram_x - side * 0.25, 0.85, -0.9 + i * 0.6), Vector3(0, 0, PI * 0.5), 5))
	# Kolce z przodu i klatka.
	for i in 3:
		_body.add_child(LowPoly.cylinder(0.06, 0.6, spike, Vector3(-0.5 + i * 0.5, 0.75, -1.65), Vector3(PI * 0.5, 0, 0), 5))
	_body.add_child(LowPoly.tube(Vector3(-0.6, 1.0, 0.9), Vector3(-0.5, 1.9, 0.6), 0.05, spike))
	_body.add_child(LowPoly.tube(Vector3(0.6, 1.0, 0.9), Vector3(0.5, 1.9, 0.6), 0.05, spike))
	_body.add_child(LowPoly.tube(Vector3(-0.5, 1.9, 0.6), Vector3(0.5, 1.9, 0.6), 0.05, spike))
	# Kierowca z irokezem.
	_body.add_child(LowPoly.box(Vector3(0.4, 0.5, 0.3), Palette.mat(Color("3d3028")), Vector3(0, 1.6, 0.55)))
	_body.add_child(LowPoly.box(Vector3(0.28, 0.28, 0.28), Palette.mat(Color("b07a58")), Vector3(0, 2.0, 0.5)))
	_body.add_child(LowPoly.box(Vector3(0.06, 0.18, 0.3), Palette.mat(Color("d8402a")), Vector3(0, 2.2, 0.5)))
	# Koła.
	for p in [Vector3(-0.95, 0.42, -0.95), Vector3(0.95, 0.42, -0.95), Vector3(-0.95, 0.42, 0.95), Vector3(0.95, 0.42, 0.95)]:
		var w := Node3D.new()
		w.position = p
		w.add_child(LowPoly.cylinder(0.42, 0.32, tire, Vector3.ZERO, Vector3(0, 0, PI * 0.5), 10))
		_body.add_child(w)
		_wheels.append(w)
	# Światła ostrzegawcze.
	for lx in [-0.55, 0.55]:
		var l := LowPoly.box(Vector3(0.22, 0.14, 0.08), _warn_mat, Vector3(lx, 1.0, -1.42))
		_body.add_child(l)
		_warn_lights.append(l)
	# Czerwona poświata – wróg widoczny w nocy i w burzy.
	var glow_light := OmniLight3D.new()
	glow_light.light_color = Color(1.0, 0.2, 0.1)
	glow_light.light_energy = 1.4
	glow_light.omni_range = 5.5
	glow_light.position = Vector3(0, 1.6, -0.8)
	add_child(glow_light)
	_exclaim = Label3D.new()
	_exclaim.text = "!"
	_exclaim.font_size = 220
	_exclaim.outline_size = 36
	_exclaim.modulate = Color("ff3b2a")
	_exclaim.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_exclaim.no_depth_test = true
	_exclaim.position = Vector3(0, 3.2, 0)
	_exclaim.visible = false
	add_child(_exclaim)
	_smoke = CPUParticles3D.new()
	_smoke.emitting = false
	_smoke.amount = 40
	_smoke.lifetime = 1.6
	_smoke.direction = Vector3(0, 1, 0.3)
	_smoke.spread = 30.0
	_smoke.initial_velocity_min = 1.5
	_smoke.initial_velocity_max = 4.0
	_smoke.gravity = Vector3(0, 0.6, 0)
	_smoke.position = Vector3(0, 1.0, 0)
	var puff := SphereMesh.new()
	puff.radius = 0.4
	puff.height = 0.8
	puff.radial_segments = 6
	puff.rings = 3
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.albedo_color = Color(0.12, 0.1, 0.09, 0.7)
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = smoke_mat
	_smoke.mesh = puff
	add_child(_smoke)


func sync(r: RaiderModel, player_d: float, delta: float) -> void:
	_time += delta
	if not _initialized:
		_shown_x = r.x
		_initialized = true
	_shown_x = lerpf(_shown_x, r.x, 1.0 - exp(-delta / 0.06))
	position = Vector3(_shown_x, 0.0, -(r.d - player_d))
	_wheel_angle -= r.speed / 0.42 * delta
	for w in _wheels:
		w.rotation.x = _wheel_angle
	var warning := r.state == RaiderModel.State.TELEGRAPH or r.state == RaiderModel.State.RAM
	var blink := fmod(_time * 6.0, 1.0) < 0.5
	_exclaim.visible = warning and blink
	Palette.set_glow_energy(_warn_mat, (6.0 if blink else 0.5) if warning else 0.8)
	_body.rotation.z = -r.lateral_velocity * 0.03
	if r.hit_flash > 0.0:
		for m in _hull_mats:
			m.material_override = _flash_mat
	elif not _hull_mats.is_empty() and _hull_mats[0].material_override == _flash_mat:
		_hull_mats[0].material_override = Palette.mat(Color("2b2522"), 0.7, 0.3)
	if r.state == RaiderModel.State.DESTROYED:
		_exclaim.visible = false
		_smoke.emitting = true
		var k := clampf(r.timer / 1.2, 0.0, 1.0)
		_body.rotation = Vector3(k * 1.2, k * 2.5 * r.side, k * 2.0 * r.side)
		_body.position.y = sin(k * PI) * 1.6
		if r.timer > 2.2:
			scale = Vector3.ONE * maxf(0.01, 1.0 - (r.timer - 2.2) / 0.8)
