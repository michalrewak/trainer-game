class_name BuggyView
extends Node3D
## Jednoosiowy buggy z pedałowym generatorem (z prymitywów): dwa duże koła na jednej osi,
## płoza z przodu, klatka z rur, kierowca kręcący korbą generatora (tempo = kadencja).
## Widok tylko odwzorowuje stan symulacji: pozycję w pasie, prędkość, przechył, uderzenia.

const WHEEL_RADIUS := 0.66
## Oś korby generatora w układzie nadwozia i promień pedałów.
const CRANK_CENTER := Vector3(0, 1.0, -0.55)
const CRANK_RADIUS := 0.16

var _body: Node3D
var _wheels: Array[Node3D] = []
var _crank: Node3D
var _thighs: Array[MeshInstance3D] = []
var _shins: Array[MeshInstance3D] = []
var _flag: Node3D
var _dust: CPUParticles3D
var _coil_mat: ShaderMaterial
var _turret: Node3D
var _muzzle: MeshInstance3D
var _muzzle_t := 0.0
var _aim_line: MeshInstance3D
var _towing := false
var _boost_flame: Node3D
var _boosting := false
var _rear_m := 0.0
var _sparks: CPUParticles3D
var _spark_light: OmniLight3D
var _charge_level := 0.0
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
	_pose_legs()
	# Przechył przy zmianie pasa, „nurkowanie” przy hamowaniu/przyspieszaniu.
	var roll := clampf(-sim.lanes.lateral_velocity_mps * 0.03, -0.22, 0.22)
	var accel := (v - _prev_speed) / maxf(delta, 1e-4)
	_prev_speed = v
	_pitch = lerpf(_pitch, clampf(accel * 0.03, -0.12, 0.08), 1.0 - exp(-delta * 6.0))
	_body.rotation = Vector3(_pitch, -sim.lanes.lateral_velocity_mps * 0.02, roll)
	_body.position.y = 0.02 * sin(_time * 18.0) * clampf(v / 10.0, 0.0, 1.0)
	_flag.rotation.x = -clampf(v / 12.0, 0.0, 1.0) * 1.1 + 0.06 * sin(_time * 9.0)
	# Generator świeci mocniej przy większej mocy.
	Palette.set_glow_energy(_coil_mat, 0.4 + clampf(power_w / 300.0, 0.0, 1.6) * 2.0)
	# Kurz spod kół.
	_dust.emitting = v > 1.0
	_dust.speed_scale = clampf(v / 9.0, 0.3, 1.5)
	if _boost_flame != null:
		_boost_flame.visible = _boosting
		_boost_flame.scale = Vector3(1.0 + 0.15 * sin(_time * 53.0), 1.0 + 0.15 * sin(_time * 47.0), 1.0 + 0.3 * sin(_time * 41.0))
	# Błysk po uderzeniu.
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		# Po końcu migania pojazd MUSI być widoczny (wcześniej znikał na resztę wyprawy).
		_body.visible = _flash <= 0.0 or fmod(_flash, 0.14) > 0.05


## Dopalacz: płomień z dyszy podczas wtrysku czystego paliwa.
func set_boost(on: bool) -> void:
	_boosting = on


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
	# Tarcza to ładunek kondensatorów, nie bańka: poziom pokazuje HUD, a zablokowany atak
	# widać jako wyładowanie – snop iskier i błysk na pancerzu.
	_shield_flash = maxf(0.0, _shield_flash - delta * 2.5)
	_spark_light.light_energy = _shield_flash * 9.0
	_spark_light.visible = _shield_flash > 0.0
	_charge_level = shield_level


## Linia celownika z lufy – widoczna, gdy gracz celuje albo strzela.
func set_aim_line(on: bool) -> void:
	_aim_line.visible = on


func muzzle_flash() -> void:
	_muzzle_t = 0.07


