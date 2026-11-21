class_name WreckFactory
extends RefCounted
## Modele przeszkód i złomu z prymitywów (spójna paleta). Wymiary wraków odpowiadają
## strefie kolizji z RunSimulation (ok. 2,6 m szerokości, 3,2 m długości).


static func make(variant: int) -> Node3D:
	# Najpierw modele Kenney (CC0); bez assetów – prymitywy poniżej.
	var kenney := KenneyModels.wreck(variant)
	if kenney != null:
		return kenney
	match posmod(variant, 4):
		0:
			return _car_wreck(false)
		1:
			return _car_wreck(true)
		2:
			return _barrel_pile()
		_:
			return _barrier()


static func _car_wreck(flipped: bool) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	root.add_child(body)
	var paints: Array[Color] = [Palette.PAINT_TEAL, Palette.PAINT_RED, Palette.PAINT_MUSTARD, Palette.RUST_LIGHT]
	var paint: Color = paints[randi() % paints.size()]
	var shell := Palette.mat(paint, 0.85, 0.2)
	var rust := Palette.mat(Palette.RUST, 0.95, 0.1)
	body.add_child(LowPoly.box(Vector3(2.2, 0.7, 3.4), shell, Vector3(0, 0.6, 0)))
	body.add_child(LowPoly.box(Vector3(1.9, 0.55, 1.7), rust, Vector3(0, 1.2, 0.25), Vector3(0.05, 0, 0.04)))
	body.add_child(LowPoly.box(Vector3(2.25, 0.12, 0.5), Palette.mat(Palette.METAL_DARK, 0.6, 0.5), Vector3(0, 0.45, -1.75)))
	var tire := Palette.mat(Palette.TIRE)
	for w in [Vector3(-1.05, 0.35, -1.1), Vector3(1.05, 0.35, 1.15)]:
		body.add_child(LowPoly.cylinder(0.36, 0.28, tire, w, Vector3(0, 0, PI * 0.5), 8))
	if flipped:
		body.rotation = Vector3(0, 0, PI)
		body.position = Vector3(0, 1.55, 0)
	else:
		body.rotation = Vector3(0.0, randf_range(-0.25, 0.25), randf_range(-0.08, 0.08))
	return root


static func _barrel_pile() -> Node3D:
	var root := Node3D.new()
	var colors := [Palette.RUST, Palette.PAINT_TEAL, Palette.PAINT_MUSTARD, Palette.PAINT_RED]
	var spots := [Vector3(-0.7, 0.55, -0.6), Vector3(0.65, 0.55, -0.5), Vector3(0.0, 0.55, 0.6), Vector3(-0.1, 1.6, -0.1)]
	for i in spots.size():
		root.add_child(LowPoly.cylinder(0.42, 1.1, Palette.mat(colors[i % 4], 0.8, 0.35), spots[i], Vector3(0, randf_range(0, TAU), randf_range(-0.1, 0.1)), 10))
	root.add_child(LowPoly.box(Vector3(2.4, 0.12, 0.35), Palette.mat(Color("6b5640")), Vector3(0, 0.25, 1.3), Vector3(0, 0.3, 0.1)))
	return root


static func _barrier() -> Node3D:
	var root := Node3D.new()
	var concrete := Palette.mat(Color("9c9184"))
	root.add_child(LowPoly.box(Vector3(2.5, 0.9, 0.7), concrete, Vector3(0, 0.45, 0), Vector3(0, 0.08, 0)))
	root.add_child(LowPoly.box(Vector3(1.6, 0.45, 0.8), concrete, Vector3(0.1, 1.1, 0.0), Vector3(0, -0.1, 0.12)))
	var steel := Palette.mat(Palette.RUST_LIGHT, 0.7, 0.6)
	for i in 4:
		root.add_child(LowPoly.tube(Vector3(-0.9 + i * 0.6, 0.9, 0.0), Vector3(-1.0 + i * 0.65, 2.0, randf_range(-0.4, 0.4)), 0.04, steel))
	root.add_child(LowPoly.box(Vector3(2.4, 0.6, 0.6), Palette.mat(Palette.METAL_DARK), Vector3(0, 0.3, 1.2), Vector3(0, -0.15, 0)))
	return root


## Kanister paliwa (etap 3): czerwony, z poświatą – inny kolor niż złom.
static func make_fuel() -> Node3D:
	var root := Node3D.new()
	var body := Palette.mat(Color("c8321e"), 0.5, 0.2)
	var glow := Palette.glow(Color("ff6a2a"), 2.0)
	root.add_child(LowPoly.box(Vector3(0.55, 0.75, 0.32), body, Vector3(0, 0.0, 0)))
	root.add_child(LowPoly.box(Vector3(0.3, 0.1, 0.12), glow, Vector3(0.0, 0.43, 0)))
	root.add_child(LowPoly.cylinder(0.06, 0.18, Palette.mat(Palette.METAL, 0.4, 0.7), Vector3(0.2, 0.45, 0), Vector3(0, 0, -0.5), 6))
	root.add_child(LowPoly.box(Vector3(0.57, 0.08, 0.34), glow, Vector3(0, -0.1, 0)))
	return root


## Złom: świecąca zębatka (mały) albo skrzynia z wiązką światła (duży, wart 5).
static func make_scrap(big: bool) -> Node3D:
	var kenney := KenneyModels.scrap(big)
	if kenney != null:
		if big:
			kenney.add_child(_beam(Palette.SCRAP_BIG_GLOW))
		return kenney
	var root := Node3D.new()
	var color := Palette.SCRAP_BIG_GLOW if big else Palette.SCRAP_GLOW
	var glow := Palette.glow(color, 3.0 if big else 2.2)
	var size := 1.6 if big else 1.0
	var gear := Node3D.new()
	gear.rotation = Vector3(PI * 0.5, 0, 0)
	gear.add_child(LowPoly.cylinder(0.34 * size, 0.16 * size, glow, Vector3.ZERO, Vector3.ZERO, 12))
	for i in 8:
		var a := TAU * i / 8.0
		gear.add_child(LowPoly.box(Vector3(0.14, 0.16, 0.16) * size, glow, Vector3(cos(a), 0, sin(a)) * 0.4 * size, Vector3(0, -a, 0)))
	root.add_child(gear)
	if big:
		root.add_child(_beam(color))
	return root


## Świetlna kolumna nad dużym złomem – widać go z daleka.
static func _beam(color: Color) -> MeshInstance3D:
	var beam_mat := Palette.translucent(Color(color, 0.25))
	return LowPoly.cylinder(0.25, 9.0, beam_mat, Vector3(0, 4.0, 0), Vector3.ZERO, 8)
