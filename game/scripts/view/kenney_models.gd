class_name KenneyModels
extends RefCounted
## Modele z darmowych paczek Kenney (CC0, game/assets/kenney) przefarbowane na paletę
## pustkowia: wraki, złom, rekwizyty przy drodze, ściany kanionu i części buggy.
## Każda funkcja zwraca gotowy Node3D albo null, gdy brakuje assetu – wtedy wołający
## zostaje przy prymitywach (WreckFactory / TrackView / BuggyView).
##
## Konwencje: metry, +Y w górę, droga biegnie wzdłuż -Z (gracz jedzie w stronę -Z).
## Paczki Kenney mają przód modeli w +Z (glTF), więc obracamy je tutaj, nie u wołającego.
## Materiały są wspólne (cache): kolormapa paczki jako tekstura albedo, odbarwiona
## i przyciemniona (Image.adjust_bcs) oraz przemnożona przez odcień z palety.

enum CarState { TILTED, OVERTURNED, BURIED, SKEWED }

const ROOT_DIR := "res://assets/kenney"
const CAR_DIR := ROOT_DIR + "/car-kit"
const SURVIVAL_DIR := ROOT_DIR + "/survival-kit"
const CAVE_DIR := ROOT_DIR + "/cave-kit"
const FACTORY_DIR := ROOT_DIR + "/factory-kit"

## Liczba różnych wariantów wraku (wariant z TrackItem bierzemy modulo).
const WRECK_VARIANTS := 4
## Obrys wraku: strefa kolizji w RunSimulation to 2,6 x 3,2 m.
const WRECK_WIDTH_M := 2.4
const WRECK_MAX_WIDTH_M := 2.6
const WRECK_MAX_LENGTH_M := 3.4
## Zabawkowe auta Kenney są wąskie – poszerzamy je w bok najwyżej o tyle.
const WRECK_MAX_WIDEN := 1.22
const SCRAP_SIZE_M := 0.8
const SCRAP_BIG_SIZE_M := 1.3
## Grubość zębatki względem modelu (cienka zębatka „znika”, gdy obraca się bokiem).
const SCRAP_THICKNESS := 1.7
const WHEEL_DIAMETER_M := 1.24
const WHEEL_WIDTH_M := 0.5
const RIDER_HEIGHT_M := 0.95
const PLATE_LENGTH_M := 1.5
const PLATE_HEIGHT_M := 0.55
## Paczka Survival jest w skali „zabawki” (beczka 0,34 m) – mnożnik do metrów.
const SURVIVAL_SCALE := 3.2
const WALL_MIN_HEIGHT_M := 12.0
const WALL_MAX_HEIGHT_M := 20.0
## Ile ściana (z kamieniami u podstawy) może wystawać przed lico (x > 0).
const WALL_MAX_OVERHANG_M := 1.5

## Auta o długości do ~3,1 m (dłuższe po zmieszczeniu w 3,4 m byłyby za wąskie).
const CARS := ["sedan", "sedan-sports", "suv", "van", "truck", "truck-flat", "taxi", "police", "hatchback-sports"]
const COGS := ["cog-a", "cog-b", "cog-c", "cog-d", "cog-e"]
const SAND_ROCKS := ["rock-sand-a", "rock-sand-b", "rock-sand-c"]
const PANELS := ["metal-panel", "metal-panel-screws", "metal-panel-narrow"]
## Płyty ścian z Cave Kit; detail-a (żebrowana) dwa razy, bo wygląda najlepiej.
const WALLS := ["template-wall", "template-wall-detail-a", "template-wall-detail-a", "template-wall-half"]

static var _scenes: Dictionary = {}
static var _materials: Dictionary = {}
static var _textures: Dictionary = {}


## Czy paczki są w projekcie (sprawdza po jednym modelu z każdej).
static func is_available() -> bool:
	return _scene(CAR_DIR + "/sedan.glb") != null \
		and _scene(SURVIVAL_DIR + "/barrel.glb") != null \
		and _scene(CAVE_DIR + "/template-wall.glb") != null \
		and _scene(FACTORY_DIR + "/cog-a.glb") != null


# --- Wraki ----------------------------------------------------------------------