## Moduły z garażu (etap 3) – każdy widocznie zmienia sylwetkę pojazdu.
func apply_loadout(loadout: Loadout) -> void:
	var old_mods := _body.get_node_or_null("Modules")
	if old_mods != null:
		_forget_wheels_under(old_mods)
		old_mods.free()
	var mods := Node3D.new()
	mods.name = "Modules"
	_body.add_child(mods)
	var frame := Palette.mat(Color("2a2826"), 0.6, 0.6)
	var accent := Palette.mat(Palette.BUGGY_ACCENT, 0.7, 0.2)
	var steel := Palette.mat(Palette.METAL, 0.45, 0.7)
	var rust := Palette.mat(Palette.RUST_LIGHT, 0.85, 0.3)
	var tire := Palette.mat(Palette.TIRE, 0.95)

	# Podwozie: druga oś z przodu zamiast płozy, potem trzecia z tyłu i platforma.
	var chassis := loadout.level(UpgradeCatalog.CHASSIS)
	var ski := _body.get_node_or_null("Ski") as Node3D
	if ski != null:
		ski.visible = chassis == 0
	if chassis >= 1:
		mods.add_child(LowPoly.cylinder(0.07, 1.9, frame, Vector3(0, 0.5, -1.6), Vector3(0, 0, PI * 0.5), 8))
		for side: float in [-1.0, 1.0]:
			mods.add_child(_module_wheel("WheelFront", Vector3(side * 1.0, 0.5, -1.6), 1.0, side, tire, steel))
			mods.add_child(LowPoly.box(Vector3(0.42, 0.05, 0.8), rust, Vector3(side * 1.0, 1.08, -1.6)))
		mods.add_child(LowPoly.box(Vector3(1.3, 0.3, 0.5), frame, Vector3(0, 0.75, -1.75)))
	var rear := 0.0
	if chassis >= 2:
		rear = 1.35
		mods.add_child(LowPoly.box(Vector3(1.5, 0.1, 1.5), frame, Vector3(0, 0.72, 1.75)))
		mods.add_child(LowPoly.cylinder(0.08, 2.0, frame, Vector3(0, 0.6, 1.95), Vector3(0, 0, PI * 0.5), 8))
		for side: float in [-1.0, 1.0]:
			mods.add_child(_module_wheel("WheelRear", Vector3(side * 1.05, 0.6, 1.95), 1.2, side, tire, steel))
			mods.add_child(LowPoly.box(Vector3(0.07, 0.5, 1.5), rust, Vector3(side * 0.72, 1.0, 1.75)))
			# Kominy – znak rozpoznawczy krążownika.
			mods.add_child(LowPoly.tube(Vector3(side * 0.6, 0.8, 2.35), Vector3(side * 0.62, 2.7, 2.45), 0.08, frame))
		mods.add_child(LowPoly.box(Vector3(1.3, 0.55, 0.9), rust, Vector3(0, 1.05, 1.9)))
		mods.add_child(LowPoly.cylinder(0.3, 1.0, Palette.mat(Palette.PAINT_RED, 0.7, 0.3), Vector3(0, 1.62, 1.9), Vector3(0, 0, PI * 0.5), 10))

	# Generator: kolejne cewki i żebra chłodzące.
	var gen := loadout.level(UpgradeCatalog.GENERATOR)
	for i in gen:
		var side := -1.0 if i % 2 == 0 else 1.0
		var row := floori(i / 2.0)
		mods.add_child(LowPoly.cylinder(0.14, 0.4, _coil_mat, Vector3(side * 0.42, 1.0 + row * 0.3, -0.55), Vector3(0, 0, PI * 0.5), 10))
		for f in 3:
			mods.add_child(LowPoly.box(Vector3(0.04, 0.3, 0.3), steel, Vector3(side * (0.3 + f * 0.09), 1.0 + row * 0.3, -0.55)))

	# Pancerz: burty, osłona przodu, na końcu pancerna szyba.
	var armor := loadout.level(UpgradeCatalog.ARMOR)
	if armor >= 1:
		for side: float in [-1.0, 1.0]:
			mods.add_child(LowPoly.box(Vector3(0.1, 0.75, 2.1), rust, Vector3(side * 0.74, 1.0, -0.1), Vector3(0, 0, side * 0.08)))
			for k in 3:
				mods.add_child(LowPoly.box(Vector3(0.12, 0.08, 0.08), steel, Vector3(side * 0.8, 1.25, -0.8 + k * 0.7)))
	if armor >= 2:
		mods.add_child(LowPoly.box(Vector3(1.5, 0.55, 0.12), rust, Vector3(0, 0.62, -1.98), Vector3(-0.5, 0, 0)))
		for side: float in [-1.0, 1.0]:
			mods.add_child(LowPoly.box(Vector3(0.08, 0.5, 0.9), rust, Vector3(side * 0.74, 1.6, 0.3), Vector3(0, 0, side * 0.12)))
	if armor >= 3:
		mods.add_child(LowPoly.box(Vector3(1.0, 0.6, 0.07), frame, Vector3(0, 1.5, -0.7), Vector3(-0.45, 0, 0)))
		mods.add_child(LowPoly.box(Vector3(0.6, 0.1, 0.08), Palette.glow(Color("9fe8ff"), 0.5), Vector3(0, 1.55, -0.74), Vector3(-0.45, 0, 0)))
		mods.add_child(LowPoly.box(Vector3(1.1, 0.06, 0.9), rust, Vector3(0, 2.12, 0.5)))

	# Kondensatory tarczy za fotelem.
	var cap := loadout.level(UpgradeCatalog.CAPACITOR)
	for i in cap:
		var x := (i - (cap - 1) * 0.5) * 0.42
		mods.add_child(LowPoly.cylinder(0.16, 0.7, frame, Vector3(x, 1.25, 0.95), Vector3.ZERO, 10))
		mods.add_child(LowPoly.cylinder(0.12, 0.72, Palette.glow(Palette.SCRAP_GLOW, 1.6), Vector3(x, 1.25, 0.95), Vector3.ZERO, 10))

	# Taran: stalowy lemiesz przed zderzakiem.
	var ram := loadout.level(UpgradeCatalog.RAM)
	if ram >= 1:
		var nose := -2.15 if chassis == 0 else -2.45
		for side: float in [-1.0, 1.0]:
			mods.add_child(LowPoly.box(Vector3(1.0, 0.6 if ram == 1 else 0.85, 0.1), steel, Vector3(side * 0.45, 0.5, nose), Vector3(0, side * 0.55, 0)))
		if ram >= 2:
			for k in 5:
				mods.add_child(LowPoly.cylinder(0.05, 0.45, steel, Vector3(-0.8 + k * 0.4, 0.75, nose - 0.2 + absf(k - 2.0) * 0.22), Vector3(PI * 0.5, 0, 0), 5))

	# Zawieszenie: widoczne sprężyny przy głównej osi.
	var susp := loadout.level(UpgradeCatalog.SUSPENSION)
	for side: float in [-1.0, 1.0]:
		for k in susp:
			mods.add_child(LowPoly.cylinder(0.09, 0.55, accent, Vector3(side * 0.82, 0.95, 0.4 + k * 0.3), Vector3(0, 0, side * 0.4), 8))
			mods.add_child(LowPoly.cylinder(0.04, 0.7, steel, Vector3(side * 0.82, 0.95, 0.4 + k * 0.3), Vector3(0, 0, side * 0.4), 6))

	# Chwytak: wysięgnik z hakiem (na 2. poziomie po obu stronach).
	var grab := loadout.level(UpgradeCatalog.GRABBER)
	for g in grab:
		var side := 1.0 if g == 0 else -1.0
		mods.add_child(LowPoly.tube(Vector3(side * 0.6, 1.7, 0.3), Vector3(side * 1.7, 1.5, -0.3), 0.05, frame))
		mods.add_child(LowPoly.tube(Vector3(side * 1.7, 1.5, -0.3), Vector3(side * 1.95, 0.45, -0.5), 0.035, steel))
		mods.add_child(LowPoly.box(Vector3(0.3, 0.08, 0.3), Palette.glow(Palette.SCRAP_GLOW, 0.8), Vector3(side * 1.95, 0.4, -0.5)))

	# Dopalacz: zaplombowane kanistry czystego paliwa i dysza z tyłu (jeden jest zawsze).
	var boost := loadout.level(UpgradeCatalog.BOOSTER)
	var bz := 1.3 if chassis < 2 else 2.7
	var seal := Palette.glow(Color("ff8a3a"), 1.4)
	for i in boost + 1:
		var bx := (i - boost * 0.5) * 0.34
		mods.add_child(LowPoly.box(Vector3(0.28, 0.5, 0.2), Palette.mat(Palette.PAINT_RED, 0.7, 0.3), Vector3(bx, 0.95, bz)))
		mods.add_child(LowPoly.box(Vector3(0.3, 0.07, 0.22), seal, Vector3(bx, 1.05, bz)))
	mods.add_child(LowPoly.cylinder(0.11 + 0.02 * boost, 0.45, frame, Vector3(0, 0.62, bz + 0.2), Vector3(PI * 0.5, 0, 0), 8))
	_boost_flame = Node3D.new()
	_boost_flame.position = Vector3(0, 0.62, bz + 0.45)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.2 + 0.04 * boost
	cone.height = 1.6 + 0.3 * boost
	cone.radial_segments = 8
	_boost_flame.add_child(LowPoly.mesh_instance(cone, Palette.glow(Color("ff7a1a"), 6.0), Vector3(0, 0, cone.height * 0.5), Vector3.ONE, Vector3(PI * 0.5, 0, 0)))
	var core := CylinderMesh.new()
	core.top_radius = 0.0
	core.bottom_radius = 0.1
	core.height = 0.9
	core.radial_segments = 6
	_boost_flame.add_child(LowPoly.mesh_instance(core, Palette.glow(Color("9fe8ff"), 8.0), Vector3(0, 0, 0.45), Vector3.ONE, Vector3(PI * 0.5, 0, 0)))
	var flame_light := OmniLight3D.new()
	flame_light.light_color = Color(1.0, 0.55, 0.2)
	flame_light.light_energy = 6.0
	flame_light.omni_range = 9.0
	flame_light.position = Vector3(0, 0.3, 0.8)
	_boost_flame.add_child(flame_light)
	_boost_flame.visible = false
	mods.add_child(_boost_flame)

	# Wieżyczka: osłona, podwójna lufa, ciężka lufa.
	var old_turret_mods := _turret.get_node_or_null("TurretMods")
	if old_turret_mods != null:
		old_turret_mods.free()
	var turret_mods := Node3D.new()
	turret_mods.name = "TurretMods"
	_turret.add_child(turret_mods)
	var turret := loadout.level(UpgradeCatalog.TURRET)
	if turret >= 1:
		turret_mods.add_child(LowPoly.box(Vector3(0.7, 0.4, 0.06), accent, Vector3(0, 0.26, -0.27)))
	if turret >= 2:
		for bx: float in [-0.16, 0.16]:
			turret_mods.add_child(LowPoly.cylinder(0.06, 0.95, steel, Vector3(bx, 0.2, -0.6), Vector3(PI * 0.5, 0, 0), 8))
	if turret >= 3:
		turret_mods.add_child(LowPoly.cylinder(0.1, 1.25, frame, Vector3(0, 0.34, -0.7), Vector3(PI * 0.5, 0, 0), 8))
		turret_mods.add_child(LowPoly.box(Vector3(0.3, 0.3, 0.5), frame, Vector3(0, 0.34, 0.25)))

	_rear_m = rear
	set_loot_wagon(_towing)


