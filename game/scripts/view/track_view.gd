class_name TrackView
extends Node3D
## Nieskończony kanion: segmenty z puli (po 40 m) + obiekty z RunSimulation (wraki, złom).
## Pojazd stoi w z = 0, a świat przesuwa się względem niego – dzięki temu precyzja float
## nie spada nawet po godzinie jazdy (dystans trzymamy w float64 w symulacji).

const SEGMENT_LENGTH := 40.0
const SEGMENTS_AHEAD := 8
const SEGMENTS_BEHIND := 1
const ROAD_HALF_WIDTH := 6.2
const ITEM_VISIBLE_BEHIND := 25.0
const ITEM_VISIBLE_AHEAD := 300.0

var _segments: Array[Node3D] = []
var _segment_ids: Array[int] = []
var _item_nodes: Dictionary = {}
var _hit_anim: Dictionary = {}
var _pickup_anim: Dictionary = {}
var _time := 0.0


func _ready() -> void:
	var total := SEGMENTS_AHEAD + SEGMENTS_BEHIND + 1
	for i in total:
		var seg := Node3D.new()
		seg.name = "Segment%d" % i
		add_child(seg)
		_segments.append(seg)
		_segment_ids.append(-999999)


func sync(sim: RunSimulation, delta: float) -> void:
	_time += delta
	var d := sim.vehicle.distance_m
	_sync_segments(d)
	_sync_items(sim, d, delta)


# --- Segmenty kanionu -------------------------------------------------------

func _sync_segments(d: float) -> void:
	var total := _segments.size()
	var first := floori(d / SEGMENT_LENGTH) - SEGMENTS_BEHIND
	for k in total:
		var idx := first + k
		var slot := posmod(idx, total)
		if _segment_ids[slot] != idx:
			_build_segment(_segments[slot], idx)
			_segment_ids[slot] = idx
		_segments[slot].position = Vector3(0.0, 0.0, -(idx * SEGMENT_LENGTH - d))