## Wrak na pas: zardzewiałe/spalone auto (bez kół, przechylone, na dachu, zakopane,
## w poprzek) albo stos beczek. Ok. 2,4 m szerokości (obrys zawsze w 2,6 x 3,4 m),
## początek układu na ziemi w środku obiektu, droga wzdłuż -Z. Wariant (modulo
## WRECK_VARIANTS) wybiera rodzaj, rng – model i szczegóły (bez rng: losowo).
static func wreck(variant: int, rng: RandomNumberGenerator = null) -> Node3D:
	var r := _rng_or_new(rng)
	match posmod(variant, WRECK_VARIANTS):
		0:
			return _car_wreck(r, CarState.TILTED, "rust" if r.randf() < 0.65 else "faded")
		1:
			return _car_wreck(r, CarState.OVERTURNED, "burnt" if r.randf() < 0.6 else "rust")
		2:
			return _barrel_pile(r)
		_:
			var state := CarState.BURIED if r.randf() < 0.5 else CarState.SKEWED
			return _car_wreck(r, state, "burnt" if r.randf() < 0.5 else "rust")


static func _car_wreck(rng: RandomNumberGenerator, state: CarState, style: String) -> Node3D:
	var model: String = CARS[rng.randi_range(0, CARS.size() - 1)]
	var car := _instance(CAR_DIR + "/" + model + ".glb", material(CAR_DIR, style))
	if car == null:
		return null
	var wheels: Array[Node3D] = []
	for child in car.get_children():
		if child is Node3D and String(child.name).begins_with("wheel"):
			wheels.append(child as Node3D)
	# Skala: szerokość ~2,4 m, długość do 3,4 m; auto poszerzamy w bok (lokalne X).
	var raw := bounds_of(car)
	var s := minf(WRECK_WIDTH_M / raw.size.x, WRECK_MAX_LENGTH_M / raw.size.z)
	var widen := clampf(WRECK_WIDTH_M / (raw.size.x * s), 1.0, WRECK_MAX_WIDEN)
	car.scale = Vector3(s * widen, s, s)
	var body := Node3D.new()
	body.name = "Body"
	body.add_child(car)
	var root := Node3D.new()
	root.name = "KenneyWreck"
	root.add_child(body)
	# Połowa aut stoi przodem do gracza, połowa tyłem.
	var yaw := rng.randf_range(-0.14, 0.14) + (PI if rng.randf() < 0.5 else 0.0)
	var sink := 0.06
	match state:
		CarState.TILTED:
			# Brak jednego koła (czasem dwóch): karoseria opada na ten róg.
			var lost: Node3D = wheels[rng.randi_range(0, wheels.size() - 1)] if not wheels.is_empty() else null
			var roll := 0.0
			var pitch := 0.0
			if lost != null:
				lost.visible = false
				roll = -signf(lost.position.x) * rng.randf_range(0.1, 0.16)
				pitch = signf(lost.position.z) * rng.randf_range(0.06, 0.11)
				if rng.randf() < 0.35:
					for w in wheels:
						if w != lost and signf(w.position.z) == signf(lost.position.z):
							w.visible = false
							roll *= 0.4
							pitch *= 1.7
			body.rotation = Vector3(pitch, yaw, roll)
			sink = 0.14
		CarState.OVERTURNED:
			for w in wheels:
				if rng.randf() < 0.3:
					w.visible = false
			body.rotation = Vector3(rng.randf_range(-0.05, 0.05), yaw, PI + rng.randf_range(-0.09, 0.09))
			sink = 0.08
		CarState.BURIED:
			# Przód zakopany w piasku (przód modelu = +Z).
			for w in wheels:
				if w.position.z > 0.0 or rng.randf() < 0.3:
					w.visible = false
			body.rotation = Vector3(rng.randf_range(0.2, 0.3), yaw, rng.randf_range(-0.08, 0.08))
			sink = 0.38
		CarState.SKEWED:
			# Na felgach, w poprzek drogi (dopasowanie do obrysu zmniejszy skalę).
			for w in wheels:
				w.visible = false
			var skew := rng.randf_range(0.45, 0.75) * (1.0 if rng.randf() < 0.5 else -1.0)
			body.rotation = Vector3(0.0, yaw + skew, rng.randf_range(-0.05, 0.05))
			sink = 0.1
	_settle(root, body, WRECK_MAX_WIDTH_M, WRECK_MAX_LENGTH_M, sink)
	return root