## Przyczepa z łupem – doczepiana tylko na czas zadania „dowieź łup” po napadzie.
func set_loot_wagon(on: bool) -> void:
	_towing = on
	var old := get_node_or_null("Trailer")
	if old != null:
		_forget_wheels_under(old)
		old.free()
	if not on:
		return
	var frame := Palette.mat(Color("2a2826"), 0.6, 0.6)
	var steel := Palette.mat(Palette.METAL, 0.45, 0.7)
	var rust := Palette.mat(Palette.RUST_LIGHT, 0.85, 0.3)
	var tire := Palette.mat(Palette.TIRE, 0.95)
	var trailer := Node3D.new()
	trailer.name = "Trailer"
	add_child(trailer)
	var z := 1.15 + _rear_m
	var bed_len := 1.9
	trailer.add_child(LowPoly.tube(Vector3(0, 0.55, z), Vector3(0, 0.55, z + 0.7), 0.05, frame))
	var bed_z := z + 0.7 + bed_len * 0.5
	trailer.add_child(LowPoly.box(Vector3(1.5, 0.12, bed_len), frame, Vector3(0, 0.62, bed_z)))
	for side: float in [-1.0, 1.0]:
		trailer.add_child(LowPoly.box(Vector3(0.06, 0.5, bed_len), rust, Vector3(side * 0.75, 0.9, bed_z)))
		trailer.add_child(_module_wheel("WheelWagon", Vector3(side * 0.9, 0.42, bed_z), 0.84, side, tire, steel))
	trailer.add_child(LowPoly.box(Vector3(1.5, 0.5, 0.06), rust, Vector3(0, 0.9, bed_z + bed_len * 0.5)))
	# Łup: skrzynie, beczka i świecący złom.
	trailer.add_child(LowPoly.box(Vector3(0.6, 0.5, 0.6), Palette.mat(Color("6b5640")), Vector3(-0.35, 1.0, bed_z - 0.45)))
	trailer.add_child(LowPoly.box(Vector3(0.5, 0.4, 0.5), Palette.mat(Color("5a4636")), Vector3(0.35, 0.95, bed_z + 0.5), Vector3(0, 0.4, 0)))
	trailer.add_child(LowPoly.cylinder(0.26, 0.7, Palette.mat(Palette.PAINT_RED, 0.7, 0.3), Vector3(0.38, 1.05, bed_z - 0.4), Vector3.ZERO, 10))
	for k in 5:
		var s := 0.2 + 0.05 * (k % 3)
		trailer.add_child(LowPoly.mesh_instance(LowPoly.rock_mesh(k + 40, 0.4), Palette.glow(Palette.SCRAP_GLOW, 0.9) if k % 2 == 0 else steel,
			Vector3(-0.4 + (k % 3) * 0.4, 0.85 + 0.12 * (k % 2), bed_z - 0.1 + (k % 4) * 0.22), Vector3(s, s, s)))

