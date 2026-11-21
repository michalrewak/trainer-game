class_name ConvoyPartView
extends Node3D
## Części konwoju Tłustych: ciągnik z tronem Barona, galera (klatka ze skutymi pedalarzami
## i kanistrami czystego paliwa), ogon ze strażnikiem i zrzutnią min oraz sprzęgi.
## Odsłonięty sprzęg pulsuje żółtym pierścieniem i strzałką – „tu strzelaj”.
## Przód pojazdów to -Z (jak cała trasa).

const WAGON_WIDTH := 2.8
const DECK_Y := 1.05
const WHEEL_D := 1.3

var _part: RaiderModel.Part = RaiderModel.Part.NONE
var _body: Node3D
var _wheels: Array[Node3D] = []
var _wheel_angle := 0.0
var _brake_mat: ShaderMaterial
var _flash_mat: ShaderMaterial
var _hull: Array[MeshInstance3D] = []
var _hull_original: Array[Material] = []
var _flashing := false
var _smoke: CPUParticles3D
var _exhausts: Array[CPUParticles3D] = []
var _ring: Node3D
var _arrow: Node3D
var _pin_mat: ShaderMaterial
var _legs: Array[Node3D] = []
var _torsos: Array[Node3D] = []
var _arm: Node3D
var _time := 0.0
var _phase := 0.0

var _rust: ShaderMaterial
var _rust_light: ShaderMaterial
var _dark: ShaderMaterial
var _steel: ShaderMaterial
var _tire: ShaderMaterial
var _red: ShaderMaterial


func build(r: RaiderModel) -> void:
	_part = r.part
	_body = Node3D.new()
	add_child(_body)
	_rust = Palette.mat(Palette.RUST, 0.9, 0.25)
	_rust_light = Palette.mat(Palette.RUST_LIGHT, 0.85, 0.3)
	_dark = Palette.mat(Color("26211f"), 0.8, 0.35)
	_steel = Palette.mat(Color("a8a094"), 0.45, 0.8)
	_tire = Palette.mat(Palette.TIRE, 0.95)
	_red = Palette.mat(Palette.PAINT_RED, 0.7, 0.3)
	# Błysk trafienia: ciepły i krótki – cały biały wagon oślepiał.
	_flash_mat = Palette.glow(Color("ffb070"), 0.9)
	_brake_mat = Palette.glow(Color("ff2a1a"), 1.0).duplicate() as ShaderMaterial
	match _part:
		RaiderModel.Part.TRACTOR:
			_build_tractor(r.variant)
		RaiderModel.Part.GALLEY:
			_build_galley(r.variant)
		RaiderModel.Part.GUARD:
			_build_guard(r.variant)
		_:
			_build_hitch()
	_collect_hull(_body)
	if _part != RaiderModel.Part.HITCH_FRONT and _part != RaiderModel.Part.HITCH_REAR:
		_smoke = _make_smoke(Vector3(0, 2.2, 0), 70, Color(0.1, 0.09, 0.08, 0.5), 0.3)
		_smoke.emitting = false
		add_child(_smoke)


