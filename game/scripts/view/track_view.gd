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

## Wygląd terenu: "canyon" (Kanion Rdzy) albo "city" (Martwe Miasto). Ustaw przed pierwszym sync.
var theme := "canyon"
## Zakres dystansu [m] zabudowany jak osada (napad): ruiny zamiast kanionu.
var town_from := -1.0
var town_to := -1.0

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


## Trasa składa się z odcinków po 5 segmentów (200 m): kanion albo otwarta pustynia.
static func is_canyon_section(idx: int) -> bool:
	return posmod(hash(floori(idx / 5.0) * 31 + 7), 100) < 45


enum Surface { ASPHALT, DIRT, CONCRETE, STEEL }

## Nawierzchnia zmienia się co odcinek (5 segmentów = 200 m): stary asfalt, szuter
## z koleinami, betonowe płyty albo stalowe maty. Start zawsze na asfalcie.
static func road_surface(idx: int) -> Surface:
	var section := floori(idx / 5.0)
	if section <= 0:
		return Surface.ASPHALT
	var roll := posmod(hash(section * 53 + 11), 100)
	if roll < 34:
		return Surface.ASPHALT
	if roll < 64:
		return Surface.DIRT
	if roll < 84:
		return Surface.CONCRETE
	return Surface.STEEL


static func surface_name(surface: Surface) -> String:
	return ["asfalt", "szuter", "betonowe płyty", "stalowe maty"][surface]


## Jezdnia segmentu. Elementy wzdłuż drogi mają najwyżej 8 m, żeby shader mógł je wygiąć
## razem z jezdnią na zakrętach i wzniesieniach.
func _build_road(seg: Node3D, idx: int, rng: RandomNumberGenerator) -> void:
	var L := SEGMENT_LENGTH
	var center_z := -L * 0.5
	var surface := road_surface(idx)
	if theme == "city" and surface == Surface.DIRT:
		surface = Surface.CONCRETE
	var road := PlaneMesh.new()
	road.size = Vector2(ROAD_HALF_WIDTH * 2.0, L)
	road.subdivide_width = 3
	road.subdivide_depth = 9
	var road_mat: Material = Palette.road()
	match surface:
		Surface.DIRT:
			road_mat = Palette.mat(Color("a4683e"), 0.98, 0.0, Palette.Kind.SAND)
		Surface.CONCRETE:
			road_mat = Palette.road(Color("a59c90"))
		Surface.STEEL:
			road_mat = Palette.mat(Color("7c6c60"), 0.5, 0.75)
	seg.add_child(LowPoly.mesh_instance(road, road_mat, Vector3(0, 0.03, center_z)))
	match surface:
		Surface.ASPHALT:
			_paint_asphalt(seg, rng)
		Surface.DIRT:
			_paint_dirt(seg, rng)
		Surface.CONCRETE:
			_paint_concrete(seg, rng)
		Surface.STEEL:
			_paint_steel(seg, rng)


## Stary asfalt: przerywane linie między pasami i wytarte linie krawędziowe.
func _paint_asphalt(seg: Node3D, rng: RandomNumberGenerator) -> void:
	var L := SEGMENT_LENGTH
	var paint := Palette.mat(Palette.LANE_PAINT, 0.9)
	for lane_line in [-1.8, 1.8]:
		for j in 5:
			if rng.randf() < 0.12:
				continue  # wytarta farba
			seg.add_child(LowPoly.box(Vector3(0.2, 0.02, 3.0), paint, Vector3(lane_line, 0.04, -j * 8.0 - 2.0)))
	for edge in [-ROAD_HALF_WIDTH + 0.35, ROAD_HALF_WIDTH - 0.35]:
		var z0 := 0.0
		while z0 < L:
			var len := rng.randf_range(4.0, 12.0)
			if rng.randf() > 0.25:
				seg.add_child(LowPoly.box(Vector3(0.16, 0.02, minf(len, L - z0)), paint, Vector3(edge, 0.04, -z0 - minf(len, L - z0) * 0.5)))
			z0 += len + rng.randf_range(1.0, 5.0)


