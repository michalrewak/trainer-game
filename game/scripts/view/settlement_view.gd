class_name SettlementView
extends Node3D
## Osada gracza: brama z wieżami w turkusowych barwach, mur ze złomu, plac z blaszakami,
## ogniskami i ludźmi. Wyprawa zaczyna się wyjazdem z osady i kończy wjazdem do następnej –
## to zastępuje „metę”. Stoi na trasie (dystans) i przesuwa się razem ze światem.
## Bez nadproża nad drogą: kamera przejeżdża nad bramą.

const HOME := Color("38e0d0")
## Brama wyjazdowa stoi tyle metrów za linią startu.
const DEPARTURE_GATE_M := 34.0

var _departure: Node3D
var _arrival: Node3D
var _arrival_d := -1.0
var _people: Array[Node3D] = []
var _flames: Array[Node3D] = []
var _time := 0.0


func sync(sim: RunSimulation, delta: float) -> void:
	_time += delta
	var pd := sim.vehicle.distance_m
	# Wyjazd: plac i brama widoczne przez pierwsze metry wyprawy.
	if _departure == null and pd < DEPARTURE_GATE_M + 60.0:
		_departure = _build(false)
		add_child(_departure)
	if _departure != null:
		_departure.position.z = -(DEPARTURE_GATE_M - pd)
		if pd > DEPARTURE_GATE_M + 80.0:
			_departure.queue_free()
			_departure = null
			_prune()
	# Dojazd: brama pojawia się na horyzoncie pod koniec czasu.
	var arrival := sim.arrival
	if arrival.is_visible():
		if _arrival == null:
			_arrival = _build(true)
			add_child(_arrival)
		_arrival_d = arrival.gate_d
		_arrival.position.z = -(_arrival_d - pd)
	elif _arrival != null:
		_arrival.queue_free()
		_arrival = null
		_prune()
	# Ludzie machają, ogień migocze.
	for i in _people.size():
		if is_instance_valid(_people[i]):
			_people[i].position.y = absf(sin(_time * 5.0 + i * 1.7)) * 0.25
			_people[i].rotation.z = sin(_time * 6.0 + i) * 0.12
	for i in _flames.size():
		if is_instance_valid(_flames[i]):
			var k := 1.0 + 0.25 * sin(_time * 17.0 + i * 2.3)
			_flames[i].scale = Vector3(k, 1.0 + 0.4 * sin(_time * 13.0 + i), k)


func _prune() -> void:
	_people = _people.filter(func(n: Node3D) -> bool: return is_instance_valid(n) and not n.is_queued_for_deletion())
	_flames = _flames.filter(func(n: Node3D) -> bool: return is_instance_valid(n) and not n.is_queued_for_deletion())