func sync(r: RaiderModel, player_d: float, delta: float) -> void:
	_time += delta
	position = Vector3(r.x, 0.0, -(r.d - player_d))
	_wheel_angle -= r.speed / (WHEEL_D * 0.5) * delta
	for w in _wheels:
		w.rotation.x = _wheel_angle
	Palette.set_glow_energy(_brake_mat, 7.0 if r.braking else 0.9)
	_set_flash(r.hit_flash > 0.0)
	# Cząsteczki tylko w drzewie sceny (testy budują widok także poza nim).
	var in_tree := is_inside_tree()
	for e in _exhausts:
		e.emitting = in_tree and r.is_alive() and not r.detached
		e.speed_scale = 0.6 if r.braking else 1.6
	# Pedalarze w klatce: gnają, gdy konwój ucieka; ledwo kręcą, gdy hamuje.
	_phase += delta * (4.0 if r.braking else 11.0) * (0.3 if r.detached else 1.0)
	for i in _legs.size():
		_legs[i].rotation.x = sin(_phase + i * 1.3) * 0.7
		_torsos[i].position.y = 0.42 + 0.04 * sin(_phase * 2.0 + i * 1.3)
		# Po odcięciu machają rękami – „zabierz nas!”.
		_torsos[i].rotation.z = sin(_time * 7.0 + i) * 0.25 if r.detached else 0.0
	if _arm != null:
		_arm.rotation.x = -0.6 + sin(_time * (9.0 if not r.braking else 3.0)) * 0.6
	if _ring != null:
		var open := r.exposed and r.is_alive()
		_ring.visible = open
		_arrow.visible = open
		var pulse := 1.0 + 0.18 * sin(_time * 9.0)
		_ring.scale = Vector3(pulse, 1.0, pulse)
		_arrow.position.y = 3.6 + 0.3 * sin(_time * 6.0)
		Palette.set_glow_energy(_pin_mat, 5.0 if open else 1.2)
	if _smoke != null:
		_smoke.emitting = in_tree and ((r.max_hp > 1 and r.hp * 2 < r.max_hp) or not r.is_alive())
	if r.state == RaiderModel.State.DESTROYED:
		var k := clampf(r.timer / 1.4, 0.0, 1.0)
		if _ring != null:
			_body.visible = r.timer < 0.12
			_ring.visible = false
			_arrow.visible = false
		else:
			_body.rotation = Vector3(-k * 0.18, 0.0, k * 0.45)
			_body.position.y = -k * 0.5
		if r.timer > 2.2:
			scale = Vector3.ONE * maxf(0.01, 1.0 - (r.timer - 2.2) / 0.8)
	elif r.detached and _part == RaiderModel.Part.GUARD:
		# Odczepiony ogon wężykuje bez napędu.
		_body.rotation.y = sin(_time * 3.2) * 0.2
		_body.rotation.z = sin(_time * 2.1) * 0.08


# --- Ciągnik -------------------------------------------------------------------