## Długość „ogona” pojazdu za główną osią [m]: trzecia oś i przyczepy. Dla kamer.
static func tail_length(loadout: Loadout, towing: bool = false) -> float:
	var rear := 1.35 if loadout.level(UpgradeCatalog.CHASSIS) >= 2 else 0.0
	return rear + (2.8 if towing else 0.0)


## Usuwa z listy kół te, które należą do zwalnianego węzła (nazwy bywają nadawane automatycznie).
func _forget_wheels_under(holder: Node) -> void:
	for w: Node3D in _wheels.duplicate():
		if holder.is_ancestor_of(w):
			_wheels.erase(w)


## Koło modułu (podwozie, wagony) – obraca się razem z kołami głównymi.
func _module_wheel(wheel_name: String, pos: Vector3, diameter: float, side: float, tire: Material, hub: Material) -> Node3D:
	var w := Node3D.new()
	w.name = wheel_name
	w.position = pos
	var model := KenneyModels.buggy_wheel(side, diameter)
	if model != null:
		w.add_child(model)
	else:
		w.add_child(LowPoly.cylinder(diameter * 0.5, diameter * 0.32, tire, Vector3.ZERO, Vector3(0, 0, PI * 0.5), 10))
		w.add_child(LowPoly.cylinder(diameter * 0.26, diameter * 0.34, hub, Vector3.ZERO, Vector3(0, 0, PI * 0.5), 8))
	_wheels.append(w)
	return w