## arriving = true: latarnie na dojeździe (przed bramą, +Z), plac za bramą (-Z).
## arriving = false: plac przed bramą (od strony startu, +Z), za bramą pustkowie.
func _build(arriving: bool) -> Node3D:
	var root := Node3D.new()
	var wall := Palette.mat(Color("5a4a3e"), 0.9, 0.2)
	var rust := Palette.mat(Palette.RUST, 0.9, 0.3)
	var dark := Palette.mat(Color("2a2422"), 0.8, 0.3)
	var steel := Palette.mat(Color("a8a094"), 0.45, 0.8)
	var home := Palette.glow(HOME, 1.6)
	var lamp := Palette.glow(Color("ffe2a0"), 3.2)
	var cloth := Palette.mat(Color("1f8a82"), 0.9)

	# Wieże po obu stronach drogi: turkusowe proporce i ciepłe światło – to „swoi”.
	for s: float in [-1.0, 1.0]:
		var t := Node3D.new()
		t.position = Vector3(s * 9.2, 0, 0)
		t.add_child(LowPoly.box(Vector3(3.6, 9.5, 3.6), wall, Vector3(0, 4.75, 0)))
		t.add_child(LowPoly.box(Vector3(4.6, 0.4, 4.6), rust, Vector3(0, 9.7, 0)))
		for c: Vector3 in [Vector3(-2.0, 10.5, -2.0), Vector3(2.0, 10.5, -2.0), Vector3(-2.0, 10.5, 2.0), Vector3(2.0, 10.5, 2.0)]:
			t.add_child(LowPoly.box(Vector3(0.5, 1.2, 0.5), rust, c))
		t.add_child(LowPoly.box(Vector3(2.4, 0.5, 0.2), home, Vector3(0, 7.6, 1.85)))
		t.add_child(LowPoly.box(Vector3(2.4, 0.5, 0.2), home, Vector3(0, 7.6, -1.85)))
		t.add_child(LowPoly.cylinder(0.4, 0.35, lamp, Vector3(0, 11.4, 0), Vector3.ZERO, 8))
		t.add_child(LowPoly.tube(Vector3(0, 9.9, 0), Vector3(0, 15.0, 0), 0.07, dark))
		t.add_child(LowPoly.box(Vector3(0.06, 1.3, 2.4), cloth, Vector3(0, 14.2, 1.25)))
		# Otwarte skrzydło bramy, odchylone na zewnątrz.
		t.add_child(LowPoly.box(Vector3(0.3, 5.6, 4.6), rust, Vector3(-s * 1.2, 2.9, -2.6 if arriving else 2.6), Vector3(0, s * (0.5 if arriving else -0.5), 0)))
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.85, 0.6)
		light.light_energy = 3.0
		light.omni_range = 16.0
		light.position = Vector3(-s * 2.5, 6.0, 0)
		t.add_child(light)
		root.add_child(t)
		# Mur ze złomu od wieży w głąb pustyni.
		for k in 7:
			root.add_child(LowPoly.box(Vector3(5.2, 3.4 + (k % 2) * 0.9, 1.3), wall if k % 2 == 0 else rust, Vector3(s * (13.4 + k * 5.0), 1.9, 0.3 * (k % 3)), Vector3(0, 0.06 * (k % 3 - 1), 0)))
			if k % 2 == 1:
				root.add_child(LowPoly.cylinder(0.07, 1.6, steel, Vector3(s * (13.4 + k * 5.0), 4.9, 0.0), Vector3.ZERO, 5))
	# Tablica z nazwą na prawej wieży.
	var board := Label3D.new()
	board.text = "OSADA"
	board.font_size = 300
	board.outline_size = 40
	board.modulate = HOME
	board.pixel_size = 0.01
	# Gracz zawsze nadjeżdża od strony +Z, więc napis patrzy w tę stronę.
	board.position = Vector3(9.2, 12.6, 2.0)
	root.add_child(board)

	# Latarnie wzdłuż dojazdu albo wyjazdu (po stronie pustkowia).
	var out_dir := 1.0 if arriving else -1.0
	for i in 7:
		for s: float in [-1.0, 1.0]:
			var z := out_dir * (18.0 + i * 20.0)
			root.add_child(LowPoly.cylinder(0.09, 3.6, dark, Vector3(s * 7.4, 1.8, z), Vector3.ZERO, 6))
			root.add_child(LowPoly.box(Vector3(0.35, 0.35, 0.35), lamp if i % 2 == 0 else home, Vector3(s * 7.4, 3.75, z)))
	# Plac osady po drugiej stronie bramy.
	_build_yard(root, -out_dir)
	return root