func _build_tractor(tier: int) -> void:
	var front := -ConvoyDirector.TRACTOR_HALF_M
	var back := ConvoyDirector.TRACTOR_HALF_M
	_frame(front + 0.6, back - 0.2, [front + 1.5, back - 2.4, back - 1.0])
	# Kabina i maska – bryły z blach, okna zaspawane.
	_body.add_child(LowPoly.box(Vector3(2.5, 1.5, 2.6), _rust, Vector3(0, DECK_Y + 0.95, front + 1.7)))
	_body.add_child(LowPoly.box(Vector3(2.6, 1.6, 2.2), _dark, Vector3(0, DECK_Y + 1.25, front + 4.0)))
	_body.add_child(LowPoly.box(Vector3(2.2, 0.5, 0.08), _steel, Vector3(0, DECK_Y + 1.6, front + 2.92), Vector3(-0.25, 0, 0)))
	for s: float in [-1.0, 1.0]:
		_body.add_child(LowPoly.box(Vector3(0.08, 0.45, 1.3), _steel, Vector3(s * 1.31, DECK_Y + 1.6, front + 4.0)))
		_body.add_child(LowPoly.box(Vector3(0.5, 0.25, 0.1), Palette.glow(Color("ffe2a0"), 2.5), Vector3(s * 0.85, DECK_Y + 0.75, front + 0.38)))
	# Lemiesz z kolcami – konwój taranuje wszystko przed sobą.
	for s: float in [-1.0, 1.0]:
		_body.add_child(LowPoly.box(Vector3(1.7, 1.2, 0.14), _steel, Vector3(s * 0.75, 0.85, front - 0.15), Vector3(0, s * 0.5, 0)))
	for i in 7:
		_body.add_child(LowPoly.cylinder(0.07, 0.7, _steel, Vector3(-1.2 + i * 0.4, 0.9, front - 0.55 + absf(i - 3.0) * 0.2), Vector3(PI * 0.5, 0, 0), 5))
	# Kominy z czarnym dymem.
	for s: float in [-1.0, 1.0]:
		_body.add_child(LowPoly.cylinder(0.16, 2.4, _dark, Vector3(s * 1.15, DECK_Y + 2.6, front + 5.3), Vector3.ZERO, 8))
		var ex := _make_smoke(Vector3(s * 1.15, DECK_Y + 3.9, front + 5.3), 26, Color(0.08, 0.07, 0.07, 0.6), 0.32)
		add_child(ex)
		_exhausts.append(ex)
	# Tron Barona na pace: on nie pedałuje.
	var tz := back - 1.4
	_body.add_child(LowPoly.box(Vector3(2.6, 0.25, 2.6), _rust_light, Vector3(0, DECK_Y + 0.6, tz)))
	_body.add_child(LowPoly.box(Vector3(1.5, 0.5, 1.2), _red, Vector3(0, DECK_Y + 0.95, tz)))
	_body.add_child(LowPoly.box(Vector3(1.7, 1.9, 0.18), _dark, Vector3(0, DECK_Y + 1.9, tz + 0.7)))
	for i in 5:
		_body.add_child(LowPoly.cylinder(0.06, 0.6, _steel, Vector3(-0.7 + i * 0.35, DECK_Y + 3.1, tz + 0.7), Vector3.ZERO, 5))
	var skin := Palette.mat(Color("c98f7a"), 0.8)
	var belly := SphereMesh.new()
	belly.radius = 0.5
	belly.height = 1.0
	belly.radial_segments = 10
	belly.rings = 5
	_body.add_child(LowPoly.mesh_instance(belly, skin, Vector3(0, DECK_Y + 1.75, tz + 0.05), Vector3(1.5, 1.25, 1.3)))
	_body.add_child(LowPoly.box(Vector3(0.6, 0.5, 0.55), skin, Vector3(0, DECK_Y + 2.65, tz)))
	_body.add_child(LowPoly.box(Vector3(0.7, 0.14, 0.62), Palette.glow(Color("ffc640"), 1.8), Vector3(0, DECK_Y + 2.98, tz)))
	for i in 4:
		_body.add_child(LowPoly.box(Vector3(0.1, 0.2, 0.1), Palette.glow(Color("ffc640"), 1.8), Vector3(-0.27 + i * 0.18, DECK_Y + 3.12, tz - 0.22)))
	_body.add_child(LowPoly.box(Vector3(0.5, 0.1, 0.08), _dark, Vector3(0, DECK_Y + 2.72, tz - 0.29)))
	# Ręka z batem / megafonem – macha, gdy pogania.
	_arm = Node3D.new()
	_arm.position = Vector3(0.75, DECK_Y + 2.2, tz)
	_arm.add_child(LowPoly.box(Vector3(0.22, 0.22, 0.9), skin, Vector3(0, 0, -0.45)))
	_arm.add_child(LowPoly.tube(Vector3(0, 0, -0.9), Vector3(0, 0.3, -2.3), 0.035, _dark))
	_body.add_child(_arm)
	# Proporce i tylne światła.
	for s: float in [-1.0, 1.0]:
		_body.add_child(LowPoly.tube(Vector3(s * 1.3, DECK_Y + 0.7, back - 0.3), Vector3(s * 1.3, DECK_Y + 4.0 + tier * 0.4, back - 0.3), 0.05, _dark))
		_body.add_child(LowPoly.box(Vector3(0.05, 0.9, 1.3), _red, Vector3(s * 1.3, DECK_Y + 3.5 + tier * 0.4, back + 0.35)))
		_body.add_child(LowPoly.box(Vector3(0.45, 0.22, 0.08), _brake_mat, Vector3(s * 0.95, DECK_Y + 0.35, back + 0.02)))
	_glow_light(Color(1.0, 0.25, 0.1), 2.0, Vector3(0, 3.6, 0), 9.0)


# --- Galera --------------------------------------------------------------------