## Szuter: wyjeżdżone koleiny na każdym pasie, kamienie i grzbiety piasku między pasami.
func _paint_dirt(seg: Node3D, rng: RandomNumberGenerator) -> void:
	var rut := Palette.mat(Color("7c4a2a"), 0.98, 0.0, Palette.Kind.SAND)
	var ridge := Palette.mat(Color("c08650"), 0.98, 0.0, Palette.Kind.SAND)
	for lane_x: float in [-3.6, 0.0, 3.6]:
		for wheel: float in [-0.75, 0.75]:
			for j in 5:
				if rng.randf() < 0.1:
					continue
				seg.add_child(LowPoly.box(Vector3(0.42, 0.02, 7.6), rut, Vector3(lane_x + wheel + rng.randf_range(-0.06, 0.06), 0.04, -j * 8.0 - 4.0)))
	for line_x: float in [-1.8, 1.8]:
		for j in 5:
			if rng.randf() < 0.35:
				seg.add_child(LowPoly.box(Vector3(rng.randf_range(0.5, 0.9), 0.06, rng.randf_range(3.0, 7.0)), ridge, Vector3(line_x, 0.04, -j * 8.0 - 4.0)))
	for j in rng.randi_range(5, 9):
		var s := rng.randf_range(0.12, 0.3)
		seg.add_child(LowPoly.mesh_instance(LowPoly.rock_mesh(rng.randi_range(0, 11)), Palette.rock(Palette.ROCK_C),
			Vector3([-1.8, 1.8, -5.6, 5.6][rng.randi_range(0, 3)] + rng.randf_range(-0.3, 0.3), s * 0.2, -rng.randf_range(0.0, SEGMENT_LENGTH)), Vector3(s, s * 0.7, s)))


## Betonowe płyty: poprzeczne dylatacje co 5 m, szwy wzdłuż pasów, pęknięcia i łaty smoły.
func _paint_concrete(seg: Node3D, rng: RandomNumberGenerator) -> void:
	var joint := Palette.mat(Color("3a342e"), 0.95)
	var tar := Palette.mat(Color("2a2622"), 0.7)
	for j in 8:
		seg.add_child(LowPoly.box(Vector3(ROAD_HALF_WIDTH * 2.0, 0.02, 0.14), joint, Vector3(0, 0.04, -j * 5.0 - 0.1)))
	for line_x: float in [-1.8, 1.8]:
		for j in 8:
			seg.add_child(LowPoly.box(Vector3(0.1, 0.02, 4.7), joint, Vector3(line_x, 0.04, -j * 5.0 - 2.5)))
	for j in rng.randi_range(2, 5):
		seg.add_child(LowPoly.box(Vector3(rng.randf_range(0.06, 0.1), 0.02, rng.randf_range(1.5, 3.5)), joint,
			Vector3(rng.randf_range(-5.4, 5.4), 0.045, -rng.randf_range(2.0, SEGMENT_LENGTH - 2.0)), Vector3(0, rng.randf_range(-1.0, 1.0), 0)))
	for j in rng.randi_range(0, 2):
		seg.add_child(LowPoly.box(Vector3(rng.randf_range(0.8, 1.6), 0.02, rng.randf_range(0.8, 2.0)), tar,
			Vector3([-5.4, -1.8, 1.8, 5.4][rng.randi_range(0, 3)], 0.045, -rng.randf_range(2.0, SEGMENT_LENGTH - 2.0)), Vector3(0, rng.randf_range(-0.4, 0.4), 0)))
	# Żółte znaczniki krawędzi – resztki dawnej drogi wojskowej.
	var mark := Palette.mat(Palette.PAINT_MUSTARD, 0.9)
	for edge: float in [-ROAD_HALF_WIDTH + 0.3, ROAD_HALF_WIDTH - 0.3]:
		for j in 4:
			if rng.randf() > 0.3:
				seg.add_child(LowPoly.box(Vector3(0.22, 0.02, 2.4), mark, Vector3(edge, 0.045, -j * 10.0 - 3.0)))