static func _barrel_pile(rng: RandomNumberGenerator) -> Node3D:
	var pile := Node3D.new()
	pile.name = "Pile"
	var root := Node3D.new()
	root.name = "KenneyWreck"
	root.add_child(pile)
	var rust := material(SURVIVAL_DIR, "rust")
	var dust := material(SURVIVAL_DIR, "dust")
	var h := 0.34 * SURVIVAL_SCALE
	var r := 0.12 * SURVIVAL_SCALE
	# Rząd trzech beczek, za nim dwie, jedna na górze i jedna przewrócona z przodu.
	var spots: Array[Vector3] = [
		Vector3(-0.86, 0.0, -0.45), Vector3(0.0, 0.0, -0.5), Vector3(0.86, 0.0, -0.42),
		Vector3(-0.45, 0.0, 0.3), Vector3(0.45, 0.0, 0.32),
	]
	for p: Vector3 in spots:
		if rng.randf() < 0.15 and pile.get_child_count() >= 3:
			continue  # dziura w stosie
		var b := _instance(SURVIVAL_DIR + "/barrel.glb", rust if rng.randf() < 0.6 else dust)
		if b == null:
			root.free()
			return null
		b.scale = Vector3.ONE * SURVIVAL_SCALE
		b.position = p + Vector3(rng.randf_range(-0.06, 0.06), 0.0, rng.randf_range(-0.06, 0.06))
		b.rotation = Vector3(rng.randf_range(-0.04, 0.04), rng.randf_range(0.0, TAU), rng.randf_range(-0.04, 0.04))
		pile.add_child(b)
	var top := _instance(SURVIVAL_DIR + ("/barrel-open.glb" if rng.randf() < 0.5 else "/barrel.glb"), rust)
	if top != null:
		top.scale = Vector3.ONE * SURVIVAL_SCALE
		top.position = Vector3(rng.randf_range(-0.45, 0.45), h, -0.46)
		top.rotation = Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(0.0, TAU), rng.randf_range(-0.12, 0.12))
		pile.add_child(top)
	var lying := _instance(SURVIVAL_DIR + "/barrel.glb", dust if rng.randf() < 0.5 else rust)
	if lying != null:
		# Leży na boku (oś wzdłuż X), toczy się w stronę drogi.
		lying.scale = Vector3.ONE * SURVIVAL_SCALE
		lying.rotation = Vector3(0.0, rng.randf_range(-0.35, 0.35), PI * 0.5)
		lying.position = Vector3(rng.randf_range(0.0, 0.9), r, 1.15)
		pile.add_child(lying)
	if rng.randf() < 0.5:
		var panel := _instance(SURVIVAL_DIR + "/metal-panel-screws.glb", material(SURVIVAL_DIR, "rust"))
		if panel != null:
			panel.scale = Vector3.ONE * SURVIVAL_SCALE
			panel.rotation = Vector3(-0.35, rng.randf_range(-0.4, 0.4), 0.0)
			panel.position = Vector3(rng.randf_range(-0.8, -0.3), 0.0, 0.95)
			pile.add_child(panel)
	_settle(root, pile, WRECK_MAX_WIDTH_M, WRECK_MAX_LENGTH_M, 0.02)
	return root


# --- Złom -------------------------------------------------------------------------

## Świecąca zębatka z Factory Kit (ok. 0,8 m, duża 1,3 m), stoi pionowo przodem do
## kamery. Początek układu w środku zębatki (TrackView unosi ją nad ziemią i obraca
## wokół Y). Bez słupa światła – dokłada go wołający (WreckFactory._beam).
static func scrap(big: bool, rng: RandomNumberGenerator = null) -> Node3D:
	var r := _rng_or_new(rng)
	var cog := _instance(FACTORY_DIR + "/" + str(COGS[r.randi_range(0, COGS.size() - 1)]) + ".glb", _scrap_material(big))
	if cog == null:
		return null
	var raw := bounds_of(cog)
	var size := SCRAP_BIG_SIZE_M if big else SCRAP_SIZE_M
	var s := size / maxf(raw.size.x, raw.size.z)
	cog.position = -raw.get_center()
	var pivot := Node3D.new()
	pivot.name = "Cog"
	pivot.add_child(cog)
	# Oś zębatki (Y modelu) -> Z: lico patrzy na kamerę.
	pivot.scale = Vector3(s, s * SCRAP_THICKNESS, s)
	pivot.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	var root := Node3D.new()
	root.name = "KenneyScrap"
	root.add_child(pivot)
	return root


# --- Pobocze --------------------------------------------------------------------

## Rekwizyt na pobocze (beczki, skały, drogowskaz, blachy, blaszana buda, namiot)
## w metrach, początek układu na ziemi w środku. Zajmuje najwyżej ok. 3 m w poprzek
## drogi (X) – mieści się między krawędzią jezdni a ścianą kanionu.
static func roadside_prop(rng: RandomNumberGenerator) -> Node3D:
	var pick := rng.randf()
	var content: Node3D = null
	if pick < 0.22:
		content = _prop_barrels(rng)
	elif pick < 0.44:
		content = _prop_rock(rng)
	elif pick < 0.58:
		content = _prop_signpost(rng)
	elif pick < 0.72:
		content = _prop_panels(rng)
	elif pick < 0.86:
		content = _prop_shack(rng)
	else:
		content = _prop_tent(rng)
	if content == null:
		return null
	var root := Node3D.new()
	root.name = "KenneyProp"
	root.add_child(content)
	_settle(root, content, 3.2, 0.0, 0.02)
	return root


static func _prop_barrels(rng: RandomNumberGenerator) -> Node3D:
	var group := Node3D.new()
	var n := rng.randi_range(1, 3)
	for i in n:
		var b := _instance(SURVIVAL_DIR + ("/barrel-open.glb" if rng.randf() < 0.3 else "/barrel.glb"),
			material(SURVIVAL_DIR, "rust" if rng.randf() < 0.5 else "dust"))
		if b == null:
			group.free()
			return null
		b.scale = Vector3.ONE * SURVIVAL_SCALE
		if rng.randf() < 0.35:
			b.rotation = Vector3(0.0, rng.randf_range(0.0, TAU), PI * 0.5)
			b.position = Vector3(rng.randf_range(-0.3, 0.3), 0.12 * SURVIVAL_SCALE, i * 0.95)
		else:
			b.rotation = Vector3(0.0, rng.randf_range(0.0, TAU), 0.0)
			b.position = Vector3(rng.randf_range(-0.3, 0.3), 0.0, i * 0.85)
		group.add_child(b)
	return group


static func _prop_rock(rng: RandomNumberGenerator) -> Node3D:
	var rock := _instance(SURVIVAL_DIR + "/" + str(SAND_ROCKS[rng.randi_range(0, SAND_ROCKS.size() - 1)]) + ".glb", material(SURVIVAL_DIR, "rock"))
	if rock == null:
		return null
	var s := rng.randf_range(3.0, 4.6)
	rock.scale = Vector3(s, s * rng.randf_range(0.85, 1.3), s)
	rock.rotation.y = rng.randf_range(0.0, TAU)
	var holder := Node3D.new()
	holder.add_child(rock)
	return holder


static func _prop_signpost(rng: RandomNumberGenerator) -> Node3D:
	var sign_node := _instance(SURVIVAL_DIR + ("/signpost.glb" if rng.randf() < 0.6 else "/signpost-single.glb"), material(SURVIVAL_DIR, "dust"))
	if sign_node == null:
		return null
	sign_node.scale = Vector3.ONE * 5.0
	# Tablica przodem do nadjeżdżającego gracza, krzywo wbita.
	sign_node.rotation = Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.5, 0.5), rng.randf_range(-0.2, 0.2))
	var holder := Node3D.new()
	holder.add_child(sign_node)
	return holder


static func _prop_panels(rng: RandomNumberGenerator) -> Node3D:
	# Prowizoryczny płot z blach wzdłuż drogi; część arkuszy pochylona albo przewrócona.
	var fence := Node3D.new()
	var n := rng.randi_range(2, 4)
	var w := 0.5 * SURVIVAL_SCALE
	for i in n:
		var panel := _instance(SURVIVAL_DIR + "/" + str(PANELS[rng.randi_range(0, PANELS.size() - 1)]) + ".glb",
			material(SURVIVAL_DIR, "rust" if rng.randf() < 0.55 else "dust"))
		if panel == null:
			fence.free()
			return null
		panel.scale = Vector3.ONE * SURVIVAL_SCALE * rng.randf_range(0.95, 1.15)
		var z := (i - (n - 1) * 0.5) * w * 0.92
		if rng.randf() < 0.18:
			panel.rotation = Vector3(-PI * 0.5 + 0.05, PI * 0.5 + rng.randf_range(-0.3, 0.3), 0.0)
			panel.position = Vector3(rng.randf_range(0.2, 0.8), 0.05, z)
		else:
			panel.rotation = Vector3(0.0, PI * 0.5 + rng.randf_range(-0.12, 0.12), rng.randf_range(-0.22, 0.22))
			panel.position = Vector3(rng.randf_range(-0.08, 0.08), 0.0, z)
		fence.add_child(panel)
	return fence


