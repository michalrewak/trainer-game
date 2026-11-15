extends TestCase
## KenneyModels: każda funkcja zwraca Node3D, gdy paczki są w projekcie (bez nich – null,
## żeby wołający wrócił do prymitywów), a wymiary trzymają się stref kolizji i konwencji.


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _free(nodes: Array[Node3D]) -> void:
	for n in nodes:
		if n != null:
			n.free()


func test_shipped_assets_load() -> void:
	# Paczki są w repozytorium: skoro katalog jest, modele muszą się wczytać (inaczej pozostałe
	# testy przeszłyby „na pusto”, a gra po cichu wróciłaby do prymitywów).
	if DirAccess.dir_exists_absolute(KenneyModels.ROOT_DIR):
		assert_true(KenneyModels.is_available(), "assets/kenney istnieje, ale modele się nie wczytują (uruchom --import)")


func test_every_function_returns_node3d_when_assets_exist() -> void:
	var rng := _rng(1234)
	var nodes: Array[Node3D] = []
	var labels: Array[String] = []
	for v in KenneyModels.WRECK_VARIANTS:
		nodes.append(KenneyModels.wreck(v, rng))
		labels.append("wreck(%d)" % v)
	nodes.append(KenneyModels.wreck(7))
	labels.append("wreck(7) bez rng")
	for big: bool in [false, true]:
		nodes.append(KenneyModels.scrap(big, rng))
		labels.append("scrap(%s)" % big)
	for i in 16:
		nodes.append(KenneyModels.roadside_prop(rng))
		labels.append("roadside_prop #%d" % i)
	for i in 6:
		nodes.append(KenneyModels.canyon_wall_piece(rng))
		labels.append("canyon_wall_piece #%d" % i)
	nodes.append(KenneyModels.buggy_wheel())
	labels.append("buggy_wheel()")
	nodes.append(KenneyModels.buggy_wheel(-1.0))
	labels.append("buggy_wheel(-1)")
	nodes.append(KenneyModels.buggy_rider())
	labels.append("buggy_rider()")
	nodes.append(KenneyModels.buggy_plate())
	labels.append("buggy_plate()")
	if KenneyModels.is_available():
		for i in nodes.size():
			assert_true(nodes[i] != null, "%s zwróciło null" % labels[i])
			if nodes[i] != null:
				assert_true(KenneyModels.bounds_of(nodes[i]).size.length() > 0.1, "%s bez siatek" % labels[i])
	else:
		for i in nodes.size():
			assert_true(nodes[i] == null, "%s bez assetów powinno zwrócić null" % labels[i])
	_free(nodes)


func test_wrecks_fit_collision_zone_and_sit_on_ground() -> void:
	if not KenneyModels.is_available():
		return
	var rng := _rng(99)
	for round_index in 12:
		for v in KenneyModels.WRECK_VARIANTS:
			var w := KenneyModels.wreck(v, rng)
			var b := KenneyModels.bounds_of(w)
			var label := "wrak v%d/%d:" % [v, round_index]
			assert_between(b.size.x, 1.6, KenneyModels.WRECK_MAX_WIDTH_M + 0.01, label + " szerokość")
			assert_between(b.size.z, 1.4, KenneyModels.WRECK_MAX_LENGTH_M + 0.01, label + " długość")
			assert_near(b.get_center().x, 0.0, 0.01, label + " środek X")
			assert_near(b.get_center().z, 0.0, 0.01, label + " środek Z")
			assert_between(b.position.y, -0.45, 0.0, label + " spód (lekko w piasku)")
			assert_between(b.end.y, 0.6, 3.0, label + " wysokość")
			w.free()


func test_scrap_size_and_center() -> void:
	if not KenneyModels.is_available():
		return
	for big: bool in [false, true]:
		var s := KenneyModels.scrap(big, _rng(3))
		# Słup światła nad dużym złomem dokłada WreckFactory – tu ma być sama zębatka.
		assert_eq(s.get_child_count(), 1, "sama zębatka, bez słupa światła big=%s" % big)
		var b := KenneyModels.bounds_of(s)
		var expected := KenneyModels.SCRAP_BIG_SIZE_M if big else KenneyModels.SCRAP_SIZE_M
		assert_near(maxf(b.size.x, b.size.y), expected, 0.03, "średnica zębatki big=%s" % big)
		assert_true(b.size.z < expected * 0.6, "zębatka stoi pionowo (cienka w Z) big=%s" % big)
		assert_true(b.get_center().length() < 0.05, "środek zębatki w początku układu big=%s" % big)
		s.free()


