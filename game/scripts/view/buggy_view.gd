class_name BuggyView
extends Node3D
## Jednoosiowy buggy z pedałowym generatorem (z prymitywów): dwa duże koła na jednej osi,
## płoza z przodu, klatka z rur, kierowca kręcący korbą generatora (tempo = kadencja).
## Widok tylko odwzorowuje stan symulacji: pozycję w pasie, prędkość, przechył, uderzenia.

const WHEEL_RADIUS := 0.62

var _body: Node3D
var _wheels: Array[Node3D] = []
var _crank: Node3D
var _legs: Array[Node3D] = []
var _flag: Node3D
var _dust: CPUParticles3D
var _coil_mat: StandardMaterial3D
var _turret: Node3D
var _muzzle: MeshInstance3D
var _muzzle_t := 0.0
var _shield: MeshInstance3D
var _shield_mat: ShaderMaterial
var _shield_flash := 0.0
var _flash := 0.0
var _wheel_angle := 0.0
var _crank_angle := 0.0
var _prev_speed := 0.0
var _pitch := 0.0
var _time := 0.0


func _ready() -> void:
	_build()


func sync(sim: RunSimulation, cadence_rpm: float, power_w: float, delta: float) -> void:
	_time += delta
	position.x = sim.lanes.x_m
	var v := sim.vehicle.speed_mps
	_wheel_angle -= v / WHEEL_RADIUS * delta
	for w in _wheels:
		w.rotation.x = _wheel_angle
	_crank_angle += cadence_rpm / 60.0 * TAU * delta
	_crank.rotation.x = _crank_angle
	for i in _legs.size():
		var phase := _crank_angle + PI * i
		_legs[i].rotation.x = -0.6 + 0.45 * sin(phase)
	# Przechył przy zmianie pasa, „nurkowanie” przy hamowaniu/przyspieszaniu.
	var roll := clampf(-sim.lanes.lateral_velocity_mps * 0.03, -0.22, 0.22)
	var accel := (v - _prev_speed) / maxf(delta, 1e-4)
	_prev_speed = v
	_pitch = lerpf(_pitch, clampf(accel * 0.03, -0.12, 0.08), 1.0 - exp(-delta * 6.0))
	_body.rotation = Vector3(_pitch, -sim.lanes.lateral_velocity_mps * 0.02, roll)
	_body.position.y = 0.02 * sin(_time * 18.0) * clampf(v / 10.0, 0.0, 1.0)
	_flag.rotation.x = -clampf(v / 12.0, 0.0, 1.0) * 1.1 + 0.06 * sin(_time * 9.0)
	# Generator świeci mocniej przy większej mocy.
	_coil_mat.emission_energy_multiplier = 0.4 + clampf(power_w / 300.0, 0.0, 1.6) * 2.0
	# Kurz spod kół.
	_dust.emitting = v > 1.0
	_dust.speed_scale = clampf(v / 9.0, 0.3, 1.5)
	# Błysk po uderzeniu.
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		# Po końcu migania pojazd MUSI być widoczny (wcześniej znikał na resztę wyprawy).
		_body.visible = _flash <= 0.0 or fmod(_flash, 0.14) > 0.05


func on_hit() -> void:
	_flash = 1.2


## Wieżyczka obraca się do celu (pozycja lokalna względem pojazdu), tarcza pokazuje poziom.
func update_combat(target_local: Variant, shield_level: float, delta: float) -> void:
	if target_local is Vector3:
		var t: Vector3 = target_local
		var dx := t.x - position.x
		var dz := t.z
		var yaw := atan2(-dx, -dz)
		_turret.rotation.y = lerp_angle(_turret.rotation.y, yaw, 1.0 - exp(-delta * 12.0))
	else:
		_turret.rotation.y = lerp_angle(_turret.rotation.y, 0.0, 1.0 - exp(-delta * 3.0))
	_muzzle_t = maxf(0.0, _muzzle_t - delta)
	_muzzle.visible = _muzzle_t > 0.0
	_shield_flash = maxf(0.0, _shield_flash - delta * 2.5)
	_shield_mat.set_shader_parameter("strength", clampf(shield_level, 0.0, 1.0))
	_shield_mat.set_shader_parameter("flash", _shield_flash)
	_shield.visible = shield_level > 0.05 or _shield_flash > 0.0


