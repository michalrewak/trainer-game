class_name RaidView
extends Node3D
## Widok napadów: drogowskaz i strzałki zjazdu podczas zwiadu, brama osady z wieżami
## i szperaczem, znaczniki miejsc, w które spadną pociski z wież.
## Wszystko stoi na trasie (pas + dystans) i przesuwa się razem ze światem.

var _sign: Node3D
var _sign_d := 0.0
var _gate: Node3D
var _door: Node3D
var _gate_d := 0.0
var _markers: Dictionary = {}
var _time := 0.0


func sync(sim: RunSimulation, delta: float) -> void:
	_time += delta
	var raids := sim.raids
	var pd := sim.vehicle.distance_m

	# Drogowskaz i strzałki na pasie zjazdu.
	if raids.state == RaidDirector.State.SCOUTING and _sign == null:
		_sign_d = float(raids.current["fork_d"])
		_sign = _build_exit(sim, int(raids.current["side"]))
		add_child(_sign)
	if _sign != null:
		_sign.position.z = -(_sign_d - pd)
		if pd > _sign_d + 40.0:
			_sign.queue_free()
			_sign = null

	# Brama z wieżami.
	if raids.is_raiding() and _gate == null:
		_gate_d = raids.gate_d
		_gate = _build_gate(int(raids.current["towers"]))
		add_child(_gate)
	if _gate != null:
		_gate.position.z = -(_gate_d - pd)
		if _door != null and raids.gate_hp <= 0 and _door.visible:
			_door.visible = false
		if pd > _gate_d + 40.0:
			_gate.queue_free()
			_gate = null
			_door = null

	# Znaczniki ostrzału.
	var seen := {}
	for shell in raids.shells:
		var id: int = shell["id"]
		seen[id] = true
		var m: Node3D = _markers.get(id)
		if m == null:
			m = _build_marker()
			add_child(m)
			_markers[id] = m
		var k := clampf(float(shell["t_left"]) / RaidDirector.SHELL_FLIGHT_S, 0.0, 1.0)
		m.position = Vector3(sim.lane_x(int(shell["lane"])), 0.12, -(float(shell["d"]) - pd))
		var s := lerpf(1.0, 2.4, k)
		m.scale = Vector3(s, 1.0, s)
		m.visible = fmod(_time * (4.0 + (1.0 - k) * 10.0), 1.0) < 0.7
	for id in _markers.keys():
		if not seen.has(id):
			_markers[id].queue_free()
			_markers.erase(id)


func _build_exit(sim: RunSimulation, side: int) -> Node3D:
	var root := Node3D.new()
	var pole := Palette.mat(Color("4b4744"), 0.6, 0.5)
	var board := Palette.glow(Color("ffb238"), 1.4)
	# Tablica 120 m przed zjazdem, po stronie osady.
	var sign := Node3D.new()
	sign.position = Vector3(side * 8.4, 0, 120.0)
	sign.add_child(LowPoly.cylinder(0.12, 5.0, pole, Vector3(0, 2.5, 0), Vector3.ZERO, 6))
	sign.add_child(LowPoly.box(Vector3(2.6, 1.3, 0.12), Palette.mat(Color("2a2826"), 0.7, 0.4), Vector3(0, 4.6, 0)))
	sign.add_child(LowPoly.box(Vector3(1.3, 0.3, 0.16), board, Vector3(-side * 0.2, 4.6, 0)))
	sign.add_child(LowPoly.box(Vector3(0.7, 0.3, 0.16), board, Vector3(side * 0.55, 4.82, 0), Vector3(0, 0, -side * 0.7)))
	sign.add_child(LowPoly.box(Vector3(0.7, 0.3, 0.16), board, Vector3(side * 0.55, 4.38, 0), Vector3(0, 0, side * 0.7)))
	root.add_child(sign)
	# Strzałki na pasie zjazdu przez ostatnie 200 m.
	var x := sim.lane_x(0 if side < 0 else sim.lanes.lane_count - 1)
	var paint := Palette.glow(Color("ffb238"), 0.9)
	for i in 8:
		var z := 25.0 + i * 25.0
		root.add_child(LowPoly.box(Vector3(1.3, 0.03, 0.3), paint, Vector3(x - side * 0.35, 0.06, z - side * 0.0), Vector3(0, side * 0.75, 0)))
		root.add_child(LowPoly.box(Vector3(1.3, 0.03, 0.3), paint, Vector3(x + side * 0.35, 0.06, z + 0.0), Vector3(0, -side * 0.75, 0)))
	return root


