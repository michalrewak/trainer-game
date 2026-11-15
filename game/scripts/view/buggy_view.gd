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
		_body.visible = fmod(_flash, 0.14) > 0.05


func on_hit() -> void:
	_flash = 1.2


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

	# Maszt z flagą.
	_body.add_child(LowPoly.tube(Vector3(0.45, 2.0, 0.6), Vector3(0.45, 3.1, 0.75), 0.025, frame))
	_flag = Node3D.new()
	_flag.position = Vector3(0.45, 3.05, 0.75)
	_body.add_child(_flag)
	_flag.add_child(LowPoly.box(Vector3(0.03, 0.34, 0.55), Palette.mat(Palette.PAINT_RED), Vector3(0, -0.17, 0.27)))

	# Kurz spod kół (cząsteczki lecą do tyłu względem pojazdu).
	_dust = CPUParticles3D.new()
	_dust.position = Vector3(0, 0.15, axle_z + 0.5)
	_dust.amount = 48
	_dust.lifetime = 1.1
	_dust.direction = Vector3(0, 0.35, 1)
	_dust.spread = 22.0
	_dust.initial_velocity_min = 3.0
	_dust.initial_velocity_max = 6.0
	_dust.gravity = Vector3(0, -1.0, 0)
	_dust.scale_amount_min = 0.5
	_dust.scale_amount_max = 1.3
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(1.0, 0.05, 0.1)
	var puff := SphereMesh.new()
	puff.radius = 0.22
	puff.height = 0.44
	puff.radial_segments = 6
	puff.rings = 3
	var puff_mat := StandardMaterial3D.new()
	puff_mat.albedo_color = Color(Palette.SAND, 0.5)
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