func muzzle_flash() -> void:
	_muzzle_t = 0.07


## Moduły z garażu (etap 3) – każdy widocznie zmienia sylwetkę pojazdu.
func apply_loadout(loadout: Loadout) -> void:
	var old := _body.get_node_or_null("Modules")
	if old != null:
		old.free()
	var old_trailer := get_node_or_null("Trailer")
	if old_trailer != null:
		for w in old_trailer.find_children("Wheel*", "Node3D", true, false):
			_wheels.erase(w)
		old_trailer.free()
	var mods := Node3D.new()
	mods.name = "Modules"
	_body.add_child(mods)
	var frame := Palette.mat(Palette.BUGGY_FRAME, 0.5, 0.6)
	var accent := Palette.mat(Palette.BUGGY_ACCENT, 0.55, 0.2)
	var steel := Palette.mat(Palette.METAL, 0.45, 0.7)
	var rust := Palette.mat(Palette.RUST_LIGHT, 0.8, 0.3)

	var gen := loadout.level(UpgradeCatalog.GENERATOR)
	for i in gen:
		# Dodatkowe cewki i żebra chłodzące generatora.
		var side := -1.0 if i % 2 == 0 else 1.0
		mods.add_child(LowPoly.cylinder(0.14, 0.4, _coil_mat, Vector3(side * 0.42, 1.0, -0.55 + 0.05 * i), Vector3(0, 0, PI * 0.5), 10))
		for f in 3:
			mods.add_child(LowPoly.box(Vector3(0.04, 0.32, 0.32), steel, Vector3(side * (0.3 + f * 0.09), 1.0, -0.55)))

	var armor := loadout.level(UpgradeCatalog.ARMOR)
	if armor >= 1:
		for side in [-1.0, 1.0]:
			mods.add_child(LowPoly.box(Vector3(0.1, 0.75, 2.1), rust, Vector3(side * 0.74, 1.0, -0.1), Vector3(0, 0, side * 0.08)))
			for k in 3:
				mods.add_child(LowPoly.box(Vector3(0.12, 0.08, 0.08), steel, Vector3(side * 0.8, 1.25, -0.8 + k * 0.7)))
	if armor >= 2:
		mods.add_child(LowPoly.box(Vector3(1.5, 0.55, 0.12), rust, Vector3(0, 0.55, -1.95), Vector3(-0.5, 0, 0)))
		for k in 4:
			mods.add_child(LowPoly.cylinder(0.05, 0.4, steel, Vector3(-0.6 + k * 0.4, 0.5, -2.1), Vector3(PI * 0.5, 0, 0), 5))

	var cap := loadout.level(UpgradeCatalog.CAPACITOR)
	for i in cap:
		var x := -0.3 + i * 0.6 if cap > 1 else 0.0
		mods.add_child(LowPoly.cylinder(0.16, 0.7, frame, Vector3(x, 1.25, 0.95), Vector3.ZERO, 10))
		mods.add_child(LowPoly.cylinder(0.12, 0.72, Palette.glow(Palette.SCRAP_GLOW, 1.6), Vector3(x, 1.25, 0.95), Vector3.ZERO, 10))

	var old_turret_mods := _turret.get_node_or_null("TurretMods")
	if old_turret_mods != null:
		old_turret_mods.free()
	var turret_mods := Node3D.new()
	turret_mods.name = "TurretMods"
	_turret.add_child(turret_mods)
	var turret := loadout.level(UpgradeCatalog.TURRET)
	if turret >= 1:
		turret_mods.add_child(LowPoly.box(Vector3(0.6, 0.35, 0.06), accent, Vector3(0, 0.25, -0.25)))
	if turret >= 2:
		turret_mods.add_child(LowPoly.cylinder(0.06, 0.9, steel, Vector3(0.16, 0.2, -0.55), Vector3(PI * 0.5, 0, 0), 8))
		turret_mods.add_child(LowPoly.cylinder(0.06, 0.9, steel, Vector3(-0.16, 0.2, -0.55), Vector3(PI * 0.5, 0, 0), 8))

	var trailer_level := loadout.level(UpgradeCatalog.TRAILER)
	if trailer_level >= 1:
		var trailer := Node3D.new()
		trailer.name = "Trailer"
		add_child(trailer)
		trailer.add_child(LowPoly.tube(Vector3(0, 0.55, 1.1), Vector3(0, 0.55, 1.9), 0.05, frame))
		var bed_len := 1.6 if trailer_level == 1 else 2.6
		var bed_z := 1.9 + bed_len * 0.5
		trailer.add_child(LowPoly.box(Vector3(1.4, 0.12, bed_len), frame, Vector3(0, 0.62, bed_z)))
		for side in [-1.0, 1.0]:
			trailer.add_child(LowPoly.box(Vector3(0.06, 0.4, bed_len), rust, Vector3(side * 0.7, 0.85, bed_z)))
		trailer.add_child(LowPoly.box(Vector3(1.4, 0.4, 0.06), rust, Vector3(0, 0.85, bed_z + bed_len * 0.5)))
		# Kupka złomu na pace.
		for k in 5 + trailer_level * 3:
			var s := 0.18 + 0.05 * (k % 3)
			trailer.add_child(LowPoly.mesh_instance(LowPoly.rock_mesh(k + 40, 0.4), steel if k % 2 == 0 else rust,
				Vector3(-0.45 + (k % 4) * 0.3, 0.8 + 0.08 * (k % 2), bed_z - bed_len * 0.35 + (k % 5) * bed_len * 0.17), Vector3(s, s, s)))
		var axles := [bed_z] if trailer_level == 1 else [bed_z - 0.6, bed_z + 0.6]
		var tire := Palette.mat(Palette.TIRE, 0.95)
		for az in axles:
			for side in [-1.0, 1.0]:
				var w := Node3D.new()
				w.name = "Wheel%d" % trailer.get_child_count()
				w.position = Vector3(side * 0.82, 0.4, az)
				w.add_child(LowPoly.cylinder(0.4, 0.24, tire, Vector3.ZERO, Vector3(0, 0, PI * 0.5), 10))
				trailer.add_child(w)
				_wheels.append(w)