func _build_gate(towers: int) -> Node3D:
	var root := Node3D.new()
	var wall := Palette.mat(Color("5a4a3e"), 0.9, 0.2)
	var rust := Palette.mat(Palette.RUST, 0.9, 0.3)
	var dark := Palette.mat(Color("2a2422"), 0.8, 0.3)
	var steel := Palette.mat(Color("a8a094"), 0.45, 0.8)
	var lamp := Palette.glow(Color("fff0c0"), 3.0)
	# Wieże po bokach drogi (trzecia, gdy osada ma ich więcej, stoi w głębi).
	var spots: Array[Vector3] = [Vector3(-9.0, 0, 0), Vector3(9.0, 0, 0), Vector3(-12.0, 0, -14.0)]
	for i in maxi(2, towers):
		var t := Node3D.new()
		t.position = spots[i]
		t.add_child(LowPoly.box(Vector3(3.4, 9.0, 3.4), wall, Vector3(0, 4.5, 0)))
		t.add_child(LowPoly.box(Vector3(4.4, 0.4, 4.4), rust, Vector3(0, 9.2, 0)))
		for c: Vector3 in [Vector3(-1.9, 10.0, -1.9), Vector3(1.9, 10.0, -1.9), Vector3(-1.9, 10.0, 1.9), Vector3(1.9, 10.0, 1.9)]:
			t.add_child(LowPoly.box(Vector3(0.5, 1.2, 0.5), rust, c))
		# Działo wieży wycelowane w drogę i szperacz.
		if i < towers:
			t.add_child(LowPoly.cylinder(0.18, 2.6, dark, Vector3(-signf(spots[i].x) * 0.8, 10.2, 1.4), Vector3(1.2, 0, signf(spots[i].x) * 0.5), 8))
		t.add_child(LowPoly.cylinder(0.35, 0.3, lamp, Vector3(0, 10.9, 1.2), Vector3(PI * 0.5, 0, 0), 8))
		t.add_child(LowPoly.mesh_instance(_cone(), Palette.translucent(Color(1.0, 0.95, 0.75, 0.1)), Vector3(0, 6.0, 9.0), Vector3(5.0, 16.0, 5.0), Vector3(-1.1, 0, 0)))
		t.add_child(LowPoly.tube(Vector3(0, 9.4, 0), Vector3(0, 13.5, 0), 0.06, dark))
		t.add_child(LowPoly.box(Vector3(0.05, 0.8, 1.3), Palette.mat(Palette.PAINT_RED), Vector3(0, 13.0, 0.7)))
		root.add_child(t)
	# Mur z gruzu i blach od wież w głąb pustyni.
	for side: float in [-1.0, 1.0]:
		for k in 5:
			root.add_child(LowPoly.box(Vector3(5.2, 3.2 + (k % 2) * 0.8, 1.2), wall if k % 2 == 0 else rust, Vector3(side * (13.0 + k * 5.0), 1.8, 0.3 * (k % 3)), Vector3(0, 0.06 * (k % 3 - 1), 0)))
	# Wrota z kolcami w poprzek drogi (bez nadproża – kamera przejeżdża nad bramą).
	_door = Node3D.new()
	for side: float in [-1.0, 1.0]:
		_door.add_child(LowPoly.box(Vector3(3.6, 5.6, 0.3), rust, Vector3(side * 1.85, 2.9, 0)))
		_door.add_child(LowPoly.box(Vector3(3.3, 5.6, 0.3), rust, Vector3(side * 5.4, 2.9, 0)))
		_door.add_child(LowPoly.box(Vector3(3.6, 0.4, 0.4), dark, Vector3(side * 1.85, 4.2, 0.1)))
		_door.add_child(LowPoly.box(Vector3(3.6, 0.4, 0.4), dark, Vector3(side * 1.85, 1.6, 0.1)))
		for k in 3:
			_door.add_child(LowPoly.cylinder(0.08, 0.7, steel, Vector3(side * (0.8 + k * 1.1), 2.9, 0.45), Vector3(PI * 0.5, 0, 0), 5))
	root.add_child(_door)
	return root


func _build_marker() -> Node3D:
	var root := Node3D.new()
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.15
	torus.rings = 20
	torus.ring_segments = 4
	ring.mesh = torus
	ring.material_override = Palette.glow(Color("ff3020"), 3.0)
	root.add_child(ring)
	root.add_child(LowPoly.cylinder(0.3, 0.05, Palette.glow(Color("ff3020"), 3.0), Vector3.ZERO, Vector3.ZERO, 10))
	return root


static var _cone_mesh: Mesh

static func _cone() -> Mesh:
	if _cone_mesh == null:
		var m := CylinderMesh.new()
		m.top_radius = 0.05
		m.bottom_radius = 0.5
		m.height = 1.0
		m.radial_segments = 10
		m.rings = 1
		_cone_mesh = m
	return _cone_mesh
