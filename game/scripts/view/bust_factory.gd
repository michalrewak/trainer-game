class_name BustFactory
extends RefCounted
## Popiersia postaci do okienka „gadającej głowy”: kanciaste, brudne, z mocnym światłem –
## w tym samym stylu co pojazdy. Każde ma węzeł "Jaw" (szczęka rusza się przy mówieniu)
## i opcjonalnie "Spin" (obracająca się ozdoba). Głowa ma ok. 1 m wysokości, środek w (0,0,0).

const RUST_TEX := "res://assets/textures/rusty_metal_02_diff_1k.jpg"
## Szara, ziarnista tekstura jako brud na skórze i szmatach (mnożona przez kolor).
const GRIME_TEX := "res://assets/textures/asphalt_03_diff_1k.jpg"

static var _rust_tex: Texture2D
static var _rust_checked := false
static var _grime_tex: Texture2D
static var _grime_checked := false


static func build(who: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Bust"
	match who:
		Chatter.BARON:
			_baron(root)
		Chatter.SLAVE:
			_slave(root)
		Chatter.PRIEST:
			_priest(root)
		Chatter.RAIDER:
			_raider(root)
		_:
			_mech(root)
	return root


# --- Baron Smalec: szeroka, tłusta twarz, korona z zębatek, złote zęby, monokl ---

static func _baron(root: Node3D) -> void:
	var skin := _m(Color("e0a48e"), 0.45)
	var skin_dark := _m(Color("b8766a"), 0.55)
	var gold := _m(Color("ffc640"), 0.35, 0.9, Color("ffb020"), 0.5)
	var dark := _m(Color("1c1614"), 0.8)
	_box(root, Vector3(1.3, 0.95, 1.0), skin, Vector3(0, 0.05, 0))
	# Policzki i podwójny podbródek.
	for s: float in [-1.0, 1.0]:
		_box(root, Vector3(0.42, 0.45, 0.5), skin, Vector3(s * 0.52, -0.2, 0.32))
		_box(root, Vector3(0.26, 0.1, 0.06), dark, Vector3(s * 0.3, 0.27, 0.53), Vector3(0, 0, -s * 0.4))
		_box(root, Vector3(0.2, 0.13, 0.05), _m(Color("f0e8d8"), 0.3), Vector3(s * 0.3, 0.12, 0.51))
		_box(root, Vector3(0.08, 0.09, 0.05), _m(Color("0c0a0a"), 0.3), Vector3(s * 0.28, 0.11, 0.54))
	_box(root, Vector3(1.15, 0.3, 0.9), skin_dark, Vector3(0, -0.55, 0.08))
	_box(root, Vector3(0.24, 0.22, 0.2), skin_dark, Vector3(0, -0.02, 0.56))
	# Monokl na łańcuszku.
	_cyl(root, 0.13, 0.04, gold, Vector3(0.3, 0.1, 0.56), Vector3(PI * 0.5, 0, 0))
	_cyl(root, 0.012, 0.5, gold, Vector3(0.48, -0.1, 0.5), Vector3(0, 0, 0.5))
	# Usta: szczęka ze złotymi zębami.
	_box(root, Vector3(0.62, 0.1, 0.06), dark, Vector3(0, -0.22, 0.56))
	var jaw := Node3D.new()
	jaw.name = "Jaw"
	jaw.position = Vector3(0, -0.3, 0.5)
	_box(jaw, Vector3(0.66, 0.16, 0.2), skin_dark, Vector3.ZERO)
	for i in 5:
		_box(jaw, Vector3(0.09, 0.08, 0.04), gold, Vector3(-0.22 + i * 0.11, 0.1, 0.09))
	root.add_child(jaw)
	# Korona z zębatek.
	_box(root, Vector3(1.15, 0.16, 0.9), gold, Vector3(0, 0.6, 0))
	for i in 5:
		_box(root, Vector3(0.14, 0.26, 0.14), gold, Vector3(-0.46 + i * 0.23, 0.78, 0.36), Vector3(0, 0, PI * 0.25))
	# Futro i medale na ramionach.
	var fur := _m(Color("3a2a20"), 1.0)
	_box(root, Vector3(2.4, 0.7, 1.0), fur, Vector3(0, -1.1, -0.05))
	for i in 6:
		_box(root, Vector3(0.3, 0.3, 0.3), _m(Color("4a3628"), 1.0), Vector3(-1.0 + i * 0.4, -0.75, 0.3), Vector3(0.4, 0.5, 0.3))
	for i in 3:
		_cyl(root, 0.09, 0.03, gold, Vector3(-0.5 + i * 0.22, -1.0, 0.47), Vector3(PI * 0.5, 0, 0))


# --- Chudy: wychudzony pedalarz w żelaznej obroży ---

static func _slave(root: Node3D) -> void:
	var skin := _m(Color("c4946e"), 0.7)
	var shade := _m(Color("7e5842"), 0.8)
	var iron := _metal(Color("8a8078"))
	var dark := _m(Color("18130f"), 0.8)
	_box(root, Vector3(0.74, 1.0, 0.8), skin, Vector3(0, 0.05, 0))
	for s: float in [-1.0, 1.0]:
		# Zapadnięte policzki, wielkie zmęczone oczy, odstające uszy.
		_box(root, Vector3(0.08, 0.36, 0.3), shade, Vector3(s * 0.36, -0.15, 0.3))
		_box(root, Vector3(0.2, 0.17, 0.05), _m(Color("e8e0d0"), 0.4), Vector3(s * 0.19, 0.15, 0.41))
		_box(root, Vector3(0.08, 0.09, 0.05), dark, Vector3(s * 0.19, 0.13, 0.43))
		_box(root, Vector3(0.24, 0.05, 0.05), shade, Vector3(s * 0.19, 0.04, 0.42))
		_box(root, Vector3(0.1, 0.24, 0.16), skin, Vector3(s * 0.42, 0.1, 0.0))
	_box(root, Vector3(0.14, 0.26, 0.16), skin, Vector3(0, -0.02, 0.45))
	# Zarost i blizna na ogolonej głowie.
	_box(root, Vector3(0.76, 0.34, 0.82), shade, Vector3(0, -0.34, 0.0))
	_box(root, Vector3(0.05, 0.05, 0.5), _m(Color("b84a3a"), 0.6), Vector3(0.16, 0.56, 0.12), Vector3(0, 0.4, 0))
	_box(root, Vector3(0.34, 0.07, 0.05), dark, Vector3(0, -0.26, 0.42))
	var jaw := Node3D.new()
	jaw.name = "Jaw"
	jaw.position = Vector3(0, -0.36, 0.34)
	_box(jaw, Vector3(0.5, 0.16, 0.2), shade, Vector3.ZERO)
	root.add_child(jaw)
	# Chuda szyja, obroża z uchem i łańcuch.
	_box(root, Vector3(0.3, 0.4, 0.3), skin, Vector3(0, -0.65, -0.05))
	_cyl(root, 0.3, 0.16, iron, Vector3(0, -0.72, -0.05), Vector3.ZERO)
	_cyl(root, 0.09, 0.05, iron, Vector3(0, -0.74, 0.3), Vector3(PI * 0.5, 0, 0))
	for i in 4:
		_box(root, Vector3(0.12, 0.05, 0.1), iron, Vector3(0.1 + i * 0.13, -0.84 - i * 0.1, 0.34), Vector3(0, 0, 0.6 if i % 2 == 0 else -0.6))
	_box(root, Vector3(1.5, 0.6, 0.6), _m(Color("5c4e3c"), 1.0), Vector3(0, -1.2, -0.05), Vector3(0, 0, 0.04))
	_box(root, Vector3(0.5, 0.1, 0.62), _m(Color("4a3e30"), 1.0), Vector3(-0.3, -1.0, -0.04), Vector3(0, 0, 0.5))


# --- Zębatka: mechaniczka w goglach spawalniczych, z radiem ---

static func _mech(root: Node3D) -> void:
	var skin := _m(Color("d09a72"), 0.6)
	var dark := _m(Color("1a1614"), 0.7)
	var red := _m(Color("a8382a"), 0.9)
	var lens := _m(Color("1a6a64"), 0.2, 0.3, Color("38e0d0"), 1.6)
	var iron := _metal(Color("9a9088"))
	_box(root, Vector3(0.9, 0.98, 0.86), skin, Vector3(0, 0.05, 0))
	# Chusta na głowie i kucyk.
	_box(root, Vector3(0.96, 0.3, 0.92), red, Vector3(0, 0.46, 0))
	_box(root, Vector3(0.2, 0.2, 0.5), red, Vector3(0.3, 0.5, -0.55), Vector3(0.4, 0.3, 0))
	_box(root, Vector3(0.24, 0.5, 0.24), _m(Color("2a1c14"), 0.9), Vector3(0, 0.2, -0.55), Vector3(0.3, 0, 0))
	# Gogle spawalnicze: dwie tuleje ze świecącymi szkłami.
	_box(root, Vector3(0.94, 0.14, 0.9), dark, Vector3(0, 0.16, 0))
	for s: float in [-1.0, 1.0]:
		_cyl(root, 0.17, 0.2, iron, Vector3(s * 0.21, 0.16, 0.48), Vector3(PI * 0.5, 0, 0))
		_cyl(root, 0.13, 0.22, lens, Vector3(s * 0.21, 0.16, 0.49), Vector3(PI * 0.5, 0, 0))
	_box(root, Vector3(0.14, 0.2, 0.14), skin, Vector3(0, -0.04, 0.46))
	# Smar na policzku i krzywy uśmiech.
	_box(root, Vector3(0.22, 0.08, 0.04), dark, Vector3(-0.26, -0.12, 0.44), Vector3(0, 0, 0.4))
	_box(root, Vector3(0.36, 0.06, 0.04), dark, Vector3(0.03, -0.24, 0.44), Vector3(0, 0, 0.12))
	var jaw := Node3D.new()
	jaw.name = "Jaw"
	jaw.position = Vector3(0, -0.34, 0.36)
	_box(jaw, Vector3(0.6, 0.16, 0.2), skin, Vector3.ZERO)
	root.add_child(jaw)
	# Słuchawka z mikrofonem.
	_cyl(root, 0.17, 0.1, dark, Vector3(0.48, 0.05, 0.0), Vector3(0, 0, PI * 0.5))
	_box(root, Vector3(0.04, 0.04, 0.5), iron, Vector3(0.44, -0.2, 0.25), Vector3(0.5, -0.3, 0))
	_box(root, Vector3(0.1, 0.1, 0.1), lens, Vector3(0.36, -0.3, 0.46))
	# Kombinezon i klucz na ramieniu.
	_box(root, Vector3(0.34, 0.3, 0.34), skin, Vector3(0, -0.6, -0.05))
	_box(root, Vector3(1.7, 0.6, 0.7), _m(Color("3c5450"), 0.95), Vector3(0, -1.1, -0.05))
	_box(root, Vector3(0.1, 0.9, 0.08), iron, Vector3(-0.6, -0.8, 0.3), Vector3(0, 0, 0.5))
	_box(root, Vector3(0.3, 0.2, 0.08), iron, Vector3(-0.36, -0.44, 0.3), Vector3(0, 0, 0.5))


# --- Brat Obrót: kaptur, pobielona twarz, aureola z zębatki, licznik kadencji ---

static func _priest(root: Node3D) -> void:
	var pale := _m(Color("ece6d8"), 0.5)
	var cloth := _m(Color("2c2634"), 1.0)
	var dark := _m(Color("100e12"), 0.8)
	var glow := _m(Color("3a2a10"), 0.4, 0.5, Color("ffb238"), 1.4)
	var iron := _metal(Color("a09888"))
	# Aureola: zębatka kręcąca się za głową.
	var spin := Node3D.new()
	spin.name = "Spin"
	spin.position = Vector3(0, 0.2, -0.5)
	_cyl(spin, 0.95, 0.08, iron, Vector3.ZERO, Vector3(PI * 0.5, 0, 0), 16)
	_cyl(spin, 0.6, 0.1, dark, Vector3.ZERO, Vector3(PI * 0.5, 0, 0), 16)
	for i in 12:
		var a := i * TAU / 12.0
		_box(spin, Vector3(0.2, 0.26, 0.08), iron, Vector3(cos(a) * 1.02, sin(a) * 1.02, 0), Vector3(0, 0, a - PI * 0.5))
	root.add_child(spin)
	_box(root, Vector3(0.8, 1.0, 0.8), pale, Vector3(0, 0.02, 0))
	# Kaptur: góra i boki.
	_box(root, Vector3(1.1, 0.34, 1.05), cloth, Vector3(0, 0.56, -0.06))
	for s: float in [-1.0, 1.0]:
		_box(root, Vector3(0.2, 1.2, 1.0), cloth, Vector3(s * 0.5, 0.0, -0.08), Vector3(0, 0, -s * 0.08))
		_box(root, Vector3(0.18, 0.06, 0.05), dark, Vector3(s * 0.2, 0.14, 0.41), Vector3(0, 0, s * 0.2))
		_box(root, Vector3(0.05, 0.3, 0.04), dark, Vector3(s * 0.2, -0.04, 0.41))
	_box(root, Vector3(0.12, 0.28, 0.14), pale, Vector3(0, -0.02, 0.44))
	# Licznik kadencji na czole jak relikwia.
	_box(root, Vector3(0.34, 0.16, 0.06), dark, Vector3(0, 0.36, 0.42))
	_box(root, Vector3(0.28, 0.1, 0.04), glow, Vector3(0, 0.36, 0.45))
	_box(root, Vector3(0.3, 0.05, 0.04), dark, Vector3(0, -0.26, 0.41))
	var jaw := Node3D.new()
	jaw.name = "Jaw"
	jaw.position = Vector3(0, -0.36, 0.34)
	_box(jaw, Vector3(0.5, 0.16, 0.16), pale, Vector3.ZERO)
	root.add_child(jaw)
	_box(root, Vector3(1.9, 0.75, 0.9), cloth, Vector3(0, -1.05, -0.08))
	# Łańcuch rowerowy na szyi.
	for i in 7:
		_box(root, Vector3(0.14, 0.07, 0.06), iron, Vector3(-0.36 + i * 0.12, -0.72 - absf(i - 3.0) * -0.04 - 0.1, 0.4), Vector3(0, 0, 0.3 if i % 2 == 0 else -0.3))


# --- Iskra: irokez, gogle, maska z filtrami ---

static func _raider(root: Node3D) -> void:
	var skin := _m(Color("b8845e"), 0.7)
	var dark := _m(Color("1a1512"), 0.7)
	var red := _m(Color("5a1810"), 0.6, 0.0, Color("ff3a1a"), 1.2)
	var eye := _m(Color("400a06"), 0.2, 0.2, Color("ff2a1a"), 2.2)
	var iron := _metal(Color("8a8078"))
	_box(root, Vector3(0.86, 1.0, 0.84), skin, Vector3(0, 0.05, 0))
	# Irokez.
	for i in 6:
		_box(root, Vector3(0.1, 0.34 - absf(i - 2.5) * 0.04, 0.16), red, Vector3(0, 0.7, 0.34 - i * 0.16), Vector3(0.1 * (i - 2.5), 0, 0))
	# Gogle z czerwonymi szkłami.
	_box(root, Vector3(0.9, 0.2, 0.88), dark, Vector3(0, 0.18, 0))
	for s: float in [-1.0, 1.0]:
		_box(root, Vector3(0.26, 0.16, 0.06), eye, Vector3(s * 0.2, 0.18, 0.44))
		# Filtry maski.
		_cyl(root, 0.15, 0.24, iron, Vector3(s * 0.3, -0.3, 0.46), Vector3(PI * 0.5, 0, s * 0.4))
		_box(root, Vector3(0.4, 0.4, 0.4), iron, Vector3(s * 1.0, -0.82, 0.0), Vector3(0.6, 0.6, 0.3))
		for k in 2:
			_cyl(root, 0.05, 0.4, iron, Vector3(s * (0.85 + k * 0.3), -0.5, 0.0), Vector3(0, 0, -s * 0.5), 5)
	_box(root, Vector3(0.7, 0.46, 0.5), dark, Vector3(0, -0.24, 0.24))
	var jaw := Node3D.new()
	jaw.name = "Jaw"
	jaw.position = Vector3(0, -0.42, 0.4)
	_box(jaw, Vector3(0.44, 0.14, 0.2), dark, Vector3.ZERO)
	_box(jaw, Vector3(0.3, 0.04, 0.04), iron, Vector3(0, 0.0, 0.11))
	root.add_child(jaw)
	_box(root, Vector3(0.36, 0.3, 0.36), skin, Vector3(0, -0.6, -0.05))
	_box(root, Vector3(1.8, 0.6, 0.7), _m(Color("2c2420"), 0.9), Vector3(0, -1.1, -0.05))


# --- Pomocnicze ------------------------------------------------------------------

static func _m(color: Color, roughness: float = 0.8, metallic: float = 0.0, emission: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if not _grime_checked:
		_grime_checked = true
		if ResourceLoader.exists(GRIME_TEX):
			_grime_tex = load(GRIME_TEX)
	if _grime_tex != null and emission_energy <= 0.0:
		# Brud tylko jako faktura powierzchni (mapa chropowatości) – koloru nie zmienia.
		m.roughness_texture = _grime_tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(1.6, 1.6, 1.6)
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m


## Zardzewiały metal z teksturą (jeśli jest w projekcie).
static func _metal(color: Color) -> StandardMaterial3D:
	var m := _m(color, 0.55, 0.8)
	if not _rust_checked:
		_rust_checked = true
		if ResourceLoader.exists(RUST_TEX):
			_rust_tex = load(RUST_TEX)
	if _rust_tex != null:
		m.albedo_texture = _rust_tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(0.8, 0.8, 0.8)
	return m


static func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _cyl(parent: Node3D, radius: float, height: float, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, sides: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi
