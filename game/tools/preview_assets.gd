extends Node3D
## Podgląd modeli Kenney (KenneyModels) w świetle i mgle jak w wyprawie: droga z wrakami,
## złomem, rekwizytami i ścianami kanionu, zestawienia wariantów oraz części buggy.
##   godot --path game res://tools/preview_assets.tscn                        (1–7 / LB, RB = widoki, Esc = wyjście)
##   godot --path game res://tools/preview_assets.tscn -- --screenshots=KAT    (zapisuje preview_*.png i kończy)
## Scena tylko do oglądania modeli – gra z niej nie korzysta.

const LANE_X := [-3.6, 0.0, 3.6]
const ROAD_HALF_WIDTH := 6.2
## Widoki: pozycja kamery, punkt, na który patrzy, FOV.
const VIEWS := [
	["droga", Vector3(0.0, 5.2, 9.0), Vector3(0.0, 0.6, -16.0), 62.0],
	["droga_daleko", Vector3(-2.0, 4.0, -40.0), Vector3(0.0, 2.0, -110.0), 62.0],
	["wraki", Vector3(300.0, 8.5, 14.5), Vector3(300.0, 0.3, -0.5), 52.0],
	["wraki_bok", Vector3(316.0, 3.2, 3.0), Vector3(300.0, 0.6, -1.0), 50.0],
	["pobocze", Vector3(600.0, 7.5, 14.0), Vector3(600.0, 0.6, -0.5), 54.0],
	["buggy", Vector3(903.5, 3.4, 6.2), Vector3(901.2, 1.0, 0.0), 46.0],
	["kierowca", Vector3(903.4, 2.3, -3.2), Vector3(901.6, 1.4, 0.2), 40.0],
]

@onready var camera: Camera3D = $Camera
@onready var sun: DirectionalLight3D = $Sun
@onready var info: Label = $Overlay/Info

var _view := 0


func _ready() -> void:
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.35, -0.75, -0.55), Vector3.UP)
	_build_ground()
	_build_road_stage(Vector3.ZERO)
	_build_wreck_stage(Vector3(300.0, 0.0, 0.0))
	_build_prop_stage(Vector3(600.0, 0.0, 0.0))
	_build_buggy_stage(Vector3(900.0, 0.0, 0.0))
	_set_view(0)
	if not KenneyModels.is_available():
		info.text = "Brak assetów Kenney w res://assets/kenney – uruchom import (godot --headless --path game --import)."
	var shots := LaunchOptions.parse(OS.get_cmdline_user_args()).screenshot_dir
	if shots != "":
		_take_screenshots(shots)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		get_tree().quit()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k >= KEY_1 and k < KEY_1 + VIEWS.size():
			_set_view(k - KEY_1)
	elif event is InputEventJoypadButton and event.pressed:
		var b := (event as InputEventJoypadButton).button_index
		if b == JOY_BUTTON_RIGHT_SHOULDER:
			_set_view((_view + 1) % VIEWS.size())
		elif b == JOY_BUTTON_LEFT_SHOULDER:
			_set_view(posmod(_view - 1, VIEWS.size()))


func _set_view(index: int) -> void:
	_view = index
	var v: Array = VIEWS[index]
	camera.fov = float(v[3])
	camera.look_at_from_position(v[1], v[2], Vector3.UP)
	info.text = "%d/%d  %s   (1–%d / LB, RB: widok, Esc: wyjście)" % [index + 1, VIEWS.size(), v[0], VIEWS.size()]