static func _prop_shack(rng: RandomNumberGenerator) -> Node3D:
	# Blaszana buda: rama z dachem + blachy z trzech stron (otwarta w stronę drogi lub tyłem).
	var shack := Node3D.new()
	var frame := _instance(SURVIVAL_DIR + "/structure-metal-roof.glb", material(SURVIVAL_DIR, "dust"))
	if frame == null:
		shack.free()
		return null
	shack.add_child(frame)
	var sides: Array[Vector3] = [Vector3(0.0, 0.0, -0.245), Vector3(-0.245, 0.0, 0.0), Vector3(0.245, 0.0, 0.0), Vector3(0.0, 0.0, 0.245)]
	var open_side := rng.randi_range(0, 3)
	for i in sides.size():
		if i == open_side:
			continue
		var panel := _instance(SURVIVAL_DIR + "/" + str(PANELS[rng.randi_range(0, 1)]) + ".glb",
			material(SURVIVAL_DIR, "rust" if rng.randf() < 0.6 else "dust"))
		if panel == null:
			continue
		panel.position = sides[i]
		panel.rotation = Vector3(0.0, PI * 0.5 if absf(sides[i].x) > 0.0 else 0.0, rng.randf_range(-0.04, 0.04))
		shack.add_child(panel)
	var s := rng.randf_range(4.2, 4.8)
	shack.scale = Vector3(s, s * rng.randf_range(0.95, 1.1), s)
	shack.rotation.y = rng.randf_range(-0.3, 0.3) + (PI * 0.5) * rng.randi_range(0, 3)
	var holder := Node3D.new()
	holder.add_child(shack)
	return holder


static func _prop_tent(rng: RandomNumberGenerator) -> Node3D:
	# tent-canvas ma płótno na jednym skosie – druga kopia obrócona o PI zamyka namiot.
	var mat := material(SURVIVAL_DIR, "canvas")
	var tent := Node3D.new()
	for i in 2:
		var half := _instance(SURVIVAL_DIR + "/tent-canvas.glb", mat)
		if half == null:
			tent.free()
			return null
		half.rotation.y = PI * i
		tent.add_child(half)
	var s := rng.randf_range(4.0, 4.6)
	tent.scale = Vector3.ONE * s
	tent.rotation.y = rng.randf_range(0.0, TAU)
	var holder := Node3D.new()
	holder.add_child(tent)
	return holder


# --- Ściany kanionu -------------------------------------------------------------

## Fragment ściany kanionu (12–20 m) z Modular Cave Kit. Lico zwrócone w +X (stronę
## drogi dla lewej ściany), najbardziej wysunięty punkt w x ≈ 0, ściana sięga w -X.
## Środek długości w z = 0, spód w y = 0. Metadane: "length_m" (zasięg wzdłuż Z
## przy układaniu kolejnych kawałków), "height_m". Prawą ścianę obróć o PI wokół Y.
static func canyon_wall_piece(rng: RandomNumberGenerator) -> Node3D:
	var rock := material(CAVE_DIR, "canyon_" + "abc"[rng.randi_range(0, 2)])
	var model: String = WALLS[rng.randi_range(0, WALLS.size() - 1)]
	var native_length := 2.0 if model == "template-wall-half" else 4.0
	var length := native_length * rng.randf_range(2.8, 3.5)
	var height := rng.randf_range(WALL_MIN_HEIGHT_M, WALL_MAX_HEIGHT_M)
	var terrace := rng.randf() < 0.45 and height < WALL_MAX_HEIGHT_M - 3.0
	if terrace:
		height = minf(height, rng.randf_range(WALL_MIN_HEIGHT_M, 15.0))
	var main := _wall_slab(model, length, height, rng.randf_range(5.5, 7.0), rock)
	if main == null:
		return null
	var root := Node3D.new()
	root.name = "KenneyCanyonWall"
	root.add_child(main)
	var top := height
	if terrace:
		# Wyższy stopień za frontem – kanion wygląda na tarasowy, a nie płaski.
		var back_h := minf(WALL_MAX_HEIGHT_M, height + rng.randf_range(3.0, 6.0))
		var back := _wall_slab(str(WALLS[rng.randi_range(0, 2)]), length * rng.randf_range(0.85, 1.1), back_h, 6.0, rock)
		if back != null:
			back.position = Vector3(-rng.randf_range(4.0, 6.5), 0.0, rng.randf_range(-1.5, 1.5))
			root.add_child(back)
			top = back_h
	# Skalne słupy przy podstawie (do połowy wtopione w ścianę).
	for i in rng.randi_range(0, 2):
		var pillar := _instance(CAVE_DIR + "/template-detail.glb", rock)
		if pillar == null:
			break
		var ps := rng.randf_range(1.3, 2.0)
		pillar.scale = Vector3(ps, ps * rng.randf_range(1.0, 1.5), ps)
		pillar.rotation.y = rng.randf_range(0.0, TAU)
		var holder := Node3D.new()
		holder.add_child(pillar)
		var pb := bounds_of(holder)
		pillar.position = -Vector3(pb.end.x - WALL_MAX_OVERHANG_M * rng.randf_range(0.3, 1.0), pb.position.y, pb.get_center().z)
		holder.position = Vector3(0.0, 0.0, rng.randf_range(-length * 0.4, length * 0.4))
		root.add_child(holder)
	root.set_meta("length_m", length)
	root.set_meta("height_m", top)
	return root