## Stalowe maty: spawane płyty co 2,5 m, listwy prowadzące między pasami, żółto-czarne
## krawężniki. Blacha błyszczy inaczej niż asfalt i dudni pod kołami.
func _paint_steel(seg: Node3D, rng: RandomNumberGenerator) -> void:
	var seam := Palette.mat(Color("2c2622"), 0.7, 0.4)
	var strip := Palette.mat(Color("a8a094"), 0.4, 0.85)
	var yellow := Palette.mat(Palette.PAINT_MUSTARD, 0.8, 0.2)
	for j in 16:
		seg.add_child(LowPoly.box(Vector3(ROAD_HALF_WIDTH * 2.0, 0.03, 0.1), seam, Vector3(0, 0.045, -j * 2.5 - 0.05)))
	for line_x: float in [-1.8, 1.8]:
		for j in 8:
			seg.add_child(LowPoly.box(Vector3(0.12, 0.05, 4.6), strip, Vector3(line_x, 0.05, -j * 5.0 - 2.5)))
	for edge: float in [-ROAD_HALF_WIDTH + 0.15, ROAD_HALF_WIDTH - 0.15]:
		for j in 10:
			seg.add_child(LowPoly.box(Vector3(0.3, 0.22, 2.0), yellow if j % 2 == 0 else seam, Vector3(edge, 0.12, -j * 4.0 - 1.0)))
	# Łaty rdzy i przyspawane nakładki.
	for j in rng.randi_range(1, 3):
		seg.add_child(LowPoly.box(Vector3(rng.randf_range(1.0, 2.0), 0.03, rng.randf_range(1.0, 2.2)), Palette.mat(Palette.RUST, 0.9, 0.3),
			Vector3([-3.6, 0.0, 3.6][rng.randi_range(0, 2)] + rng.randf_range(-0.5, 0.5), 0.05, -rng.randf_range(2.0, SEGMENT_LENGTH - 2.0)), Vector3(0, rng.randf_range(-0.2, 0.2), 0)))


func _build_segment(seg: Node3D, idx: int) -> void:
	for child in seg.get_children():
		child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(idx * 7919 + 17)
	var L := SEGMENT_LENGTH
	var center_z := -L * 0.5

	# Podłoże: piasek + stary asfalt.
	# Siatki są gęste, bo shader wygina je w zakręty i wzniesienia oraz usypuje wydmy.
	var ground := PlaneMesh.new()
	ground.size = Vector2(260.0, L)
	ground.subdivide_width = 64
	ground.subdivide_depth = 9
	var ground_mi := LowPoly.mesh_instance(ground, Palette.sand(Palette.SAND, 1.0), Vector3(0, 0, center_z))
	ground_mi.extra_cull_margin = 60.0
	seg.add_child(ground_mi)
	_build_road(seg, idx, rng)
	# Nawiany piasek na jezdni (poza środkiem pasów, żeby nie mylił z przeszkodą).
	var sand_drift := Palette.mat(Palette.SAND_DARK)
	for j in rng.randi_range(1, 3):
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		seg.add_child(LowPoly.box(Vector3(rng.randf_range(1.0, 2.6), 0.05, rng.randf_range(3.0, 9.0)), sand_drift, Vector3(side * rng.randf_range(4.6, 6.6), 0.03, -rng.randf_range(2.0, L - 2.0)), Vector3(0, rng.randf_range(-0.3, 0.3), 0)))

	var mid_d := (idx + 0.5) * SEGMENT_LENGTH
	if theme == "city" or (town_to > town_from and mid_d >= town_from and mid_d <= town_to):
		_build_city_sides(seg, rng)
		return

	# Ściany kanionu: nachodzące na siebie bloki skalne + dalsze mesy.
	var rock_colors := [Palette.ROCK_A, Palette.ROCK_B, Palette.ROCK_C, Palette.ROCK_D]
	var canyon := is_canyon_section(idx)
	for side: float in [-1.0, 1.0]:
		var z := rng.randf_range(0.0, 4.0)
		# Otwarta pustynia: zamiast ściany pojedyncze ostańce dalej od drogi.
		while not canyon and z < L:
			if rng.randf() < 0.3:
				var oh := rng.randf_range(3.0, 11.0)
				var ow := rng.randf_range(4.0, 10.0)
				seg.add_child(LowPoly.mesh_instance(
					LowPoly.rock_mesh(rng.randi_range(0, 11), 0.3),
					Palette.rock(rock_colors[rng.randi_range(0, 3)]),
					Vector3(side * rng.randf_range(16.0, 60.0), oh * 0.3, -z),
					Vector3(ow, oh, ow * rng.randf_range(0.8, 1.4)) * 0.5,
					Vector3(0, rng.randf_range(0, TAU), 0)))
			z += rng.randf_range(8.0, 16.0)
		while canyon and z < L:
			var h := rng.randf_range(7.0, 20.0)
			var w := rng.randf_range(6.0, 11.0)
			var depth := rng.randf_range(9.0, 14.0)
			var x := side * (rng.randf_range(10.5, 14.0) + w * 0.4)
			var rock := LowPoly.mesh_instance(
				LowPoly.rock_mesh(rng.randi_range(0, 11), 0.3),
				Palette.rock(rock_colors[rng.randi_range(0, 3)]),
				Vector3(x, h * 0.32, -z),
				Vector3(w, h, depth) * 0.5,
				Vector3(0, rng.randf_range(0, TAU), 0))
			seg.add_child(rock)
			z += depth * rng.randf_range(0.55, 0.8)
		for j in (2 if canyon else rng.randi_range(0, 1)):
			var mh := rng.randf_range(22.0, 42.0)
			var mesa := LowPoly.mesh_instance(
				LowPoly.rock_mesh(rng.randi_range(12, 19), 0.18),
				Palette.rock(rock_colors[rng.randi_range(0, 3)]),
				Vector3(side * (rng.randf_range(26.0, 40.0) if canyon else rng.randf_range(70.0, 110.0)), mh * 0.3, -rng.randf_range(0.0, L)),
				Vector3(rng.randf_range(14.0, 22.0), mh, rng.randf_range(16.0, 24.0)) * 0.5,
				Vector3(0, rng.randf_range(0, TAU), 0))
			seg.add_child(mesa)
		# Drobne kamienie na poboczu.
		for j in rng.randi_range(4, 8):
			var s := rng.randf_range(0.25, 1.1)
			seg.add_child(LowPoly.mesh_instance(
				LowPoly.rock_mesh(rng.randi_range(0, 11)),
				Palette.rock(rock_colors[rng.randi_range(0, 3)]),
				Vector3(side * rng.randf_range(6.8, 9.5), s * 0.25, -rng.randf_range(0.0, L)),
				Vector3(s, s * rng.randf_range(0.6, 1.0), s),
				Vector3(0, rng.randf_range(0, TAU), 0)))

	# Słup telegraficzny co segment (prawa strona) – rytm, który „czuć” przy prędkości.
	_add_pole(seg, Vector3(8.2, 0, -rng.randf_range(2.0, 6.0)), rng)
	# Rekwizyty: kaktusy, opony, beczki, znak drogowy.
	for j in rng.randi_range(1, 3):
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var pos := Vector3(side * rng.randf_range(7.0, 9.8), 0, -rng.randf_range(4.0, L - 4.0))
		# Połowa rekwizytów z paczki Kenney (beczki, skały, znaki, blaszaki), reszta z prymitywów.
		if rng.randf() < 0.5:
			var prop := KenneyModels.roadside_prop(rng)
			if prop != null:
				prop.position = pos
				seg.add_child(prop)
				continue
		match rng.randi_range(0, 3):
			0:
				_add_cactus(seg, pos, rng)
			1:
				_add_tire_stack(seg, pos, rng)
			2:
				_add_barrels(seg, pos, rng)
			_:
				_add_sign(seg, pos, rng)


