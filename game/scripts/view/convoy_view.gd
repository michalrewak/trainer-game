class_name ConvoyView
extends Node3D
## Miny beczkowe zrzucane przez strażnika z ogona konwoju: beczka leci na pas, a na
## drodze miga czerwony pierścień – miejsce wybuchu. Same wagony rysuje ConvoyPartView.

var _markers: Dictionary = {}
var _time := 0.0


func sync(sim: RunSimulation, delta: float) -> void:
	_time += delta
	var pd := sim.vehicle.distance_m
	var seen := {}
	for mine in sim.convoys.mines:
		var id: int = mine["id"]
		seen[id] = true
		var m: Node3D = _markers.get(id)
		if m == null:
			m = _build_marker()
			add_child(m)
			_markers[id] = m
		var k := clampf(float(mine["t_left"]) / ConvoyDirector.MINE_FUSE_S, 0.0, 1.0)
		m.position = Vector3(sim.lane_x(int(mine["lane"])), 0.0, -(float(mine["d"]) - pd))
		var ring := m.get_child(0) as Node3D
		var s := lerpf(1.0, 2.2, k)
		ring.scale = Vector3(s, 1.0, s)
		ring.visible = fmod(_time * (4.0 + (1.0 - k) * 10.0), 1.0) < 0.7
		var barrel := m.get_child(1) as Node3D
		barrel.position.y = 0.4 + k * k * 5.0
		barrel.rotation.x = _time * 9.0
	for id in _markers.keys():
		if not seen.has(id):
			_markers[id].queue_free()
			_markers.erase(id)


func _build_marker() -> Node3D:
	var root := Node3D.new()
	var ring := Node3D.new()
	ring.position.y = 0.12
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.15
	torus.rings = 20
	torus.ring_segments = 4
	ring.add_child(LowPoly.mesh_instance(torus, Palette.glow(Color("ff3020"), 3.0)))
	root.add_child(ring)
	var barrel := Node3D.new()
	barrel.add_child(LowPoly.cylinder(0.32, 0.75, Palette.mat(Color("26211f"), 0.8, 0.35), Vector3.ZERO, Vector3(0, 0, PI * 0.5), 8))
	barrel.add_child(LowPoly.cylinder(0.33, 0.14, Palette.glow(Color("ff3020"), 2.5), Vector3.ZERO, Vector3(0, 0, PI * 0.5), 8))
	root.add_child(barrel)
	return root