## Płyta ściany: lico modelu (−Z) obrócone w +X, przeskalowana do długości/wysokości/głębokości.
static func _wall_slab(model: String, length: float, height: float, depth: float, mat: Material) -> Node3D:
	var wall := _instance(CAVE_DIR + "/" + model + ".glb", mat)
	if wall == null:
		return null
	var raw := bounds_of(wall)
	wall.scale = Vector3(length / raw.size.x, height / raw.size.y, depth / raw.size.z)
	wall.rotation.y = -PI * 0.5
	var holder := Node3D.new()
	holder.add_child(wall)
	var b := bounds_of(holder)
	wall.position = -Vector3(b.end.x, b.position.y, b.get_center().z)
	return holder


# --- Części buggy ---------------------------------------------------------------

## Koło (wheel-tractor-back): średnica 1,24 m (szerokość 0,5 m), oś wzdłuż X, początek
## układu w środku koła (obracaj węzeł wokół X). Felga na zewnątrz: outer_side = +1
## (prawe koło) / -1. Inna średnica (np. 0,8 m przyczepy) skaluje też szerokość.
static func buggy_wheel(outer_side: float = 1.0, diameter_m: float = WHEEL_DIAMETER_M) -> Node3D:
	var model := _instance(CAR_DIR + "/wheel-tractor-back.glb", material(CAR_DIR, "buggy"))
	if model == null:
		return null
	var raw := bounds_of(model)
	var d := diameter_m / raw.size.y
	model.scale = Vector3(WHEEL_WIDTH_M * diameter_m / WHEEL_DIAMETER_M / raw.size.x, d, d)
	if outer_side < 0.0:
		model.rotation.y = PI
	var root := Node3D.new()
	root.name = "KenneyWheel"
	root.add_child(model)
	model.position = -bounds_of(root).get_center()
	return root


## Kierowca w kasku (postać „character” z gokarta kart-oozi), siedzący, przodem w -Z.
## RIDER_HEIGHT_M od spodu do czubka kasku (duża głowa – styl Kenney); początek
## układu: środek spodu postaci. Model jest jednym meshem (bez animacji nóg).
static func buggy_rider() -> Node3D:
	var kart := _instance(CAR_DIR + "/kart-oozi.glb", material(CAR_DIR, "rider"))
	if kart == null:
		return null
	var character := kart.find_child("character", true, false) as Node3D
	if character == null:
		kart.free()
		return null
	var xf := Transform3D.IDENTITY
	var n: Node = character
	while n != null and n != kart:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	character.get_parent().remove_child(character)
	kart.free()
	character.transform = xf
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.add_child(character)
	var raw := bounds_of(pivot)
	var s := RIDER_HEIGHT_M / raw.size.y
	pivot.scale = Vector3.ONE * s
	pivot.rotation.y = PI
	var root := Node3D.new()
	root.name = "KenneyRider"
	root.add_child(pivot)
	_settle(root, pivot, 0.0, 0.0, 0.0)
	return root