## Martwe Miasto: zrujnowane bloki z pasami okien, chodniki, latarnie, billboardy, gruz.
func _build_city_sides(seg: Node3D, rng: RandomNumberGenerator) -> void:
	var L := SEGMENT_LENGTH
	var concrete: Array[Color] = [Color("9c9184"), Color("8a8277"), Color("b3a58f"), Color("6e6a63"), Color("a2826a")]
	var window_mat := Palette.mat(Color("2a2522"))
	var sidewalk := Palette.mat(Color("8f877c"))
	var rubble := Palette.mat(Color("7d756b"))
	for side: float in [-1.0, 1.0]:
		# Chodnik (miejscami zerwany).
		var z0 := 0.0
		while z0 < L:
			var len := rng.randf_range(5.0, 14.0)
			if rng.randf() > 0.2:
				seg.add_child(LowPoly.box(Vector3(2.2, 0.18, minf(len, L - z0)), sidewalk, Vector3(side * 7.5, 0.09, -z0 - minf(len, L - z0) * 0.5)))
			z0 += len + rng.randf_range(0.5, 3.0)
		# Bloki.
		var z := rng.randf_range(0.0, 3.0)
		while z < L:
			var w := rng.randf_range(7.0, 12.0)
			var depth := rng.randf_range(8.0, 13.0)
			var h := rng.randf_range(7.0, 24.0)
			var x := side * (rng.randf_range(11.0, 13.5) + w * 0.5)
			var b := Node3D.new()
			b.position = Vector3(x, 0, -z - depth * 0.5)
			seg.add_child(b)
			var color: Color = concrete[rng.randi_range(0, concrete.size() - 1)]
			b.add_child(LowPoly.box(Vector3(w, h, depth), Palette.mat(color), Vector3(0, h * 0.5, 0)))
			# Pasy okien od strony drogi.
			var floors := floori(h / 3.2)
			for f in floors:
				if rng.randf() < 0.85:
					b.add_child(LowPoly.box(Vector3(0.1, 1.1, depth * 0.8), window_mat, Vector3(-side * (w * 0.5 + 0.02), 1.8 + f * 3.2, 0)))
			# Wyszczerbiony dach.
			if rng.randf() < 0.6:
				b.add_child(LowPoly.box(Vector3(w * 0.6, 2.0, depth * 0.5), Palette.mat(color.darkened(0.1)), Vector3(rng.randf_range(-1.0, 1.0), h + 0.5, rng.randf_range(-2.0, 2.0)), Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.4, 0.4))))
			z += depth + rng.randf_range(0.5, 4.0)
		# Gruz przy chodniku.
		for j in rng.randi_range(2, 5):
			var s := rng.randf_range(0.4, 1.4)
			seg.add_child(LowPoly.mesh_instance(LowPoly.rock_mesh(rng.randi_range(0, 11), 0.35), rubble,
				Vector3(side * rng.randf_range(7.0, 9.5), s * 0.2, -rng.randf_range(0.0, L)), Vector3(s, s * 0.5, s), Vector3(0, rng.randf_range(0, TAU), 0)))
	# Latarnia (prawa strona) i czasem billboard (lewa).
	var pole_mat := Palette.mat(Color("4b4744"), 0.6, 0.5)
	var lamp := Node3D.new()
	lamp.position = Vector3(8.4, 0, -rng.randf_range(2.0, 8.0))
	lamp.rotation = Vector3(0, 0, rng.randf_range(-0.12, 0.05))
	lamp.add_child(LowPoly.cylinder(0.1, 7.0, pole_mat, Vector3(0, 3.5, 0), Vector3.ZERO, 6))
	lamp.add_child(LowPoly.box(Vector3(1.6, 0.12, 0.2), pole_mat, Vector3(-0.7, 7.0, 0)))
	seg.add_child(lamp)
	if rng.randf() < 0.45:
		var bb := Node3D.new()
		bb.position = Vector3(-10.5, 0, -rng.randf_range(5.0, L - 5.0))
		bb.rotation = Vector3(0, 0.35, 0)
		bb.add_child(LowPoly.cylinder(0.12, 6.0, pole_mat, Vector3(-1.5, 3.0, 0), Vector3.ZERO, 6))
		bb.add_child(LowPoly.cylinder(0.12, 6.0, pole_mat, Vector3(1.5, 3.0, 0), Vector3.ZERO, 6))
		var faded: Array[Color] = [Color("b85d3f"), Color("4f7c7a"), Color("c8a04a")]
		bb.add_child(LowPoly.box(Vector3(5.0, 2.6, 0.15), Palette.mat(faded[rng.randi_range(0, 2)], 0.9), Vector3(0, 6.2, 0), Vector3(0, 0, rng.randf_range(-0.08, 0.08))))
		seg.add_child(bb)
	if rng.randf() < 0.5:
		var car := WreckFactory.make(rng.randi_range(0, 1))
		car.position = Vector3((-1.0 if rng.randf() < 0.5 else 1.0) * 9.2, 0.0, -rng.randf_range(4.0, L - 4.0))
		car.rotation.y = rng.randf_range(0.6, 1.2)
		seg.add_child(car)


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
		if item.is_pickup():
			_animate_pickup(node, item, base, delta)
		else:
			_animate_wreck(node, item, base, delta)
	for id in _item_nodes.keys():
		if not seen.has(id):
			_item_nodes[id].queue_free()
			_item_nodes.erase(id)
			_hit_anim.erase(id)
			_pickup_anim.erase(id)


func _animate_pickup(node: Node3D, item: TrackItem, base: Vector3, delta: float) -> void:
	_animate_scrap(node, item, base, delta)


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
		TrackItem.Kind.FUEL:
			return WreckFactory.make_fuel()
		TrackItem.Kind.CRATE:
			return WreckFactory.make_crate()
		_:
			return WreckFactory.make_scrap(false)