func test_canyon_walls_height_and_face() -> void:
	if not KenneyModels.is_available():
		return
	var rng := _rng(17)
	for i in 20:
		var w := KenneyModels.canyon_wall_piece(rng)
		var b := KenneyModels.bounds_of(w)
		var h: float = w.get_meta("height_m", 0.0)
		var length: float = w.get_meta("length_m", 0.0)
		assert_between(h, KenneyModels.WALL_MIN_HEIGHT_M, KenneyModels.WALL_MAX_HEIGHT_M, "height_m #%d" % i)
		assert_between(b.end.y, KenneyModels.WALL_MIN_HEIGHT_M - 0.01, KenneyModels.WALL_MAX_HEIGHT_M + 0.01, "wysokość siatek #%d" % i)
		assert_near(b.position.y, 0.0, 0.01, "spód ściany na ziemi #%d" % i)
		assert_true(length >= 5.0, "length_m #%d" % i)
		assert_true(b.size.z >= length * 0.95, "ściana pokrywa length_m #%d" % i)
		assert_between(b.end.x, 0.0, KenneyModels.WALL_MAX_OVERHANG_M + 0.01, "lico w x ≈ 0 (wystaje najwyżej %.1f m) #%d" % [KenneyModels.WALL_MAX_OVERHANG_M, i])
		assert_true(b.position.x < -4.0, "ściana sięga w głąb (-X) #%d" % i)
		w.free()


func test_roadside_props_fit_between_road_and_wall() -> void:
	if not KenneyModels.is_available():
		return
	var rng := _rng(5)
	for i in 40:
		var p := KenneyModels.roadside_prop(rng)
		var b := KenneyModels.bounds_of(p)
		assert_true(b.size.x <= 3.21, "rekwizyt #%d szerokość %.2f" % [i, b.size.x])
		assert_near(b.get_center().x, 0.0, 0.01, "rekwizyt #%d środek X" % i)
		assert_between(b.position.y, -0.05, 0.0, "rekwizyt #%d na ziemi" % i)
		assert_between(b.end.y, 0.1, 5.0, "rekwizyt #%d wysokość" % i)
		p.free()


func test_buggy_parts_dimensions() -> void:
	if not KenneyModels.is_available():
		return
	for side: float in [1.0, -1.0]:
		var wheel := KenneyModels.buggy_wheel(side)
		var wb := KenneyModels.bounds_of(wheel)
		assert_near(wb.size.y, KenneyModels.WHEEL_DIAMETER_M, 0.02, "średnica koła")
		assert_near(wb.size.z, KenneyModels.WHEEL_DIAMETER_M, 0.02, "średnica koła (Z)")
		assert_near(wb.size.x, KenneyModels.WHEEL_WIDTH_M, 0.02, "szerokość koła (oś X)")
		assert_true(wb.get_center().length() < 0.01, "środek koła w początku układu")
		wheel.free()
	var small := KenneyModels.buggy_wheel(1.0, 0.8)
	var sb := KenneyModels.bounds_of(small)
	assert_near(sb.size.y, 0.8, 0.02, "koło przyczepy: średnica")
	assert_near(sb.size.x, KenneyModels.WHEEL_WIDTH_M * 0.8 / KenneyModels.WHEEL_DIAMETER_M, 0.02, "koło przyczepy: szerokość")
	small.free()
	var rider := KenneyModels.buggy_rider()
	var rb := KenneyModels.bounds_of(rider)
	assert_near(rb.size.y, KenneyModels.RIDER_HEIGHT_M, 0.02, "wysokość kierowcy")
	assert_near(rb.position.y, 0.0, 0.01, "kierowca stoi spodem w y = 0")
	rider.free()
	var plate := KenneyModels.buggy_plate()
	var pb := KenneyModels.bounds_of(plate)
	assert_true(pb.size.x < 0.3, "płyta pancerza cienka w X (%.2f)" % pb.size.x)
	assert_between(pb.size.y, 0.4, 0.75, "wysokość płyty")
	assert_between(pb.size.z, 1.3, 1.8, "długość płyty")
	assert_true(pb.get_center().length() < 0.01, "środek płyty w początku układu")
	plate.free()


func test_materials_are_shared_and_matte() -> void:
	if not KenneyModels.is_available():
		return
	var a := KenneyModels.material(KenneyModels.CAR_DIR, "rust")
	var b := KenneyModels.material(KenneyModels.CAR_DIR, "rust")
	assert_true(a == b, "ten sam materiał z cache")
	assert_true(a != KenneyModels.material(KenneyModels.CAR_DIR, "burnt"), "osobny materiał dla spalonych")
	for style: String in ["dust", "rust", "burnt", "faded", "buggy", "rider", "rock", "canvas", "canyon_a"]:
		var m := KenneyModels.material(KenneyModels.SURVIVAL_DIR, style)
		assert_true(m.albedo_texture != null, "%s: kolormapa jako albedo" % style)
		assert_between(m.roughness, 0.85, 1.0, "%s: szorstkość" % style)
		assert_eq(m.metallic, 0.0, "%s: bez metaliczności" % style)