func _build_galley(_tier: int) -> void:
	var front := -ConvoyDirector.GALLEY_HALF_M
	var back := ConvoyDirector.GALLEY_HALF_M
	_frame(front, back, [front + 1.3, 0.0, back - 1.3])
	_body.add_child(LowPoly.box(Vector3(WAGON_WIDTH, 0.14, back - front), _rust_light, Vector3(0, DECK_Y + 0.22, 0)))
	# Klatka bez dachu z blachy – z góry widać ludzi w środku.
	var cage_front := front + 0.25
	var cage_back := 1.7
	var top := DECK_Y + 2.25
	for s: float in [-1.0, 1.0]:
		var z := cage_front
		while z <= cage_back + 0.01:
			_body.add_child(LowPoly.cylinder(0.045, top - DECK_Y - 0.25, _steel, Vector3(s * 1.33, (top + DECK_Y + 0.25) * 0.5, z), Vector3.ZERO, 5))
			z += 0.62
		_body.add_child(LowPoly.box(Vector3(0.1, 0.1, cage_back - cage_front), _dark, Vector3(s * 1.33, top, (cage_front + cage_back) * 0.5)))
	for z: float in [cage_front, (cage_front + cage_back) * 0.5, cage_back]:
		_body.add_child(LowPoly.box(Vector3(WAGON_WIDTH - 0.1, 0.1, 0.1), _dark, Vector3(0, top, z)))
	# Pedalarze przykuci do korb: trzy rzędy po dwóch.
	var rags: Array[Color] = [Color("6a5a44"), Color("584a3c"), Color("7a6248"), Color("4e463c")]
	var skins: Array[Color] = [Color("b07a58"), Color("8a5a40"), Color("c89a76"), Color("6e4a36")]
	var n := 0
	for row in 3:
		for s: float in [-1.0, 1.0]:
			var seat := Node3D.new()
			seat.position = Vector3(s * 0.62, DECK_Y + 0.3, cage_front + 0.9 + row * 1.75)
			seat.add_child(LowPoly.box(Vector3(0.5, 0.12, 0.45), _dark, Vector3(0, 0.2, 0.15)))
			var torso := Node3D.new()
			torso.position = Vector3(0, 0.42, 0.12)
			torso.add_child(LowPoly.box(Vector3(0.42, 0.52, 0.26), Palette.mat(rags[n % 4], 0.95), Vector3(0, 0.26, 0)))
			torso.add_child(LowPoly.box(Vector3(0.27, 0.27, 0.27), Palette.mat(skins[n % 4], 0.85), Vector3(0, 0.68, -0.02)))
			# Żelazna obroża i ręce w górze, gdy wołają o ratunek.
			torso.add_child(LowPoly.box(Vector3(0.34, 0.07, 0.34), _steel, Vector3(0, 0.52, -0.02)))
			for a: float in [-1.0, 1.0]:
				torso.add_child(LowPoly.box(Vector3(0.1, 0.1, 0.5), Palette.mat(skins[n % 4], 0.85), Vector3(a * 0.27, 0.36, -0.28)))
			seat.add_child(torso)
			var legs := Node3D.new()
			legs.position = Vector3(0, 0.3, -0.05)
			for a: float in [-1.0, 1.0]:
				legs.add_child(LowPoly.box(Vector3(0.12, 0.12, 0.55), Palette.mat(rags[(n + 1) % 4], 0.95), Vector3(a * 0.13, a * 0.08, -0.3)))
			seat.add_child(legs)
			# Korba generatora i łańcuch do pręta klatki.
			seat.add_child(LowPoly.cylinder(0.16, 0.08, _steel, Vector3(0, 0.3, -0.62), Vector3(0, 0, PI * 0.5), 8))
			seat.add_child(LowPoly.tube(Vector3(0, 0.95, 0.1), Vector3(s * 0.7, 1.4, 0.1), 0.025, _dark))
			_body.add_child(seat)
			_legs.append(legs)
			_torsos.append(torso)
			n += 1
	# Wał napędowy przez środek – to oni ciągną całą kolumnę.
	_body.add_child(LowPoly.cylinder(0.09, cage_back - cage_front, Palette.glow(Palette.GENERATOR_GLOW, 0.9), Vector3(0, DECK_Y + 0.42, (cage_front + cage_back) * 0.5), Vector3(PI * 0.5, 0, 0), 8))
	# Zaplombowane kanistry czystego paliwa z tyłu wagonu.
	var seal := Palette.glow(Color("ff8a3a"), 1.6)
	for row in 2:
		for col in 3:
			var p := Vector3(-0.8 + col * 0.8, DECK_Y + 0.72 + row * 0.02, cage_back + 0.75 + row * 0.9)
			_body.add_child(LowPoly.box(Vector3(0.6, 0.85, 0.5), _red, p))
			_body.add_child(LowPoly.box(Vector3(0.62, 0.1, 0.52), seal, p + Vector3(0, 0.2, 0)))
			_body.add_child(LowPoly.cylinder(0.08, 0.14, _steel, p + Vector3(0.15, 0.48, 0), Vector3.ZERO, 6))
	_body.add_child(LowPoly.box(Vector3(WAGON_WIDTH, 0.5, 0.1), _rust, Vector3(0, DECK_Y + 0.55, back - 0.05)))
	for s: float in [-1.0, 1.0]:
		_body.add_child(LowPoly.box(Vector3(0.45, 0.2, 0.08), _brake_mat, Vector3(s * 0.95, DECK_Y + 0.5, back + 0.02)))
	# Latarnia nad klatką – ludzi widać także nocą.
	_body.add_child(LowPoly.box(Vector3(0.25, 0.25, 0.25), Palette.glow(Color("ffd9a0"), 3.0), Vector3(0, top + 0.2, (cage_front + cage_back) * 0.5)))
	_glow_light(Color(1.0, 0.8, 0.55), 2.2, Vector3(0, top + 0.6, -1.0), 8.0)