func _build_segment(seg: Node3D, idx: int) -> void:
	for child in seg.get_children():
		child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(idx * 7919 + 17)
	var L := SEGMENT_LENGTH
	var center_z := -L * 0.5

	# Podłoże: piasek + stary asfalt.
	var ground := PlaneMesh.new()
	ground.size = Vector2(160.0, L)
	seg.add_child(LowPoly.mesh_instance(ground, Palette.mat(Palette.SAND), Vector3(0, 0, center_z)))
	var road := PlaneMesh.new()
	road.size = Vector2(ROAD_HALF_WIDTH * 2.0, L)
	seg.add_child(LowPoly.mesh_instance(road, Palette.mat(Palette.ROAD, 0.97), Vector3(0, 0.02, center_z)))

	# Przerywane linie między pasami (co 8 m) – dają poczucie prędkości.
	var paint := Palette.mat(Palette.LANE_PAINT, 0.9)
	for lane_line in [-1.8, 1.8]:
		for j in 5:
			if rng.randf() < 0.12:
				continue  # wytarta farba
			seg.add_child(LowPoly.box(Vector3(0.2, 0.02, 3.0), paint, Vector3(lane_line, 0.04, -j * 8.0 - 2.0)))
	# Linie krawędziowe – miejscami zasypane.
	for edge in [-ROAD_HALF_WIDTH + 0.35, ROAD_HALF_WIDTH - 0.35]:
		var z0 := 0.0
		while z0 < L:
			var len := rng.randf_range(4.0, 12.0)
			if rng.randf() > 0.25:
				seg.add_child(LowPoly.box(Vector3(0.16, 0.02, minf(len, L - z0)), paint, Vector3(edge, 0.04, -z0 - minf(len, L - z0) * 0.5)))
			z0 += len + rng.randf_range(1.0, 5.0)
	# Nawiany piasek na jezdni (poza środkiem pasów, żeby nie mylił z przeszkodą).
	var sand_drift := Palette.mat(Palette.SAND_DARK)
	for j in rng.randi_range(1, 3):
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		seg.add_child(LowPoly.box(Vector3(rng.randf_range(1.0, 2.6), 0.05, rng.randf_range(3.0, 9.0)), sand_drift, Vector3(side * rng.randf_range(4.6, 6.6), 0.03, -rng.randf_range(2.0, L - 2.0)), Vector3(0, rng.randf_range(-0.3, 0.3), 0)))

	# Ściany kanionu: nachodzące na siebie bloki skalne + dalsze mesy.
	var rock_colors := [Palette.ROCK_A, Palette.ROCK_B, Palette.ROCK_C, Palette.ROCK_D]
	for side: float in [-1.0, 1.0]:
		var z := rng.randf_range(0.0, 4.0)
		while z < L:
			var h := rng.randf_range(7.0, 20.0)
			var w := rng.randf_range(6.0, 11.0)
			var depth := rng.randf_range(9.0, 14.0)
			var x := side * (rng.randf_range(10.5, 14.0) + w * 0.4)
			var rock := LowPoly.mesh_instance(
				LowPoly.rock_mesh(rng.randi_range(0, 11), 0.3),
				Palette.mat(rock_colors[rng.randi_range(0, 3)]),
				Vector3(x, h * 0.32, -z),
				Vector3(w, h, depth) * 0.5,
				Vector3(0, rng.randf_range(0, TAU), 0))
			seg.add_child(rock)
			z += depth * rng.randf_range(0.55, 0.8)
		for j in 2:
			var mh := rng.randf_range(22.0, 42.0)
			var mesa := LowPoly.mesh_instance(
				LowPoly.rock_mesh(rng.randi_range(12, 19), 0.18),
				Palette.mat(rock_colors[rng.randi_range(0, 3)]),
				Vector3(side * rng.randf_range(26.0, 40.0), mh * 0.3, -rng.randf_range(0.0, L)),
				Vector3(rng.randf_range(14.0, 22.0), mh, rng.randf_range(16.0, 24.0)) * 0.5,
				Vector3(0, rng.randf_range(0, TAU), 0))
			seg.add_child(mesa)
		# Drobne kamienie na poboczu.
		for j in rng.randi_range(4, 8):
			var s := rng.randf_range(0.25, 1.1)
			seg.add_child(LowPoly.mesh_instance(
				LowPoly.rock_mesh(rng.randi_range(0, 11)),
				Palette.mat(rock_colors[rng.randi_range(0, 3)]),
				Vector3(side * rng.randf_range(6.8, 9.5), s * 0.25, -rng.randf_range(0.0, L)),
				Vector3(s, s * rng.randf_range(0.6, 1.0), s),
				Vector3(0, rng.randf_range(0, TAU), 0)))

	# Słup telegraficzny co segment (prawa strona) – rytm, który „czuć” przy prędkości.
	_add_pole(seg, Vector3(8.2, 0, -rng.randf_range(2.0, 6.0)), rng)
	# Rekwizyty: kaktusy, opony, beczki, znak drogowy.
	for j in rng.randi_range(1, 3):
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var pos := Vector3(side * rng.randf_range(7.0, 9.8), 0, -rng.randf_range(4.0, L - 4.0))
		match rng.randi_range(0, 3):
			0:
				_add_cactus(seg, pos, rng)
			1:
				_add_tire_stack(seg, pos, rng)
			2:
				_add_barrels(seg, pos, rng)
			_:
				_add_sign(seg, pos, rng)


func _add_pole(seg: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var wood := Palette.mat(Color("5a4636"))
	var lean := Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.06, 0.06))
	var pole := Node3D.new()
	pole.position = pos
	pole.rotation = lean
	pole.add_child(LowPoly.cylinder(0.14, 8.0, wood, Vector3(0, 4.0, 0), Vector3.ZERO, 6))
	pole.add_child(LowPoly.box(Vector3(2.2, 0.16, 0.16), wood, Vector3(0, 7.4, 0)))
	seg.add_child(pole)