## Płyta pancerza z blach (debris-plate) 1,5 x 0,55 m, pionowa, lico w +X; początek
## układu w środku płyty. Na lewą burtę obróć o PI wokół Y.
static func buggy_plate() -> Node3D:
	var mat := material(CAR_DIR, "buggy")
	var panel := Node3D.new()
	panel.name = "Panel"
	# Dwie zachodzące na siebie blachy + mała łata (modele leżą płasko, grubość w Y).
	var parts := [
		["debris-plate-a", Vector3(0.0, 0.0, -0.36), PLATE_LENGTH_M * 0.55, 0.0],
		["debris-plate-b", Vector3(0.03, 0.02, 0.36), PLATE_LENGTH_M * 0.5, 0.05],
		["debris-plate-small-a", Vector3(0.07, -0.05, 0.02), PLATE_LENGTH_M * 0.22, -0.2],
	]
	for p: Array in parts:
		var plate := _instance(CAR_DIR + "/" + str(p[0]) + ".glb", mat)
		if plate == null:
			panel.free()
			return null
		var raw := bounds_of(plate)
		var along: float = p[2]
		# Lokalnie: X modelu -> wysokość, Y modelu (grubość) -> X płyty, Z -> długość.
		plate.scale = Vector3(PLATE_HEIGHT_M / raw.size.x, 0.6, along / raw.size.z)
		plate.rotation = Vector3(float(p[3]), 0.0, -PI * 0.5)
		plate.position = p[1]
		panel.add_child(plate)
	var root := Node3D.new()
	root.name = "KenneyPlate"
	root.add_child(panel)
	var b := bounds_of(root)
	panel.position -= b.get_center()
	return root


# --- Materiały ------------------------------------------------------------------

## Wspólny materiał paczki w danym stylu: kolormapa jako albedo (odbarwiona) x odcień.
## Style: dust, rust, burnt, faded, buggy, rider, rock, canvas, canyon_a/b/c.
static func material(kit_dir: String, style: String) -> ShaderMaterial:
	var key := kit_dir + "|" + style
	if _materials.has(key):
		return _materials[key]
	var st := _style(style)
	# Modele Kenney są dwustronne (cienkie blachy, płótno namiotu).
	var m := Palette.textured(_texture(kit_dir, st.saturation, st.contrast, st.brightness), st.tint, st.roughness, true)
	m.resource_name = "kenney_%s_%s" % [kit_dir.get_file(), style]
	_materials[key] = m
	return m


class Style:
	var saturation := 1.0
	var contrast := 1.0
	var brightness := 1.0
	var tint := Color.WHITE
	var roughness := 0.9

	func _init(p_saturation: float, p_contrast: float, p_brightness: float, p_tint: Color, p_roughness: float = 0.9) -> void:
		saturation = p_saturation
		contrast = p_contrast
		brightness = p_brightness
		tint = p_tint
		roughness = p_roughness


static func _style(style: String) -> Style:
	match style:
		"rust":
			return Style.new(0.3, 0.88, 0.92, Color("b27a56"), 0.95)
		"burnt":
			return Style.new(0.1, 0.85, 0.78, Color("6a564a"), 0.97)
		"faded":
			return Style.new(0.38, 0.9, 0.95, Color("c4ad8e"), 0.92)
		"buggy":
			return Style.new(0.85, 1.0, 1.0, Color("f4e6d4"), 0.85)
		"rider":
			return Style.new(0.5, 0.92, 0.92, Color("d8c2a4"), 0.9)
		"rock":
			return Style.new(0.7, 1.0, 1.0, Color("e8b48c"), 0.95)
		"canvas":
			return Style.new(0.45, 1.0, 1.0, Color("e2cfb0"), 0.95)
		"canyon_a":
			return Style.new(0.9, 1.05, 1.0, Color(Palette.ROCK_D).lightened(0.35), 0.95)
		"canyon_b":
			return Style.new(0.9, 1.05, 1.0, Color(Palette.ROCK_B).lightened(0.3), 0.95)
		"canyon_c":
			return Style.new(0.85, 1.05, 0.95, Color(Palette.ROCK_A).lightened(0.3), 0.95)
		_:
			return Style.new(0.55, 1.0, 1.0, Color("efdcc4"), 0.9)