func _take_screenshots(dir: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("Podgląd: tryb headless – brak zrzutów.")
		get_tree().quit()
		return
	var win := get_window()
	win.mode = Window.MODE_WINDOWED
	win.size = Vector2i(1920, 1080)
	info.visible = false
	for i in VIEWS.size():
		_set_view(i)
		for f in 6:
			await get_tree().process_frame
		await Screenshot.capture(self, "%s/preview_%s.png" % [dir, VIEWS[i][0]])
	get_tree().quit()


# --- Scena ------------------------------------------------------------------------

func _build_ground() -> void:
	var sand := PlaneMesh.new()
	sand.size = Vector2(2400.0, 1200.0)
	add_child(LowPoly.mesh_instance(sand, Palette.mat(Palette.SAND), Vector3(450.0, 0.0, -300.0)))


func _build_road_stage(origin: Vector3) -> void:
	var stage := _stage(origin)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var length := 320.0
	var road := PlaneMesh.new()
	road.size = Vector2(ROAD_HALF_WIDTH * 2.0, length)
	stage.add_child(LowPoly.mesh_instance(road, Palette.mat(Palette.ROAD, 0.97), Vector3(0.0, 0.02, -length * 0.5 + 30.0)))
	var paint := Palette.mat(Palette.LANE_PAINT, 0.9)
	for lane_line: float in [-1.8, 1.8]:
		var z := 28.0
		while z > -length + 30.0:
			stage.add_child(LowPoly.box(Vector3(0.2, 0.02, 3.0), paint, Vector3(lane_line, 0.04, z)))
			z -= 8.0
	for edge: float in [-ROAD_HALF_WIDTH + 0.35, ROAD_HALF_WIDTH - 0.35]:
		stage.add_child(LowPoly.box(Vector3(0.16, 0.02, length), paint, Vector3(edge, 0.04, -length * 0.5 + 30.0)))
	# Ściany kanionu – tak, jak mógłby je układać TrackView (patrz raport integracji).
	for side: float in [-1.0, 1.0]:
		var z := -30.0
		while z < length - 30.0:
			var piece := KenneyModels.canyon_wall_piece(rng)
			if piece == null:
				break
			var piece_len: float = piece.get_meta("length_m", 12.0)
			piece.position = Vector3(side * rng.randf_range(10.5, 11.5), 0.0, -z - piece_len * 0.5)
			piece.rotation.y = 0.0 if side < 0.0 else PI
			stage.add_child(piece)
			z += piece_len * rng.randf_range(0.82, 0.95)
	# Pobocze.
	var pz := -4.0
	while pz > -length + 40.0:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var prop := KenneyModels.roadside_prop(rng)
		if prop != null:
			prop.position = Vector3(side * rng.randf_range(7.0, 9.8), 0.0, pz)
			stage.add_child(prop)
		pz -= rng.randf_range(7.0, 14.0)
	# Wraki i złom na pasach (jak przedmioty z RunSimulation).
	var wrecks := [[-20.0, 0, 0], [-31.0, 2, 1], [-44.0, 1, 2], [-58.0, 0, 3], [-72.0, 2, 0], [-86.0, 1, 1], [-100.0, 0, 2], [-114.0, 2, 3], [-130.0, 1, 0], [-146.0, 0, 1]]
	for w: Array in wrecks:
		var node := KenneyModels.wreck(int(w[2]), rng)
		if node != null:
			node.position = Vector3(LANE_X[int(w[1])], 0.0, float(w[0]))
			stage.add_child(node)
	var scraps := [[-13.0, 1, false], [-26.0, 1, true], [-38.0, 2, false], [-51.0, 0, false], [-65.0, 1, true], [-79.0, 0, false], [-93.0, 2, false]]
	for s: Array in scraps:
		var node := _scrap(bool(s[2]), rng)
		if node != null:
			node.position = Vector3(LANE_X[int(s[1])], 0.9, float(s[0]))
			node.rotation.y = rng.randf_range(-0.6, 0.6)
			stage.add_child(node)
	# Buggy gracza (obecny widok z prymitywów) w punkcie z = 0.
	var buggy: Node3D = load("res://scenes/run/buggy.tscn").instantiate()
	stage.add_child(buggy)


func _build_wreck_stage(origin: Vector3) -> void:
	# 4 warianty x 4 losowania; szare prostokąty = strefa kolizji z RunSimulation (2,6 x 3,2 m).
	var stage := _stage(origin)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var zone := StandardMaterial3D.new()
	zone.albedo_color = Color(0.1, 0.1, 0.1, 0.35)
	zone.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for variant in KenneyModels.WRECK_VARIANTS:
		for k in 4:
			var pos := Vector3((k - 1.5) * 4.6, 0.0, (variant - 1.5) * 4.6)
			stage.add_child(LowPoly.box(Vector3(2.6, 0.02, 3.2), zone, pos + Vector3(0.0, 0.03, 0.0)))
			var node := KenneyModels.wreck(variant, rng)
			if node != null:
				node.position = pos
				stage.add_child(node)
	_label(stage, "Wraki: rzędy = warianty 0–3 (od tyłu), prostokąty = kolizja 2,6 x 3,2 m", Vector3(0.0, 0.1, 9.0))


func _build_prop_stage(origin: Vector3) -> void:
	var stage := _stage(origin)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 12:
		var prop := KenneyModels.roadside_prop(rng)
		if prop != null:
			prop.position = Vector3((i % 6 - 2.5) * 4.4, 0.0, (i / 6) * 5.5 - 6.0)
			stage.add_child(prop)
	for i in 6:
		var big := i >= 3
		var node := _scrap(big, rng)
		if node != null:
			node.position = Vector3((i - 2.5) * 2.6, 0.9, 5.0)
			node.rotation.y = -0.5 + i * 0.25
			stage.add_child(node)


func _build_buggy_stage(origin: Vector3) -> void:
	# Lewo: obecny BuggyView. Prawo: te same wymiary z częściami Kenney (koła, kierowca, pancerz).
	var stage := _stage(origin)
	var buggy: Node3D = load("res://scenes/run/buggy.tscn").instantiate()
	buggy.position = Vector3(-1.6, 0.0, 0.0)
	stage.add_child(buggy)
	var mock := Node3D.new()
	mock.position = Vector3(1.6, 0.0, 0.0)
	stage.add_child(mock)
	var frame := Palette.mat(Palette.BUGGY_FRAME, 0.5, 0.6)
	mock.add_child(LowPoly.cylinder(0.07, 1.9, frame, Vector3(0, 0.62, 0.55), Vector3(0, 0, PI * 0.5), 8))
	mock.add_child(LowPoly.box(Vector3(1.3, 0.1, 1.8), frame, Vector3(0, 0.72, -0.15)))
	mock.add_child(LowPoly.box(Vector3(0.9, 0.08, 1.2), frame, Vector3(0, 0.12, -1.55), Vector3(-0.15, 0, 0)))
	mock.add_child(LowPoly.box(Vector3(0.55, 0.12, 0.55), Palette.mat(Color("3b2f27")), Vector3(0, 1.05, 0.35)))
	for c: Array in [[Vector3(-0.62, 0.75, 0.75), Vector3(-0.5, 2.05, 0.55)], [Vector3(0.62, 0.75, 0.75), Vector3(0.5, 2.05, 0.55)],
			[Vector3(-0.5, 2.05, 0.55), Vector3(0.5, 2.05, 0.55)], [Vector3(-0.62, 0.75, -0.95), Vector3(-0.5, 1.75, -0.35)],
			[Vector3(0.62, 0.75, -0.95), Vector3(0.5, 1.75, -0.35)], [Vector3(-0.5, 1.75, -0.35), Vector3(-0.5, 2.05, 0.55)],
			[Vector3(0.5, 1.75, -0.35), Vector3(0.5, 2.05, 0.55)], [Vector3(-0.5, 1.75, -0.35), Vector3(0.5, 1.75, -0.35)]]:
		mock.add_child(LowPoly.tube(c[0], c[1], 0.045, frame))
	for side: float in [-1.0, 1.0]:
		var wheel := KenneyModels.buggy_wheel(side)
		if wheel != null:
			wheel.position = Vector3(side * 0.98, KenneyModels.WHEEL_DIAMETER_M * 0.5, 0.55)
			mock.add_child(wheel)
		var plate := KenneyModels.buggy_plate()
		if plate != null:
			plate.position = Vector3(side * 0.68, 1.0, -0.15)
			plate.rotation.y = 0.0 if side > 0.0 else PI
			mock.add_child(plate)
	var rider := KenneyModels.buggy_rider()
	if rider != null:
		rider.position = Vector3(0.0, 1.06, 0.22)
		mock.add_child(rider)
	_label(stage, "BuggyView (prymitywy)  |  części Kenney", Vector3(0.0, 0.1, 2.6))


## Złom jak w grze: zębatka z KenneyModels + słup światła nad dużym (w grze dokłada go
## WreckFactory).
func _scrap(big: bool, rng: RandomNumberGenerator) -> Node3D:
	var node := KenneyModels.scrap(big, rng)
	if node != null and big:
		var beam_mat := StandardMaterial3D.new()
		beam_mat.albedo_color = Color(Palette.SCRAP_BIG_GLOW, 0.25)
		beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		node.add_child(LowPoly.cylinder(0.25, 9.0, beam_mat, Vector3(0, 4.0, 0), Vector3.ZERO, 8))
	return node


func _stage(origin: Vector3) -> Node3D:
	var stage := Node3D.new()
	stage.position = origin
	add_child(stage)
	return stage


func _label(parent: Node3D, text: String, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = 0.01
	l.outline_size = 10
	l.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	l.position = pos
	l.modulate = Palette.UI_TEXT
	parent.add_child(l)