func _add_cactus(seg: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var green := Palette.mat(Color("6f7d45"))
	var h := rng.randf_range(1.8, 3.4)
	var c := Node3D.new()
	c.position = pos
	c.add_child(LowPoly.cylinder(0.28, h, green, Vector3(0, h * 0.5, 0), Vector3.ZERO, 7))
	c.add_child(LowPoly.cylinder(0.18, 1.0, green, Vector3(0.45, h * 0.55, 0), Vector3(0, 0, -0.2), 6))
	c.add_child(LowPoly.cylinder(0.16, 0.8, green, Vector3(-0.4, h * 0.45, 0), Vector3(0, 0, 0.25), 6))
	seg.add_child(c)


func _add_tire_stack(seg: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var tire := Palette.mat(Palette.TIRE)
	var n := rng.randi_range(2, 4)
	for i in n:
		var t := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.28
		torus.outer_radius = 0.55
		torus.rings = 10
		torus.ring_segments = 6
		t.mesh = torus
		t.material_override = tire
		t.position = pos + Vector3(rng.randf_range(-0.08, 0.08), 0.14 + i * 0.27, rng.randf_range(-0.08, 0.08))
		seg.add_child(t)


func _add_barrels(seg: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var colors := [Palette.RUST, Palette.PAINT_TEAL, Palette.PAINT_MUSTARD]
	for i in rng.randi_range(1, 3):
		var tipped := rng.randf() < 0.4
		var b := LowPoly.cylinder(0.34, 1.0, Palette.mat(colors[rng.randi_range(0, 2)], 0.8, 0.3),
			pos + Vector3(i * 0.75, 0.34 if tipped else 0.5, rng.randf_range(-0.4, 0.4)),
			Vector3(PI * 0.5, rng.randf_range(0, TAU), 0) if tipped else Vector3.ZERO, 10)
		seg.add_child(b)


func _add_sign(seg: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var metal := Palette.mat(Palette.METAL, 0.6, 0.5)
	var s := Node3D.new()
	s.position = pos
	s.rotation = Vector3(0, rng.randf_range(-0.4, 0.4), rng.randf_range(-0.25, 0.25))
	s.add_child(LowPoly.cylinder(0.05, 2.4, metal, Vector3(0, 1.2, 0), Vector3.ZERO, 6))
	s.add_child(LowPoly.box(Vector3(1.1, 0.75, 0.05), Palette.mat(Palette.PAINT_MUSTARD, 0.7), Vector3(0, 2.2, 0)))
	seg.add_child(s)


# --- Obiekty na trasie -------------------------------------------------------

func _sync_items(sim: RunSimulation, d: float, delta: float) -> void:
	var seen := {}
	for item in sim.items:
		if item.distance_m < d - ITEM_VISIBLE_BEHIND or item.distance_m > d + ITEM_VISIBLE_AHEAD:
			continue
		seen[item.id] = true
		var node: Node3D = _item_nodes.get(item.id)
		if node == null:
			node = _make_item_node(item)
			_item_nodes[item.id] = node
			add_child(node)
		var base := Vector3(sim.lane_x(item.lane), 0.0, -(item.distance_m - d))
		if item.is_scrap():
			_animate_scrap(node, item, base, delta)
		else:
			_animate_wreck(node, item, base, delta)
	for id in _item_nodes.keys():
		if not seen.has(id):
			_item_nodes[id].queue_free()
			_item_nodes.erase(id)
			_hit_anim.erase(id)
			_pickup_anim.erase(id)


func _animate_scrap(node: Node3D, item: TrackItem, base: Vector3, delta: float) -> void:
	if item.consumed:
		var t: float = _pickup_anim.get(item.id, 0.0) + delta
		_pickup_anim[item.id] = t
		var k := clampf(t / 0.35, 0.0, 1.0)
		node.position = base + Vector3(0, 1.0 + k * 3.0, 0)
		node.scale = Vector3.ONE * maxf(0.01, 1.0 - k)
		node.visible = k < 1.0
		return
	node.position = base + Vector3(0, 0.9 + 0.18 * sin(_time * 3.0 + item.id), 0)
	node.rotation.y = _time * 2.2 + item.id


func _animate_wreck(node: Node3D, item: TrackItem, base: Vector3, delta: float) -> void:
	if item.consumed:
		var t: float = _hit_anim.get(item.id, 0.0) + delta
		_hit_anim[item.id] = t
		var k := clampf(t / 0.6, 0.0, 1.0)
		var side := -1.0 if item.lane == 0 else 1.0
		node.position = base + Vector3(side * k * 2.2, sin(k * PI) * 1.2, -k * 3.0)
		node.rotation = Vector3(k * 0.5, k * 0.9 * side, k * 0.6 * side)
	else:
		node.position = base


func _make_item_node(item: TrackItem) -> Node3D:
	match item.kind:
		TrackItem.Kind.WRECK:
			return WreckFactory.make(item.variant)
		TrackItem.Kind.SCRAP_BIG:
			return WreckFactory.make_scrap(true)
		_:
			return WreckFactory.make_scrap(false)