## Plac: blaszaki z oświetlonymi oknami, warsztat z żurawiem, ogniska i ludzie przy drodze.
func _build_yard(root: Node3D, dir: float) -> void:
	var rust := Palette.mat(Palette.RUST_LIGHT, 0.9, 0.3)
	var dark := Palette.mat(Color("2a2422"), 0.8, 0.3)
	var tin := Palette.mat(Color("6a6258"), 0.6, 0.6)
	var window := Palette.glow(Color("ffd9a0"), 2.2)
	var fire := Palette.glow(Color("ff8a2a"), 4.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 5:
		for s: float in [-1.0, 1.0]:
			var z := dir * (10.0 + i * 15.0 + rng.randf_range(-2.0, 2.0))
			var x := s * rng.randf_range(11.0, 15.0)
			var w := rng.randf_range(4.5, 7.0)
			var h := rng.randf_range(3.0, 5.5)
			root.add_child(LowPoly.box(Vector3(w, h, 6.0), rust if (i + int(s)) % 2 == 0 else tin, Vector3(x, h * 0.5, z)))
			root.add_child(LowPoly.box(Vector3(w + 0.6, 0.2, 6.6), dark, Vector3(x, h + 0.1, z), Vector3(0, 0, s * 0.06)))
			root.add_child(LowPoly.box(Vector3(0.1, 0.9, 1.4), window, Vector3(x - s * (w * 0.5 + 0.03), h * 0.55, z)))
	# Warsztat Zębatki: żuraw z hakiem.
	root.add_child(LowPoly.tube(Vector3(-11.0, 0, dir * 40.0), Vector3(-11.0, 9.0, dir * 40.0), 0.18, dark))
	root.add_child(LowPoly.tube(Vector3(-11.0, 9.0, dir * 40.0), Vector3(-6.5, 8.0, dir * 40.0), 0.12, dark))
	root.add_child(LowPoly.tube(Vector3(-6.5, 8.0, dir * 40.0), Vector3(-6.5, 5.5, dir * 40.0), 0.04, tin))
	# Ogniska w beczkach.
	for i in 4:
		for s: float in [-1.0, 1.0]:
			var p := Vector3(s * 7.6, 0, dir * (6.0 + i * 16.0))
			root.add_child(LowPoly.cylinder(0.4, 0.9, dark, p + Vector3(0, 0.45, 0), Vector3.ZERO, 8))
			var flame := Node3D.new()
			flame.position = p + Vector3(0, 1.0, 0)
			flame.add_child(LowPoly.box(Vector3(0.45, 0.7, 0.45), fire, Vector3(0, 0.3, 0), Vector3(0, 0.6, 0)))
			root.add_child(flame)
			_flames.append(flame)
			if i % 2 == 0:
				var light := OmniLight3D.new()
				light.light_color = Color(1.0, 0.6, 0.25)
				light.light_energy = 2.4
				light.omni_range = 9.0
				light.position = p + Vector3(0, 1.6, 0)
				root.add_child(light)
	# Ludzie przy drodze: machają na powitanie.
	var skins: Array[Color] = [Color("b07a58"), Color("8a5a40"), Color("c89a76"), Color("6e4a36")]
	var rags: Array[Color] = [Color("6a5a44"), Color("1f8a82"), Color("7a6248"), Color("4e463c")]
	for i in 12:
		var s := -1.0 if i % 2 == 0 else 1.0
		var person := Node3D.new()
		var holder := Node3D.new()
		holder.position = Vector3(s * rng.randf_range(7.2, 9.4), 0, dir * (4.0 + i * 5.5))
		holder.add_child(person)
		person.add_child(LowPoly.box(Vector3(0.5, 0.9, 0.32), Palette.mat(rags[i % 4], 0.95), Vector3(0, 1.15, 0)))
		person.add_child(LowPoly.box(Vector3(0.32, 0.32, 0.32), Palette.mat(skins[i % 4], 0.85), Vector3(0, 1.78, 0)))
		for a: float in [-1.0, 1.0]:
			person.add_child(LowPoly.box(Vector3(0.14, 0.7, 0.14), Palette.mat(rags[(i + 1) % 4], 0.95), Vector3(a * 0.14, 0.35, 0)))
			person.add_child(LowPoly.box(Vector3(0.12, 0.7, 0.12), Palette.mat(skins[i % 4], 0.85), Vector3(a * 0.36, 1.85, 0), Vector3(0, 0, -a * 0.5)))
		root.add_child(holder)
		_people.append(person)