func shield_block() -> void:
	_shield_flash = 1.0


func _build() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var frame := Palette.mat(Palette.BUGGY_FRAME, 0.5, 0.6)
	var accent := Palette.mat(Palette.BUGGY_ACCENT, 0.55, 0.2)
	var tire := Palette.mat(Palette.TIRE, 0.95)
	var rim := Palette.mat(Palette.METAL, 0.4, 0.7)
	_coil_mat = Palette.glow(Palette.GENERATOR_GLOW, 1.0).duplicate()

	# Oś z dwoma dużymi kołami (z tyłu).
	var axle_z := 0.55
	_body.add_child(LowPoly.cylinder(0.07, 1.9, frame, Vector3(0, WHEEL_RADIUS, axle_z), Vector3(0, 0, PI * 0.5), 8))
	for side in [-1.0, 1.0]:
		var wheel := Node3D.new()
		wheel.position = Vector3(side * 0.98, WHEEL_RADIUS, axle_z)
		var t := LowPoly.cylinder(WHEEL_RADIUS, 0.34, tire, Vector3.ZERO, Vector3(0, 0, PI * 0.5), 14)
		wheel.add_child(t)
		wheel.add_child(LowPoly.cylinder(0.34, 0.36, rim, Vector3.ZERO, Vector3(0, 0, PI * 0.5), 8))
		for k in 3:
			var a := TAU * k / 3.0
			wheel.add_child(LowPoly.box(Vector3(0.38, 0.09, 0.09), accent, Vector3(side * 0.02, sin(a) * 0.2, cos(a) * 0.2), Vector3(a, 0, 0)))
		_wheels.append(wheel)
		_body.add_child(wheel)

	# Płoza z przodu (druga „oś” to tylko ślizg – miejsce na przyszłe moduły).
	_body.add_child(LowPoly.box(Vector3(0.9, 0.08, 1.2), frame, Vector3(0, 0.12, -1.55), Vector3(-0.15, 0, 0)))
	_body.add_child(LowPoly.tube(Vector3(-0.35, 0.16, -1.2), Vector3(-0.3, 0.75, -0.2), 0.04, frame))
	_body.add_child(LowPoly.tube(Vector3(0.35, 0.16, -1.2), Vector3(0.3, 0.75, -0.2), 0.04, frame))

	# Podłoga, siedzisko i klatka.
	_body.add_child(LowPoly.box(Vector3(1.3, 0.1, 1.8), frame, Vector3(0, 0.72, -0.15)))
	_body.add_child(LowPoly.box(Vector3(1.1, 0.18, 0.1), accent, Vector3(0, 0.82, -1.05)))
	_body.add_child(LowPoly.box(Vector3(0.55, 0.12, 0.55), Palette.mat(Color("3b2f27")), Vector3(0, 1.05, 0.35)))
	_body.add_child(LowPoly.box(Vector3(0.55, 0.6, 0.1), Palette.mat(Color("3b2f27")), Vector3(0, 1.35, 0.62), Vector3(-0.2, 0, 0)))
	var cage := [
		[Vector3(-0.62, 0.75, 0.75), Vector3(-0.5, 2.05, 0.55)],
		[Vector3(0.62, 0.75, 0.75), Vector3(0.5, 2.05, 0.55)],
		[Vector3(-0.5, 2.05, 0.55), Vector3(0.5, 2.05, 0.55)],
		[Vector3(-0.62, 0.75, -0.95), Vector3(-0.5, 1.75, -0.35)],
		[Vector3(0.62, 0.75, -0.95), Vector3(0.5, 1.75, -0.35)],
		[Vector3(-0.5, 1.75, -0.35), Vector3(-0.5, 2.05, 0.55)],
		[Vector3(0.5, 1.75, -0.35), Vector3(0.5, 2.05, 0.55)],
		[Vector3(-0.5, 1.75, -0.35), Vector3(0.5, 1.75, -0.35)],
	]
	for c in cage:
		_body.add_child(LowPoly.tube(c[0], c[1], 0.045, frame))
	# Płyty pancerza po bokach (akcent – gracz widoczny z daleka).
	for side in [-1.0, 1.0]:
		_body.add_child(LowPoly.box(Vector3(0.06, 0.5, 1.5), accent, Vector3(side * 0.66, 1.0, -0.15)))

	# Generator z korbą przed kierowcą.
	var gen := Node3D.new()
	gen.position = Vector3(0, 1.0, -0.55)
	_body.add_child(gen)
	gen.add_child(LowPoly.cylinder(0.2, 0.5, frame, Vector3.ZERO, Vector3(0, 0, PI * 0.5), 10))
	gen.add_child(LowPoly.cylinder(0.16, 0.52, _coil_mat, Vector3.ZERO, Vector3(0, 0, PI * 0.5), 10))
	_crank = Node3D.new()
	gen.add_child(_crank)
	for side in [-1.0, 1.0]:
		_crank.add_child(LowPoly.box(Vector3(0.05, 0.32, 0.06), rim, Vector3(side * 0.3, 0.0, 0.0)))
		_crank.add_child(LowPoly.box(Vector3(0.14, 0.04, 0.08), accent, Vector3(side * 0.36, 0.16 * side, 0.0)))
	# Kable do piast kół.
	_body.add_child(LowPoly.tube(Vector3(-0.25, 1.0, -0.5), Vector3(-0.9, WHEEL_RADIUS, axle_z), 0.03, _coil_mat))
	_body.add_child(LowPoly.tube(Vector3(0.25, 1.0, -0.5), Vector3(0.9, WHEEL_RADIUS, axle_z), 0.03, _coil_mat))

	# Kierowca: tułów, głowa w kasku z goglami, ręce na kierownicy, nogi kręcą korbą.
	var cloth := Palette.mat(Color("7a5b3f"))
	var skin := Palette.mat(Color("c48a64"))
	var rider := Node3D.new()
	rider.position = Vector3(0, 1.1, 0.3)
	_body.add_child(rider)
	rider.add_child(LowPoly.box(Vector3(0.42, 0.62, 0.3), cloth, Vector3(0, 0.38, -0.05), Vector3(-0.35, 0, 0)))
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.17
	sphere.height = 0.34
	sphere.radial_segments = 8
	sphere.rings = 4
	head.mesh = sphere
	head.material_override = skin
	head.position = Vector3(0, 0.82, -0.22)
	rider.add_child(head)
	var helmet := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.19
	hs.height = 0.24
	hs.radial_segments = 8
	hs.rings = 3
	hs.is_hemisphere = true
	helmet.mesh = hs
	helmet.material_override = accent
	helmet.position = Vector3(0, 0.86, -0.22)
	rider.add_child(helmet)
	rider.add_child(LowPoly.box(Vector3(0.3, 0.07, 0.06), Palette.glow(Color("9fe8ff"), 0.8), Vector3(0, 0.84, -0.38)))
	for side in [-1.0, 1.0]:
		rider.add_child(LowPoly.tube(Vector3(side * 0.22, 0.55, -0.15), Vector3(side * 0.28, 0.2, -0.75), 0.05, cloth))
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.14, 0.05, 0.0)
		leg.add_child(LowPoly.tube(Vector3.ZERO, Vector3(0, -0.15, -0.6), 0.07, cloth))
		rider.add_child(leg)
		_legs.append(leg)
	rider.add_child(LowPoly.box(Vector3(0.7, 0.05, 0.05), frame, Vector3(0, 0.2, -0.78)))

	# Wieżyczka na dachu klatki (etap 2): podstawa + lufa, obraca się do celu.
	_turret = Node3D.new()
	_turret.position = Vector3(0, 2.12, 0.1)
	_body.add_child(_turret)
	_turret.add_child(LowPoly.cylinder(0.28, 0.16, frame, Vector3.ZERO, Vector3.ZERO, 10))
	_turret.add_child(LowPoly.box(Vector3(0.36, 0.22, 0.42), accent, Vector3(0, 0.17, 0.0)))
	_turret.add_child(LowPoly.cylinder(0.06, 0.9, rim, Vector3(0, 0.2, -0.55), Vector3(PI * 0.5, 0, 0), 8))
	_muzzle = MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.18
	flash_mesh.height = 0.36
	flash_mesh.radial_segments = 6
	flash_mesh.rings = 3
	_muzzle.mesh = flash_mesh
	_muzzle.material_override = Palette.glow(Color("ffe08a"), 8.0)
	_muzzle.position = Vector3(0, 0.2, -1.05)
	_muzzle.visible = false
	_turret.add_child(_muzzle)

	# Tarcza (bańka z poświatą na krawędziach).
	_shield = MeshInstance3D.new()
	var bubble := SphereMesh.new()
	bubble.radius = 1.0
	bubble.height = 2.0
	bubble.radial_segments = 24
	bubble.rings = 12
	_shield.mesh = bubble
	_shield.scale = Vector3(1.7, 1.45, 2.2)
	_shield.position = Vector3(0, 1.2, -0.2)
	_shield_mat = ShaderMaterial.new()
	_shield_mat.shader = load("res://shaders/shield.gdshader")
	_shield.material_override = _shield_mat
	add_child(_shield)

	# Maszt z flagą.
	_body.add_child(LowPoly.tube(Vector3(0.45, 2.0, 0.6), Vector3(0.45, 3.1, 0.75), 0.025, frame))
	_flag = Node3D.new()
	_flag.position = Vector3(0.45, 3.05, 0.75)
	_body.add_child(_flag)
	_flag.add_child(LowPoly.box(Vector3(0.03, 0.34, 0.55), Palette.mat(Palette.PAINT_RED), Vector3(0, -0.17, 0.27)))

	# Kurz spod kół (cząsteczki lecą do tyłu względem pojazdu).
	_dust = CPUParticles3D.new()
	_dust.emitting = false
	_dust.position = Vector3(0, 0.15, axle_z + 0.5)
	_dust.amount = 36
	_dust.lifetime = 0.9
	_dust.direction = Vector3(0, 0.25, 1)
	_dust.spread = 18.0
	_dust.initial_velocity_min = 3.0
	_dust.initial_velocity_max = 5.5
	_dust.gravity = Vector3(0, -1.0, 0)
	_dust.scale_amount_min = 0.25
	_dust.scale_amount_max = 0.6
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(1.0, 0.05, 0.1)
	var puff := SphereMesh.new()
	puff.radius = 0.22
	puff.height = 0.44
	puff.radial_segments = 6
	puff.rings = 3
	var puff_mat := StandardMaterial3D.new()
	puff_mat.albedo_color = Color(Color("e2c39a"), 0.32)
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = puff_mat
	_dust.mesh = puff
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.6))
	fade.add_point(Vector2(1.0, 1.6))
	_dust.scale_amount_curve = fade
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.7))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	_dust.color_ramp = ramp
	add_child(_dust)