# --- Ogon ----------------------------------------------------------------------

func _build_guard(tier: int) -> void:
	var front := -ConvoyDirector.GUARD_HALF_M
	var back := ConvoyDirector.GUARD_HALF_M
	_frame(front, back, [front + 1.2, back - 1.2])
	_body.add_child(LowPoly.box(Vector3(2.7, 1.6, back - front - 0.5), _rust, Vector3(0, DECK_Y + 1.0, -0.1)))
	for s: float in [-1.0, 1.0]:
		# Burty z łat i szczeliny strzelnicze.
		_body.add_child(LowPoly.box(Vector3(0.1, 1.1, 2.6), _rust_light, Vector3(s * 1.4, DECK_Y + 0.9, -1.2), Vector3(0, 0, s * 0.06)))
		_body.add_child(LowPoly.box(Vector3(0.1, 0.9, 2.2), _dark, Vector3(s * 1.42, DECK_Y + 1.1, 1.5), Vector3(0, 0, -s * 0.05)))
		_body.add_child(LowPoly.box(Vector3(0.06, 0.14, 0.9), Palette.glow(Color("ff5a2a"), 0.8), Vector3(s * 1.47, DECK_Y + 1.35, -0.4)))
		_body.add_child(LowPoly.box(Vector3(0.45, 0.22, 0.08), _brake_mat, Vector3(s * 0.95, DECK_Y + 0.45, back - 0.2)))
	# Wieżyczka strażnika z lufą do tyłu.
	_body.add_child(LowPoly.cylinder(0.7, 0.6, _dark, Vector3(0, DECK_Y + 2.1, -1.0), Vector3.ZERO, 10))
	_body.add_child(LowPoly.cylinder(0.1, 1.6 + 0.2 * tier, _steel, Vector3(0, DECK_Y + 2.2, 0.0), Vector3(PI * 0.5, 0, 0), 8))
	_body.add_child(LowPoly.box(Vector3(0.34, 0.4, 0.3), Palette.mat(Color("3d3028")), Vector3(0, DECK_Y + 2.6, -1.0)))
	_body.add_child(LowPoly.box(Vector3(0.26, 0.26, 0.26), Palette.mat(Color("b07a58")), Vector3(0, DECK_Y + 2.93, -1.0)))
	_body.add_child(LowPoly.box(Vector3(0.06, 0.2, 0.3), Palette.mat(Color("d8402a")), Vector3(0, DECK_Y + 3.14, -1.0)))
	# Zrzutnia min: rampa i beczki z czerwonym paskiem.
	_body.add_child(LowPoly.box(Vector3(1.6, 0.1, 1.9), _steel, Vector3(0, DECK_Y + 1.45, back - 0.7), Vector3(0.5, 0, 0)))
	var stripe := Palette.glow(Color("ff3020"), 2.2)
	for i in 3:
		var p := Vector3(-0.6 + i * 0.6, DECK_Y + 2.1, 1.2)
		_body.add_child(LowPoly.cylinder(0.27, 0.6, _dark, p, Vector3.ZERO, 8))
		_body.add_child(LowPoly.cylinder(0.28, 0.12, stripe, p, Vector3.ZERO, 8))
	for i in 6:
		_body.add_child(LowPoly.cylinder(0.06, 0.6, _steel, Vector3(-1.1 + i * 0.44, 0.75, back + 0.2), Vector3(PI * 0.5, 0, 0), 5))
	# Szperacz świecący do tyłu, na ścigającego.
	_body.add_child(LowPoly.cylinder(0.3, 0.3, Palette.glow(Color("fff0c0"), 3.5), Vector3(0, DECK_Y + 2.45, back - 0.9), Vector3(PI * 0.5, 0, 0), 8))
	_glow_light(Color(1.0, 0.2, 0.1), 1.8, Vector3(0, 3.4, 1.0), 8.0)


