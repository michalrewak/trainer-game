class_name RaiderView
extends Node3D
## Pojazd gangu: seryjny wóz (sedan, SUV, pickup) przerobiony na taran – osmalony lakier,
## kolczasty zderzak, płyta taranująca od strony gracza, zaspawane okna, kominy wydechu.
## Bez modeli Kenney zostaje prosta bryła. Ostrzeżenie przed atakiem: migające czerwone
## światła i „!” nad pojazdem.

var _body: Node3D
var _warn_mat: ShaderMaterial
var _flash_mat: ShaderMaterial
## Siatki kadłuba i ich materiały – do białego błysku po trafieniu.
var _hull: Array[MeshInstance3D] = []
var _hull_original: Array[Material] = []
var _flashing := false
var _exclaim: Label3D
var _wheels: Array[Node3D] = []
var _wheel_radius := 0.42
var _smoke: CPUParticles3D
var _shown_x := 0.0
var _initialized := false
var _wheel_angle := 0.0
var _time := 0.0


func build(variant: int, side: int) -> void:
	_body = Node3D.new()
	add_child(_body)
	var rust := Palette.mat(Palette.RUST, 0.9, 0.2)
	var dark := Palette.mat(Color("2a2422"), 0.8, 0.3)
	var steel := Palette.mat(Color("a8a094"), 0.45, 0.8)
	_flash_mat = Palette.glow(Color("ffffff"), 4.0)
	_warn_mat = Palette.glow(Color("ff2a1a"), 3.0).duplicate() as ShaderMaterial

	# Kadłub: model auta albo zapasowa bryła.
	var size := Vector3(2.0, 1.5, 3.6)
	var car := KenneyModels.raider_car(variant)
	if car != null:
		_body.add_child(car)
		size = car.get_meta("size")
		for w: Node3D in car.get_meta("wheels"):
			_wheels.append(w)
		_wheel_radius = maxf(0.3, size.y * 0.24)
		_collect_hull(car)
	else:
		var hull_colors: Array[Color] = [Color("2b2522"), Color("4a1f1a"), Color("33302a")]
		var box := LowPoly.box(Vector3(1.8, 0.7, 3.2), Palette.mat(hull_colors[posmod(variant, 3)], 0.7, 0.3), Vector3(0, 0.8, 0))
		_body.add_child(box)
		_body.add_child(LowPoly.box(Vector3(1.5, 0.5, 1.5), rust, Vector3(0, 1.35, 0.3)))
		_collect_hull(box)
		for p in [Vector3(-0.95, 0.42, -1.0), Vector3(0.95, 0.42, -1.0), Vector3(-0.95, 0.42, 1.0), Vector3(0.95, 0.42, 1.0)]:
			var w := Node3D.new()
			w.position = p
			w.add_child(LowPoly.cylinder(0.42, 0.32, Palette.mat(Palette.TIRE), Vector3.ZERO, Vector3(0, 0, PI * 0.5), 10))
			_body.add_child(w)
			_wheels.append(w)

	var hw := size.x * 0.5
	var front := -size.z * 0.5
	var back := size.z * 0.5
	var top := size.y

	# Kolczasty zderzak-taran z przodu.
	_body.add_child(LowPoly.box(Vector3(size.x + 0.2, 0.42, 0.16), rust, Vector3(0, 0.55, front - 0.1)))
	_body.add_child(LowPoly.box(Vector3(size.x * 0.7, 0.3, 0.14), dark, Vector3(0, 0.95, front - 0.05), Vector3(-0.35, 0, 0)))
	for i in 5:
		_body.add_child(LowPoly.cylinder(0.06, 0.55, steel, Vector3(-hw + 0.15 + i * (size.x - 0.3) / 4.0, 0.55, front - 0.4), Vector3(PI * 0.5, 0, 0), 5))
	# Płyta taranująca z kolcami – po stronie gracza (przeciwnej do strony ataku).
	var ram_x := -side * (hw + 0.08)
	_body.add_child(LowPoly.box(Vector3(0.14, 0.75, size.z * 0.62), rust, Vector3(ram_x, 0.8, 0)))
	for i in 4:
		_body.add_child(LowPoly.cylinder(0.07, 0.5, steel, Vector3(ram_x - side * 0.26, 0.8, -size.z * 0.24 + i * size.z * 0.16), Vector3(0, 0, PI * 0.5), 5))
	# Zaspawane okna: blachy na szybie i bokach kabiny.
	_body.add_child(LowPoly.box(Vector3(size.x * 0.78, 0.5, 0.06), dark, Vector3(0, top * 0.74, front + size.z * 0.33), Vector3(-0.6, 0, 0)))
	for s: float in [-1.0, 1.0]:
		_body.add_child(LowPoly.box(Vector3(0.06, 0.34, size.z * 0.34), dark, Vector3(s * (hw - 0.04), top * 0.74, size.z * 0.06)))
	# Dach: klatka strzelca z blachą.
	_body.add_child(LowPoly.box(Vector3(size.x * 0.6, 0.06, size.z * 0.3), rust, Vector3(0, top + 0.05, size.z * 0.08)))
	for s: float in [-1.0, 1.0]:
		_body.add_child(LowPoly.tube(Vector3(s * hw * 0.55, top + 0.05, size.z * 0.2), Vector3(s * hw * 0.45, top + 0.6, size.z * 0.12), 0.04, steel))
	_body.add_child(LowPoly.tube(Vector3(-hw * 0.45, top + 0.6, size.z * 0.12), Vector3(hw * 0.45, top + 0.6, size.z * 0.12), 0.04, steel))
	# Kierowca-strzelec z irokezem wystaje z dachu.
	_body.add_child(LowPoly.box(Vector3(0.42, 0.45, 0.3), Palette.mat(Color("3d3028")), Vector3(0, top + 0.3, size.z * 0.05)))
	_body.add_child(LowPoly.box(Vector3(0.28, 0.28, 0.28), Palette.mat(Color("b07a58")), Vector3(0, top + 0.66, size.z * 0.02)))
	_body.add_child(LowPoly.box(Vector3(0.06, 0.2, 0.32), Palette.mat(Color("d8402a")), Vector3(0, top + 0.88, size.z * 0.02)))
	# Kominy wydechu z tyłu i kolce na klapie.
	for s: float in [-1.0, 1.0]:
		_body.add_child(LowPoly.tube(Vector3(s * (hw - 0.1), 0.6, back - 0.3), Vector3(s * (hw - 0.05), top + 0.75, back - 0.1), 0.07, dark))
	for i in 3:
		_body.add_child(LowPoly.cylinder(0.05, 0.4, steel, Vector3(-0.5 + i * 0.5, 0.7, back + 0.15), Vector3(PI * 0.5, 0, 0), 5))
	# Światła ostrzegawcze (czerwone „oczy”) z przodu i z tyłu.
	for lx: float in [-hw * 0.6, hw * 0.6]:
		_body.add_child(LowPoly.box(Vector3(0.26, 0.14, 0.08), _warn_mat, Vector3(lx, 0.82, front - 0.2)))
		_body.add_child(LowPoly.box(Vector3(0.22, 0.12, 0.06), _warn_mat, Vector3(lx, 0.8, back + 0.04)))
	# Czerwona poświata – wróg widoczny w nocy i w burzy.
	var glow_light := OmniLight3D.new()
	glow_light.light_color = Color(1.0, 0.2, 0.1)
	glow_light.light_energy = 1.4
	glow_light.omni_range = 6.0
	glow_light.position = Vector3(0, top + 0.4, front * 0.5)
	add_child(glow_light)

	_exclaim = Label3D.new()
	_exclaim.text = "!"
	_exclaim.font_size = 220
	_exclaim.outline_size = 36
	_exclaim.modulate = Color("ff3b2a")
	_exclaim.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_exclaim.no_depth_test = true
	_exclaim.position = Vector3(0, top + 2.0, 0)
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
	_wheel_angle += r.speed / _wheel_radius * delta
	for w in _wheels:
		w.rotation.x = _wheel_angle
	var warning := r.state == RaiderModel.State.TELEGRAPH or r.state == RaiderModel.State.RAM
	var blink := fmod(_time * 6.0, 1.0) < 0.5
	_exclaim.visible = warning and blink
	Palette.set_glow_energy(_warn_mat, (6.0 if blink else 0.5) if warning else 1.2)
	_body.rotation.z = -r.lateral_velocity * 0.03
	_set_flash(r.hit_flash > 0.0)
	if r.state == RaiderModel.State.DESTROYED:
		_exclaim.visible = false
		_smoke.emitting = true
		var k := clampf(r.timer / 1.2, 0.0, 1.0)
		_body.rotation = Vector3(k * 1.2, k * 2.5 * r.side, k * 2.0 * r.side)
		_body.position.y = sin(k * PI) * 1.6
		if r.timer > 2.2:
			scale = Vector3.ONE * maxf(0.01, 1.0 - (r.timer - 2.2) / 0.8)


func _collect_hull(node: Node) -> void:
	if node is MeshInstance3D:
		_hull.append(node)
		_hull_original.append((node as MeshInstance3D).material_override)
	for child in node.get_children():
		_collect_hull(child)


func _set_flash(on: bool) -> void:
	if on == _flashing:
		return
	_flashing = on
	for i in _hull.size():
		_hull[i].material_override = _flash_mat if on else _hull_original[i]