func shield_block() -> void:
	_shield_flash = 1.0
	_sparks.restart()
	_sparks.emitting = true


func _build() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var frame := Palette.mat(Color("2a2826"), 0.6, 0.6)
	var accent := Palette.mat(Palette.BUGGY_ACCENT, 0.7, 0.2)
	var rust := Palette.mat(Palette.RUST_LIGHT, 0.85, 0.3)
	var tire := Palette.mat(Palette.TIRE, 0.95)
	var rim := Palette.mat(Palette.METAL, 0.4, 0.7)
	var leather := Palette.mat(Color("3b2f27"))
	var cloth := Palette.mat(Color("6a5038"))
	var skin := Palette.mat(Color("b98562"))
	_coil_mat = Palette.glow(Palette.GENERATOR_GLOW, 1.0).duplicate() as ShaderMaterial

	# Jedna oś z dwoma wielkimi kołami terenowymi.
	var axle_z := 0.55
	_body.add_child(LowPoly.cylinder(0.08, 2.0, frame, Vector3(0, WHEEL_RADIUS, axle_z), Vector3(0, 0, PI * 0.5), 8))
	for side: float in [-1.0, 1.0]:
		var wheel := Node3D.new()
		wheel.position = Vector3(side * 1.08, WHEEL_RADIUS, axle_z)
		var model := KenneyModels.buggy_wheel(side, WHEEL_RADIUS * 2.0)
		if model != null:
			wheel.add_child(model)
		else:
			wheel.add_child(LowPoly.cylinder(WHEEL_RADIUS, 0.42, tire, Vector3.ZERO, Vector3(0, 0, PI * 0.5), 14))
			wheel.add_child(LowPoly.cylinder(0.34, 0.44, rim, Vector3.ZERO, Vector3(0, 0, PI * 0.5), 8))
		# Kolce na piaście.
		wheel.add_child(LowPoly.cylinder(0.05, 0.3, rim, Vector3(side * 0.3, 0, 0), Vector3(0, 0, PI * 0.5), 5))
		_wheels.append(wheel)
		_body.add_child(wheel)
		# Błotnik z blachy nad kołem.
		_body.add_child(LowPoly.box(Vector3(0.5, 0.05, 1.0), rust, Vector3(side * 1.08, WHEEL_RADIUS * 2.0 + 0.1, axle_z), Vector3(0.0, 0, side * -0.1)))
		_body.add_child(LowPoly.tube(Vector3(side * 0.66, 1.0, axle_z), Vector3(side * 0.95, WHEEL_RADIUS * 2.0 + 0.08, axle_z), 0.035, frame))

	# Rama: podłużnice zbiegające się ku przodowi, płoza z amortyzatorem zamiast drugiej osi.
	var ski := Node3D.new()
	ski.name = "Ski"
	_body.add_child(ski)
	for side: float in [-1.0, 1.0]:
		_body.add_child(LowPoly.tube(Vector3(side * 0.5, 0.62, 1.15), Vector3(side * 0.3, 0.5, -1.75), 0.055, frame))
		ski.add_child(LowPoly.tube(Vector3(side * 0.3, 0.5, -1.75), Vector3(side * 0.2, 0.14, -1.55), 0.04, rim))
	ski.add_child(LowPoly.box(Vector3(0.55, 0.07, 1.15), frame, Vector3(0, 0.1, -1.7), Vector3(-0.12, 0, 0)))
	ski.add_child(LowPoly.box(Vector3(0.55, 0.07, 0.35), frame, Vector3(0, 0.22, -2.35), Vector3(-0.7, 0, 0)))

	# Wanna: podłoga, burty z łatanej blachy, maska i zderzak z kolcami.
	_body.add_child(LowPoly.box(Vector3(1.3, 0.08, 2.1), frame, Vector3(0, 0.68, -0.2)))
	for side: float in [-1.0, 1.0]:
		_body.add_child(LowPoly.box(Vector3(0.06, 0.55, 1.7), accent, Vector3(side * 0.67, 0.98, -0.2)))
		_body.add_child(LowPoly.box(Vector3(0.07, 0.3, 0.55), rust, Vector3(side * 0.68, 0.9, 0.35), Vector3(0.06, 0, 0)))
		_body.add_child(LowPoly.box(Vector3(0.07, 0.22, 0.4), frame, Vector3(side * 0.68, 1.1, -0.7), Vector3(-0.1, 0, 0)))
	_body.add_child(LowPoly.box(Vector3(1.2, 0.06, 0.95), accent, Vector3(0, 0.98, -1.3), Vector3(0.38, 0, 0)))
	_body.add_child(LowPoly.box(Vector3(0.3, 0.07, 0.97), frame, Vector3(0, 0.99, -1.3), Vector3(0.38, 0, 0)))
	_body.add_child(LowPoly.cylinder(0.05, 1.5, rim, Vector3(0, 0.62, -1.85), Vector3(0, 0, PI * 0.5), 6))
	for k in 4:
		_body.add_child(LowPoly.cylinder(0.045, 0.35, rim, Vector3(-0.6 + k * 0.4, 0.62, -2.02), Vector3(PI * 0.5, 0, 0), 5))
	# Reflektory.
	var lamp := Palette.glow(Color("ffe2a8"), 1.6)
	for side: float in [-1.0, 1.0]:
		_body.add_child(LowPoly.cylinder(0.12, 0.16, frame, Vector3(side * 0.42, 0.98, -1.74), Vector3(PI * 0.5, 0, 0), 8))
		_body.add_child(LowPoly.cylinder(0.09, 0.03, lamp, Vector3(side * 0.42, 0.98, -1.83), Vector3(PI * 0.5, 0, 0), 8))

	# Fotel i klatka bezpieczeństwa z dachem pod wieżyczkę.
	_body.add_child(LowPoly.box(Vector3(0.55, 0.12, 0.55), leather, Vector3(0, 1.05, 0.35)))
	_body.add_child(LowPoly.box(Vector3(0.55, 0.65, 0.1), leather, Vector3(0, 1.38, 0.63), Vector3(-0.2, 0, 0)))
	var cage := [
		[Vector3(-0.62, 0.75, 0.8), Vector3(-0.5, 2.05, 0.55)],
		[Vector3(0.62, 0.75, 0.8), Vector3(0.5, 2.05, 0.55)],
		[Vector3(-0.5, 2.05, 0.55), Vector3(0.5, 2.05, 0.55)],
		[Vector3(-0.62, 0.75, -0.95), Vector3(-0.5, 1.75, -0.35)],
		[Vector3(0.62, 0.75, -0.95), Vector3(0.5, 1.75, -0.35)],
		[Vector3(-0.5, 1.75, -0.35), Vector3(-0.5, 2.05, 0.55)],
		[Vector3(0.5, 1.75, -0.35), Vector3(0.5, 2.05, 0.55)],
		[Vector3(-0.5, 1.75, -0.35), Vector3(0.5, 1.75, -0.35)],
		[Vector3(-0.62, 0.75, 0.8), Vector3(0.5, 2.05, 0.55)],
	]
	for c in cage:
		_body.add_child(LowPoly.tube(c[0], c[1], 0.05, frame))
	_body.add_child(LowPoly.box(Vector3(1.0, 0.05, 0.85), rust, Vector3(0, 2.07, 0.12), Vector3(-0.3, 0, 0)))

	# Generator z korbą przed kierowcą: cewki świecą mocniej przy większej mocy.
	var gen := Node3D.new()
	gen.position = CRANK_CENTER
	_body.add_child(gen)
	gen.add_child(LowPoly.cylinder(0.22, 0.5, frame, Vector3.ZERO, Vector3(0, 0, PI * 0.5), 10))
	gen.add_child(LowPoly.cylinder(0.17, 0.52, _coil_mat, Vector3.ZERO, Vector3(0, 0, PI * 0.5), 10))
	for f in 4:
		gen.add_child(LowPoly.box(Vector3(0.03, 0.5, 0.5), rim, Vector3(-0.21 + f * 0.14, 0, 0)))
	_crank = Node3D.new()
	gen.add_child(_crank)
	for side: float in [-1.0, 1.0]:
		_crank.add_child(LowPoly.box(Vector3(0.05, 0.34, 0.06), rim, Vector3(side * 0.3, side * 0.08, 0.0)))
		_crank.add_child(LowPoly.box(Vector3(0.16, 0.04, 0.09), accent, Vector3(side * 0.36, CRANK_RADIUS * side, 0.0)))
	_body.add_child(LowPoly.tube(Vector3(-0.25, 1.0, -0.5), Vector3(-0.95, WHEEL_RADIUS, axle_z), 0.03, _coil_mat))
	_body.add_child(LowPoly.tube(Vector3(0.25, 1.0, -0.5), Vector3(0.95, WHEEL_RADIUS, axle_z), 0.03, _coil_mat))

	# Kierowca: pochylony tułów, naramienniki z blachy, kask z goglami, chusta.
	var rider := Node3D.new()
	rider.position = Vector3(0, 1.1, 0.3)
	_body.add_child(rider)
	rider.add_child(LowPoly.box(Vector3(0.46, 0.62, 0.3), cloth, Vector3(0, 0.4, -0.06), Vector3(-0.35, 0, 0)))
	rider.add_child(LowPoly.box(Vector3(0.5, 0.2, 0.2), leather, Vector3(0, 0.26, 0.06), Vector3(-0.35, 0, 0)))
	for side: float in [-1.0, 1.0]:
		rider.add_child(LowPoly.box(Vector3(0.2, 0.08, 0.26), rust, Vector3(side * 0.28, 0.7, -0.18), Vector3(-0.3, 0, side * -0.35)))
		rider.add_child(LowPoly.tube(Vector3(side * 0.26, 0.62, -0.18), Vector3(side * 0.34, 0.42, -0.5), 0.06, cloth))
		rider.add_child(LowPoly.tube(Vector3(side * 0.34, 0.42, -0.5), Vector3(side * 0.3, 0.22, -0.78), 0.05, skin))
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.17
	sphere.height = 0.34
	sphere.radial_segments = 8
	sphere.rings = 4
	head.mesh = sphere
	head.material_override = skin
	head.position = Vector3(0, 0.86, -0.26)
	rider.add_child(head)
	var helmet := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.2
	hs.height = 0.26
	hs.radial_segments = 8
	hs.rings = 3
	hs.is_hemisphere = true
	helmet.mesh = hs
	helmet.material_override = frame
	helmet.position = Vector3(0, 0.89, -0.26)
	rider.add_child(helmet)
	rider.add_child(LowPoly.box(Vector3(0.06, 0.1, 0.36), accent, Vector3(0, 1.01, -0.26)))
	rider.add_child(LowPoly.box(Vector3(0.3, 0.07, 0.06), Palette.glow(Color("9fe8ff"), 0.8), Vector3(0, 0.87, -0.42)))
	rider.add_child(LowPoly.box(Vector3(0.36, 0.1, 0.2), Palette.mat(Palette.PAINT_RED), Vector3(0, 0.7, -0.2)))
	rider.add_child(LowPoly.box(Vector3(0.7, 0.05, 0.05), frame, Vector3(0, 0.2, -0.78)))
	# Nogi: udo i łydka prowadzone za pedałami (ustawiane co klatkę w sync).
	for i in 2:
		var thigh := LowPoly.unit_tube(0.085, cloth)
		var shin := LowPoly.unit_tube(0.07, leather)
		_body.add_child(thigh)
		_body.add_child(shin)
		_thighs.append(thigh)
		_shins.append(shin)
	_pose_legs()

	# Tył: kanistry, zapasowa opona, zrolowany koc.
	for side: float in [-1.0, 1.0]:
		_body.add_child(LowPoly.box(Vector3(0.18, 0.42, 0.3), Palette.mat(Palette.PAINT_RED, 0.7, 0.3), Vector3(side * 0.52, 0.95, 0.98)))
		_body.add_child(LowPoly.box(Vector3(0.08, 0.08, 0.12), frame, Vector3(side * 0.52, 1.2, 0.98)))
	var spare := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.42
	torus.rings = 12
	torus.ring_segments = 6
	spare.mesh = torus
	spare.material_override = tire
	spare.position = Vector3(0, 1.3, 1.24)
	spare.rotation = Vector3(PI * 0.5, 0, 0)
	_body.add_child(spare)
	_body.add_child(LowPoly.cylinder(0.14, 0.9, cloth, Vector3(0, 1.85, 0.7), Vector3(0, 0, PI * 0.5), 8))

	# Wieżyczka na dachu klatki: podstawa + lufa, obraca się do celu.
	_turret = Node3D.new()
	_turret.position = Vector3(0, 2.14, 0.1)
	_body.add_child(_turret)
	_turret.add_child(LowPoly.cylinder(0.28, 0.16, frame, Vector3.ZERO, Vector3.ZERO, 10))
	_turret.add_child(LowPoly.box(Vector3(0.36, 0.24, 0.46), rust, Vector3(0, 0.18, 0.0)))
	_turret.add_child(LowPoly.box(Vector3(0.5, 0.3, 0.05), frame, Vector3(0, 0.22, -0.22)))
	_turret.add_child(LowPoly.cylinder(0.06, 0.95, rim, Vector3(0, 0.2, -0.6), Vector3(PI * 0.5, 0, 0), 8))
	_turret.add_child(LowPoly.box(Vector3(0.14, 0.2, 0.3), frame, Vector3(0.24, 0.2, 0.05)))
	_muzzle = MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.2
	flash_mesh.height = 0.4
	flash_mesh.radial_segments = 6
	flash_mesh.rings = 3
	_muzzle.mesh = flash_mesh
	_muzzle.material_override = Palette.glow(Color("ffe08a"), 8.0)
	_muzzle.position = Vector3(0, 0.2, -1.12)
	_muzzle.visible = false
	_turret.add_child(_muzzle)
	var line := BoxMesh.new()
	line.size = Vector3(0.05, 0.05, 22.0)
	_aim_line = MeshInstance3D.new()
	_aim_line.mesh = line
	_aim_line.material_override = Palette.translucent(Color(1.0, 0.35, 0.2, 0.55))
	_aim_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_line.position = Vector3(0, 0.2, -12.2)
	_aim_line.visible = false
	_turret.add_child(_aim_line)

	# Wyładowanie tarczy: iskry i niebieskawy błysk (bez bańki pola siłowego).
	_sparks = CPUParticles3D.new()
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.explosiveness = 0.9
	_sparks.amount = 70
	_sparks.lifetime = 0.45
	_sparks.direction = Vector3.UP
	_sparks.spread = 180.0
	_sparks.initial_velocity_min = 5.0
	_sparks.initial_velocity_max = 13.0
	_sparks.gravity = Vector3(0, -14.0, 0)
	_sparks.particle_flag_align_y = true
	_sparks.position = Vector3(0, 1.2, -0.2)
	var spark := BoxMesh.new()
	spark.size = Vector3(0.03, 0.5, 0.03)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(0.75, 0.92, 1.0)
	spark.material = spark_mat
	_sparks.mesh = spark
	add_child(_sparks)
	_spark_light = OmniLight3D.new()
	_spark_light.light_color = Color(0.6, 0.85, 1.0)
	_spark_light.omni_range = 9.0
	_spark_light.light_energy = 0.0
	_spark_light.visible = false
	_spark_light.position = Vector3(0, 1.8, 0)
	add_child(_spark_light)

	# Maszt z postrzępioną flagą i antena.
	_body.add_child(LowPoly.tube(Vector3(0.45, 2.0, 0.6), Vector3(0.45, 3.3, 0.78), 0.025, frame))
	_body.add_child(LowPoly.tube(Vector3(-0.45, 2.0, 0.6), Vector3(-0.5, 2.9, 0.85), 0.015, rim))
	_flag = Node3D.new()
	_flag.position = Vector3(0.45, 3.25, 0.78)
	_body.add_child(_flag)
	_flag.add_child(LowPoly.box(Vector3(0.03, 0.36, 0.5), Palette.mat(Palette.PAINT_RED), Vector3(0, -0.18, 0.25)))
	_flag.add_child(LowPoly.box(Vector3(0.03, 0.2, 0.25), Palette.mat(Palette.PAINT_RED), Vector3(0, -0.1, 0.6)))

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
	_dust.emission_box_extents = Vector3(1.1, 0.05, 0.1)
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