# --- Sprzęg --------------------------------------------------------------------

func _build_hitch() -> void:
	_pin_mat = Palette.glow(Color("ffc21a"), 1.2).duplicate() as ShaderMaterial
	_body.add_child(LowPoly.box(Vector3(0.28, 0.28, 2.7), _steel, Vector3(0, DECK_Y, 0)))
	for i in 4:
		_body.add_child(LowPoly.box(Vector3(0.5, 0.12, 0.34), _dark, Vector3(0, DECK_Y - 0.2, -0.9 + i * 0.6), Vector3(0, 0, 0.5 if i % 2 == 0 else -0.5)))
	# Sworzeń – słaby punkt, w który trzeba trafić.
	_body.add_child(LowPoly.cylinder(0.24, 0.9, _pin_mat, Vector3(0, DECK_Y + 0.15, 0), Vector3.ZERO, 8))
	_body.add_child(LowPoly.box(Vector3(0.7, 0.14, 0.7), _pin_mat, Vector3(0, DECK_Y + 0.65, 0), Vector3(0, PI * 0.25, 0)))
	var mark := Palette.glow(Color("ffd21a"), 2.6)
	_ring = Node3D.new()
	_ring.position = Vector3(0, 0.12, 0)
	var torus := TorusMesh.new()
	torus.inner_radius = 1.25
	torus.outer_radius = 1.5
	torus.rings = 24
	torus.ring_segments = 4
	_ring.add_child(LowPoly.mesh_instance(torus, mark))
	_ring.visible = false
	add_child(_ring)
	_arrow = Node3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.42
	cone.bottom_radius = 0.0
	cone.height = 0.9
	cone.radial_segments = 4
	_arrow.add_child(LowPoly.mesh_instance(cone, mark))
	_arrow.position = Vector3(0, 4.4, 0)
	_arrow.visible = false
	add_child(_arrow)


# --- Wspólne -------------------------------------------------------------------

## Rama wagonu z osiami i kołami terenowymi.
func _frame(front: float, back: float, axles: Array) -> void:
	_body.add_child(LowPoly.box(Vector3(WAGON_WIDTH - 0.5, 0.3, back - front), _dark, Vector3(0, DECK_Y - 0.05, (front + back) * 0.5)))
	for az: float in axles:
		_body.add_child(LowPoly.cylinder(0.09, WAGON_WIDTH + 0.3, _dark, Vector3(0, WHEEL_D * 0.5, az), Vector3(0, 0, PI * 0.5), 8))
		for s: float in [-1.0, 1.0]:
			var w := Node3D.new()
			w.position = Vector3(s * (WAGON_WIDTH * 0.5 + 0.1), WHEEL_D * 0.5, az)
			var model := KenneyModels.buggy_wheel(s, WHEEL_D)
			if model != null:
				w.add_child(model)
			else:
				w.add_child(LowPoly.cylinder(WHEEL_D * 0.5, 0.45, _tire, Vector3.ZERO, Vector3(0, 0, PI * 0.5), 10))
				w.add_child(LowPoly.box(Vector3(0.47, 0.2, 0.9), _steel))
			_body.add_child(w)
			_wheels.append(w)
			# Błotnik z blachy nad kołem.
			_body.add_child(LowPoly.box(Vector3(0.55, 0.06, 1.5), _rust_light, Vector3(s * (WAGON_WIDTH * 0.5 + 0.1), WHEEL_D + 0.08, az)))


func _glow_light(color: Color, energy: float, pos: Vector3, reach: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = reach
	l.position = pos
	add_child(l)


func _make_smoke(pos: Vector3, amount: int, color: Color, size: float) -> CPUParticles3D:
	var s := CPUParticles3D.new()
	s.amount = amount
	s.lifetime = 1.8
	s.direction = Vector3(0, 1, 0.6)
	s.spread = 22.0
	s.initial_velocity_min = 1.5
	s.initial_velocity_max = 4.0
	s.gravity = Vector3(0, 0.8, 3.0)
	s.position = pos
	var puff := SphereMesh.new()
	puff.radius = size
	puff.height = size * 2.0
	puff.radial_segments = 6
	puff.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = m
	s.mesh = puff
	return s


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
