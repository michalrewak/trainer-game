class_name LowPoly
extends RefCounted
## Proceduralne siatki low-poly (płaskie cieniowanie): skały, koła, rury.
## Używane, gdy nie ma modeli z paczek CC0, oraz do elementów, których paczki nie mają.

static var _rock_cache: Dictionary = {}


## Kanciasta skała: zdeformowany dwudziestościan z płaskimi ścianami.
static func rock_mesh(seed_value: int, roughness: float = 0.28) -> ArrayMesh:
	var key := "%d|%.2f" % [seed_value, roughness]
	if _rock_cache.has(key):
		return _rock_cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	var faces := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]
	var displaced: Array[Vector3] = []
	for v in verts:
		var n := v.normalized()
		var r := 1.0 + rng.randf_range(-roughness, roughness)
		var p := n * r
		# Spłaszczony spód – skała „siedzi” na ziemi.
		if p.y < -0.35:
			p.y = -0.35 + (p.y + 0.35) * 0.25
		displaced.append(p)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in faces:
		var a: Vector3 = displaced[f[0]]
		var b: Vector3 = displaced[f[1]]
		var c: Vector3 = displaced[f[2]]
		var normal := (c - a).cross(b - a).normalized()
		for p in [a, c, b]:
			st.set_normal(-normal)
			st.add_vertex(p)
	var mesh := st.commit()
	_rock_cache[key] = mesh
	return mesh


static func mesh_instance(mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO, scale_v: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.scale = scale_v
	mi.rotation = rot
	return mi


static func box(size: Vector3, material: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return mesh_instance(m, material, pos, Vector3.ONE, rot)


static func cylinder(radius: float, height: float, material: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, sides: int = 10) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = sides
	m.rings = 1
	return mesh_instance(m, material, pos, Vector3.ONE, rot)


## Rura między dwoma punktami (rama buggy, pręty, maszt).
static func tube(from: Vector3, to: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var length := from.distance_to(to)
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = length
	m.radial_segments = 6
	m.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	var mid := (from + to) * 0.5
	var dir := (to - from).normalized()
	var up := Vector3.UP
	var basis := Basis()
	if absf(dir.dot(up)) > 0.999:
		basis = Basis.IDENTITY if dir.y > 0 else Basis(Vector3.RIGHT, PI)
	else:
		var axis := up.cross(dir).normalized()
		basis = Basis(axis, acos(clampf(up.dot(dir), -1.0, 1.0)))
	mi.transform = Transform3D(basis, mid)
	return mi


## Rura o jednostkowej długości do animacji – ustawiana co klatkę przez place_tube.
static func unit_tube(radius: float, material: Material) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	return mi


## Rozciąga rurę z unit_tube między dwoma punktami (w układzie rodzica).
static func place_tube(mi: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var length := maxf(from.distance_to(to), 0.001)
	var dir := (to - from) / length
	var basis := Basis.IDENTITY
	if absf(dir.dot(Vector3.UP)) > 0.999:
		basis = Basis.IDENTITY if dir.y > 0 else Basis(Vector3.RIGHT, PI)
	else:
		basis = Basis(Vector3.UP.cross(dir).normalized(), acos(clampf(Vector3.UP.dot(dir), -1.0, 1.0)))
	mi.transform = Transform3D(basis * Basis.from_scale(Vector3(1.0, length, 1.0)), (from + to) * 0.5)
