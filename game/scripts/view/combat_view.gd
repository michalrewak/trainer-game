class_name CombatView
extends Node3D
## Rysuje walkę z CombatModel: pojazdy gangu, pociski z wieżyczki, wybuchy i znacznik celu.

var _raider_views: Dictionary = {}
var _projectile_views: Dictionary = {}
var _projectile_mesh: Mesh
var _projectile_mat: StandardMaterial3D
var _target_marker: Node3D
var _explosions: Array[Dictionary] = []


func _ready() -> void:
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.09
	capsule.height = 0.9
	capsule.radial_segments = 6
	capsule.rings = 2
	_projectile_mesh = capsule
	_projectile_mat = Palette.glow(Color("ffd05a"), 6.0)
	_target_marker = _make_marker()
	add_child(_target_marker)


func sync(sim: RunSimulation, delta: float) -> void:
	var combat := sim.combat
	var pd := sim.vehicle.distance_m
	var seen := {}
	for r in combat.raiders:
		seen[r.id] = true
		var v: RaiderView = _raider_views.get(r.id)
		if v == null:
			v = RaiderView.new()
			v.build(r.variant, r.side)
			add_child(v)
			_raider_views[r.id] = v
		v.sync(r, pd, delta)
	for id in _raider_views.keys():
		if not seen.has(id):
			_raider_views[id].queue_free()
			_raider_views.erase(id)

	var seen_p := {}
	for p in combat.projectiles:
		var pid: int = p["id"]
		seen_p[pid] = true
		var mi: MeshInstance3D = _projectile_views.get(pid)
		if mi == null:
			mi = MeshInstance3D.new()
			mi.mesh = _projectile_mesh
			mi.material_override = _projectile_mat
			add_child(mi)
			_projectile_views[pid] = mi
		var pos := Vector3(float(p["x"]), 1.9, -(float(p["d"]) - pd))
		mi.position = pos
		var dir := Vector3(float(p["vx"]), 0.0, -(float(p["vd"]) - sim.vehicle.speed_mps))
		if dir.length() > 0.01:
			mi.look_at(pos + dir, Vector3.UP)
			mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	for pid in _projectile_views.keys():
		if not seen_p.has(pid):
			_projectile_views[pid].queue_free()
			_projectile_views.erase(pid)

	var target := combat.current_target()
	_target_marker.visible = target != null
	if target != null:
		_target_marker.position = Vector3(target.x, 0.08, -(target.d - pd))
		_target_marker.rotation.y += delta * 2.5
	_update_explosions(delta)


## Wybuch w miejscu zniszczonego wroga (pozycja względem gracza w chwili zniszczenia).
func explode_at(local_pos: Vector3) -> void:
	var burst := CPUParticles3D.new()
	burst.one_shot = true
	burst.explosiveness = 0.95
	burst.amount = 36
	burst.lifetime = 0.9
	burst.direction = Vector3.UP
	burst.spread = 80.0
	burst.initial_velocity_min = 5.0
	burst.initial_velocity_max = 11.0
	burst.gravity = Vector3(0, -9.0, 0)
	burst.scale_amount_min = 0.4
	burst.scale_amount_max = 1.1
	var cube := BoxMesh.new()
	cube.size = Vector3(0.35, 0.35, 0.35)
	cube.material = Palette.glow(Color("ff8a2a"), 4.0)
	burst.mesh = cube
	burst.position = local_pos + Vector3(0, 1.0, 0)
	add_child(burst)
	burst.emitting = true
	var light := OmniLight3D.new()
	light.light_color = Color("ffa040")
	light.light_energy = 6.0
	light.omni_range = 12.0
	light.position = local_pos + Vector3(0, 2.0, 0)
	add_child(light)
	_explosions.append({"burst": burst, "light": light, "t": 0.0})


func _update_explosions(delta: float) -> void:
	for i in range(_explosions.size() - 1, -1, -1):
		var e: Dictionary = _explosions[i]
		e["t"] = float(e["t"]) + delta
		var light: OmniLight3D = e["light"]
		light.light_energy = maxf(0.0, 6.0 * (1.0 - float(e["t"]) / 0.5))
		if float(e["t"]) > 1.5:
			(e["burst"] as Node).queue_free()
			light.queue_free()
			_explosions.remove_at(i)


func _make_marker() -> Node3D:
	var root := Node3D.new()
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.5
	torus.outer_radius = 1.75
	torus.rings = 24
	torus.ring_segments = 4
	ring.mesh = torus
	ring.material_override = Palette.glow(Color("ffd05a"), 2.5)
	root.add_child(ring)
	root.visible = false
	return root