## Nogi kierowcy: biodro stałe, stopa na pedale, kolano z prostej kinematyki odwrotnej.
func _pose_legs() -> void:
	const THIGH := 0.56
	const SHIN := 0.56
	for i in _thighs.size():
		var side := -1.0 if i == 0 else 1.0
		var hip := Vector3(side * 0.16, 1.22, 0.3)
		var pedal := CRANK_CENTER + Vector3(side * 0.36, side * CRANK_RADIUS * cos(_crank_angle), side * CRANK_RADIUS * sin(_crank_angle))
		var v := Vector2(pedal.z - hip.z, pedal.y - hip.y)
		var dist := clampf(v.length(), 0.25, THIGH + SHIN - 0.01)
		var base := v.angle()
		var bend := acos(clampf((THIGH * THIGH + dist * dist - SHIN * SHIN) / (2.0 * THIGH * dist), -1.0, 1.0))
		# Z dwóch rozwiązań wybieramy kolano wyżej.
		var a1 := Vector2.from_angle(base + bend) * THIGH
		var a2 := Vector2.from_angle(base - bend) * THIGH
		var k2 := a1 if a1.y > a2.y else a2
		var knee := Vector3(side * 0.26, hip.y + k2.y, hip.z + k2.x)
		LowPoly.place_tube(_thighs[i], hip, knee)
		LowPoly.place_tube(_shins[i], knee, pedal)