## Kolormapa paczki po korekcji (Image.adjust_bcs). Bez dostępu do pikseli (np. serwer
## bez GPU zwraca pusty obraz) zostaje oryginalna tekstura – odcień nadal działa.
static func _texture(kit_dir: String, saturation: float, contrast: float, brightness: float) -> Texture2D:
	var key := "%s|%.2f|%.2f|%.2f" % [kit_dir, saturation, contrast, brightness]
	if _textures.has(key):
		return _textures[key]
	var path := kit_dir + "/Textures/colormap.png"
	var base: Texture2D = null
	if ResourceLoader.exists(path):
		base = load(path) as Texture2D
	var result: Texture2D = base
	if base != null and (saturation != 1.0 or contrast != 1.0 or brightness != 1.0):
		var img := base.get_image()
		if img != null and not img.is_empty():
			img = img.duplicate() as Image
			if img.is_compressed():
				img.decompress()
			if not img.is_compressed():
				img.adjust_bcs(brightness, contrast, saturation)
				if not img.has_mipmaps():
					img.generate_mipmaps()
				result = ImageTexture.create_from_image(img)
	_textures[key] = result
	return result


static func _scrap_material(big: bool) -> ShaderMaterial:
	var key := "scrap|%s" % big
	if _materials.has(key):
		return _materials[key]
	var color := Palette.SCRAP_BIG_GLOW if big else Palette.SCRAP_GLOW
	# Umiarkowana emisja: zbyt jasny cyjan przechodzi w biel i zębatka traci kształt.
	var m := Palette.glow(color.darkened(0.2), 1.6 if big else 1.3).duplicate() as ShaderMaterial
	m.resource_name = "kenney_scrap_big" if big else "kenney_scrap"
	_materials[key] = m
	return m


# --- Narzędzia --------------------------------------------------------------------

## Prostopadłościan obejmujący widoczne siatki pod węzłem, w układzie tego węzła
## (bez jego własnej transformacji). Pusty AABB, gdy nie ma siatek.
static func bounds_of(node: Node3D) -> AABB:
	var acc := {"box": AABB(), "has": false}
	_collect_bounds(node, Transform3D.IDENTITY, acc)
	return acc["box"]


static func _collect_bounds(node: Node, xf: Transform3D, acc: Dictionary) -> void:
	for child in node.get_children():
		var n3 := child as Node3D
		if n3 == null or not n3.visible:
			continue
		var cxf := xf * n3.transform
		var mi := n3 as MeshInstance3D
		if mi != null and mi.mesh != null:
			var box: AABB = cxf * mi.mesh.get_aabb()
			if acc["has"]:
				acc["box"] = (acc["box"] as AABB).merge(box)
			else:
				acc["box"] = box
				acc["has"] = true
		_collect_bounds(n3, cxf, acc)


## Dopasowuje zawartość do obrysu (max szerokość X / długość Z; 0 = bez limitu), potem
## ustawia ją środkiem nad początkiem układu, spodem w y = -sink (lekko w piasku).
static func _settle(root: Node3D, content: Node3D, max_width: float, max_length: float, sink: float) -> void:
	var b := bounds_of(root)
	var k := 1.0
	if max_width > 0.0 and b.size.x > max_width:
		k = minf(k, max_width / b.size.x)
	if max_length > 0.0 and b.size.z > max_length:
		k = minf(k, max_length / b.size.z)
	if k < 1.0:
		content.transform = Transform3D(Basis.from_scale(Vector3.ONE * k), Vector3.ZERO) * content.transform
		b = bounds_of(root)
	var c := b.get_center()
	content.position -= Vector3(c.x, b.position.y + sink, c.z)


static func _scene(path: String) -> PackedScene:
	if _scenes.has(path):
		return _scenes[path]
	var ps: PackedScene = null
	if ResourceLoader.exists(path):
		ps = load(path) as PackedScene
	_scenes[path] = ps
	return ps


## Instancja modelu z nadpisanym materiałem (null, gdy pliku nie ma).
static func _instance(path: String, mat: Material) -> Node3D:
	var ps := _scene(path)
	if ps == null:
		return null
	var node := ps.instantiate() as Node3D
	if node != null and mat != null:
		_paint(node, mat)
	return node


static func _paint(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_paint(child, mat)


static func _rng_or_new(rng: RandomNumberGenerator) -> RandomNumberGenerator:
	if rng != null:
		return rng
	var r := RandomNumberGenerator.new()
	r.randomize()
	return r
