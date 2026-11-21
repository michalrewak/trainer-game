extends Control
## Garaż (baza między wyprawami, etap 3): podgląd pojazdu z modułami, sklep ulepszeń
## za złom i paliwo, wybór terenu i długości wyprawy, FTP i auto-ogień.
## Całość obsługiwana padem (krzyżak/gałka + A) albo klawiaturą (strzałki + Enter).

const DURATIONS: Array[float] = [15.0, 30.0, 45.0, 60.0, 2.0]

var _stash: Label
var _detail: Label
var _upgrade_buttons: Dictionary = {}
var _terrain_button: Button
var _duration_button: Button
var _ftp_button: Button
var _autofire_button: Button
var _source_button: Button
var _mode_button: Button
var _rank_label: Label
var _time_button: Button
var _plans: Array[String] = []
var _go_button: Button
var _buggy: BuggyView
var _turntable: Node3D
var _preview_cam: Camera3D
var _terrain_index := 0
var _duration_index := 0


func _ready() -> void:
	theme = UiStyle.menu_theme()
	_terrain_index = maxi(0, TerrainCatalog.ORDER.find(App.selected_terrain))
	_duration_index = _closest_duration(App.selected_minutes)
	_build()
	_refresh()
	if App.options.screenshot_dir != "" and not App.options.autostart and not App.is_headless():
		await get_tree().create_timer(1.2).timeout
		await Screenshot.capture(self, App.options.screenshot_dir + "/garage.png")
		get_tree().quit()


func _process(delta: float) -> void:
	if _turntable != null:
		_turntable.rotation.y += delta * 0.35


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1c1410")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Lewa połowa: podgląd 3D pojazdu.
	var view_box := SubViewportContainer.new()
	view_box.stretch = true
	view_box.anchor_right = 0.48
	view_box.anchor_bottom = 1.0
	view_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view_box)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	view_box.add_child(vp)
	vp.add_child(_make_preview_world())

	# Prawa połowa: sklep i wyprawa.
	var right := MarginContainer.new()
	right.anchor_left = 0.48
	right.anchor_right = 1.0
	right.anchor_bottom = 1.0
	for m in ["margin_left", "margin_right"]:
		right.add_theme_constant_override(m, 40)
	right.add_theme_constant_override("margin_top", 36)
	add_child(right)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	right.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 40)
	head.add_child(UiStyle.label("GARAŻ", 72, Palette.UI_ACCENT))
	_stash = UiStyle.label("", 40, Palette.UI_SCRAP)
	head.add_child(_stash)
	col.add_child(head)
	_rank_label = UiStyle.label("", 28, Palette.UI_TEXT)
	col.add_child(_rank_label)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	for id in UpgradeCatalog.ORDER:
		var b := _small_button(444)
		b.pressed.connect(_on_buy.bind(id))
		b.focus_entered.connect(_show_detail.bind(id))
		grid.add_child(b)
		_upgrade_buttons[id] = b
	_detail = UiStyle.label("", 26, Palette.UI_DIM)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(900, 96)
	col.add_child(_detail)
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 12)
	_mode_button = _small_button(444)
	_mode_button.pressed.connect(_cycle_mode)
	_mode_button.focus_entered.connect(func() -> void: _detail.text = "Jazda swobodna: gra proponuje wyzwania. Trening: plan (JSON/ZWO/FIT) prowadzi jazdę – interwały to burze piaskowe z polem bezpiecznym, cel ±5%.")
	mode_row.add_child(_mode_button)
	_terrain_button = _small_button(444)
	_terrain_button.pressed.connect(_cycle_terrain)
	_terrain_button.focus_entered.connect(func() -> void: _detail.text = TerrainCatalog.description(TerrainCatalog.ORDER[_terrain_index]))
	mode_row.add_child(_terrain_button)
	col.add_child(mode_row)
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 12)
	_duration_button = _small_button(444)
	_duration_button.pressed.connect(_cycle_duration)
	_duration_button.focus_entered.connect(func() -> void: _detail.text = "Długość wyprawy. Test 2 min – do szybkiego sprawdzenia sterowania.")
	time_row.add_child(_duration_button)
	_time_button = _small_button(444)
	_time_button.pressed.connect(func() -> void:
		var modes: Array[String] = ["cycle", "day", "night"]
		App.set_time_mode(modes[(modes.find(App.time_mode()) + 1) % modes.size()])
		_refresh())
	_time_button.focus_entered.connect(func() -> void: _detail.text = "Pora wyprawy. Zmienna: start za dnia, w połowie zachód słońca, końcówka nocą w reflektorach.")
	time_row.add_child(_time_button)
	col.add_child(time_row)
	var settings_row := HBoxContainer.new()
	settings_row.add_theme_constant_override("separation", 12)
	_ftp_button = _small_button(380)
	_ftp_button.gui_input.connect(_on_ftp_input)
	_ftp_button.pressed.connect(func() -> void: _change_ftp(5.0))
	_ftp_button.focus_entered.connect(func() -> void: _detail.text = "Twoje FTP: ←/→ zmienia o 5 W. Cel mocy w jeździe swobodnej = 65% FTP; niektóre tereny wymagają wyższego FTP.")
	settings_row.add_child(_ftp_button)
	_autofire_button = _small_button(250)
	_autofire_button.pressed.connect(func() -> void:
		App.set_auto_fire(not App.auto_fire_enabled())
		_refresh())
	_autofire_button.focus_entered.connect(func() -> void: _detail.text = "Auto-ogień: wieżyczka strzela sama do najbliższego celu – wygodne na ciężkich odcinkach.")
	settings_row.add_child(_autofire_button)
	_source_button = _small_button(250)
	_source_button.pressed.connect(func() -> void:
		var next := PowerSourceFactory.KIND_GAMEPAD if App.power_source_kind() == PowerSourceFactory.KIND_TRAINER else PowerSourceFactory.KIND_TRAINER
		App.set_power_source_kind(next)
		_refresh())
	_source_button.focus_entered.connect(func() -> void: _detail.text = "Źródło mocy: PAD (symulacja na triggerze) albo TRENAŻER (Elite Suito przez mostek bridge/ – uruchom go przed wyprawą).")
	settings_row.add_child(_source_button)
	col.add_child(settings_row)
	var go_row := HBoxContainer.new()
	go_row.add_theme_constant_override("separation", 12)
	_go_button = UiStyle.button("WYRUSZ!", 680)
	_go_button.custom_minimum_size.y = 84
	_go_button.pressed.connect(_on_go)
	_go_button.focus_entered.connect(func() -> void: _detail.text = _motto())
	go_row.add_child(_go_button)
	var quit := UiStyle.button("WYJŚCIE", 210)
	quit.custom_minimum_size.y = 84
	quit.add_theme_font_size_override("font_size", 30)
	quit.pressed.connect(func() -> void: App.quit_game())
	go_row.add_child(quit)
	col.add_child(go_row)
	col.add_child(UiStyle.label("Pad: krzyżak – wybór, A – zatwierdź   ·   Klawiatura: strzałki, Enter   ·   F11 pełny ekran", 22, Palette.UI_DIM))
	(func() -> void:
		if _go_button.is_inside_tree():
			_go_button.grab_focus()).call_deferred()


func _small_button(width: float = 900.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(width, 56)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 28)
	b.focus_mode = Control.FOCUS_ALL
	return b


func _refresh() -> void:
	var p := App.progress
	var rank := Lore.rank(App.ftp_w())
	var next_rank := "  ·  do rangi %s: +%d W" % [str(rank["next_name"]), int(rank["next_at"]) - roundi(App.ftp_w())] if int(rank["next_at"]) > 0 else ""
	_rank_label.text = "Ranga: %s  ·  FTP %d W%s" % [str(rank["name"]).to_upper(), roundi(App.ftp_w()), next_rank]
	_stash.text = "Złom: %d  ·  Paliwo: %d  ·  Praca: %d kJ" % [p.total_scrap(), p.fuel(), p.total_energy_kj()]
	for id in UpgradeCatalog.ORDER:
		var lvl := p.upgrade_level(id)
		var maxl := UpgradeCatalog.max_level(id)
		var pips := "■".repeat(lvl) + "□".repeat(maxl - lvl)
		var text := "%s %s" % [UpgradeCatalog.display_name(id), pips]
		var cost := UpgradeCatalog.next_cost(id, lvl)
		if cost.is_empty():
			text += "  maks."
		elif lvl >= UpgradeCatalog.level_cap(id, p.chassis_level()):
			text += "  (podwozie)"
		else:
			text += "  %d zł%s" % [int(cost["scrap"]), (" + %d pal." % int(cost["fuel"])) if int(cost["fuel"]) > 0 else ""]
		var b: Button = _upgrade_buttons[id]
		b.text = text
		b.modulate = Color.WHITE if (cost.is_empty() or p.can_buy(id)) else Color(1, 1, 1, 0.55)
	var tid := TerrainCatalog.ORDER[_terrain_index]
	var missing := TerrainCatalog.missing_requirements(tid, p.loadout(), App.ftp_w())
	_terrain_button.text = "Teren: %s%s" % [TerrainCatalog.display_name(tid), "" if missing.is_empty() else " (blokada)"]
	if not missing.is_empty() and _terrain_button.has_focus():
		_detail.text = "%s wymaga: %s." % [TerrainCatalog.display_name(tid), ", ".join(missing)]
	var plan := App.selected_plan()
	if plan != null:
		_mode_button.text = "Trening: %s" % plan.name
		_duration_button.text = "Czas: %s (z planu)" % WorkoutStep.format_duration(plan.total_duration_s())
	else:
		_mode_button.text = "Tryb: jazda swobodna"
		var minutes := DURATIONS[_duration_index]
		_duration_button.text = "Czas: %s" % ("TEST 2 min" if minutes < 5.0 else "%d min" % roundi(minutes))
	_time_button.text = "Pora: %s" % {"cycle": "zmienna (dzień → noc)", "day": "dzień", "night": "noc"}.get(App.time_mode(), "zmienna (dzień → noc)")
	_frame_vehicle(App.run_loadout())
	_ftp_button.text = "FTP: %d W  ← →" % roundi(App.ftp_w())
	_autofire_button.text = "Auto-ogień: %s" % ("TAK" if App.auto_fire_enabled() else "nie")
	_source_button.text = "Moc: %s" % ("TRENAŻER" if App.power_source_kind() == PowerSourceFactory.KIND_TRAINER else "PAD")
	_go_button.disabled = not missing.is_empty()
	_go_button.text = "WYRUSZ!  →  %s" % TerrainCatalog.display_name(tid) if missing.is_empty() else "TEREN ZABLOKOWANY"
	if _buggy != null:
		_buggy.apply_loadout(App.run_loadout())


## Hasło dnia i trening z ostatniego tygodnia – przypomnienie, po co się jeździ.
func _motto() -> String:
	var week := App.progress.recent_stats(7)
	var text := "„%s”" % Lore.slogan(App.progress.runs().size())
	if int(week["runs"]) > 0:
		text += "\nOstatnie 7 dni: %d wypraw  ·  %d min  ·  TSS %d  ·  %d kJ" % [int(week["runs"]), int(week["minutes"]), roundi(float(week["tss"])), int(week["kj"])]
	else:
		text += "\nW tym tygodniu jeszcze nie kręciłeś. Pustkowia czekają."
	return text


## Kamera podglądu odsuwa się, gdy pojazd rośnie (kolejne osie i przyczepy).
func _frame_vehicle(loadout: Loadout) -> void:
	if _preview_cam == null or not _preview_cam.is_inside_tree():
		return
	var tail := BuggyView.tail_length(loadout)
	_preview_cam.look_at_from_position(Vector3(5.2, 3.3, 6.4) * (1.0 + tail * 0.11), Vector3(0, 1.0, 0.6), Vector3.UP)
	if _buggy != null:
		_buggy.position.z = -tail * 0.45


func _show_detail(id: String) -> void:
	var p := App.progress
	var lvl := p.upgrade_level(id)
	var text := UpgradeCatalog.description(id)
	var cost := UpgradeCatalog.next_cost(id, lvl)
	if not cost.is_empty():
		text += "\nPoziom %d: %s. Koszt: %d złomu%s. %s" % [lvl + 1, UpgradeCatalog.level_effect(id, lvl + 1), int(cost["scrap"]), (" i %d paliwa" % int(cost["fuel"])) if int(cost["fuel"]) > 0 else "", p.block_reason(id)]
	else:
		text += "\nMaksymalny poziom: %s." % UpgradeCatalog.level_effect(id, lvl)
	_detail.text = text


func _on_buy(id: String) -> void:
	if App.progress.buy(id):
		App.progress.save_data()
		_detail.text = "Zamontowano: %s (poziom %d)." % [UpgradeCatalog.display_name(id), App.progress.upgrade_level(id)]
	else:
		_detail.text = "%s: %s" % [UpgradeCatalog.display_name(id), App.progress.block_reason(id)]
	_refresh()


func _cycle_terrain() -> void:
	_terrain_index = (_terrain_index + 1) % TerrainCatalog.ORDER.size()
	App.selected_terrain = TerrainCatalog.ORDER[_terrain_index]
	_detail.text = TerrainCatalog.description(App.selected_terrain)
	_refresh()


func _cycle_mode() -> void:
	if _plans.is_empty():
		_plans = App.available_plans()
	var options: Array[String] = [""]
	options.append_array(_plans)
	var i := options.find(App.selected_plan_path)
	App.selected_plan_path = options[(i + 1) % options.size()]
	var plan := App.selected_plan()
	_detail.text = plan.describe() if plan != null else "Jazda swobodna – gra sama proponuje wyzwania (podjazd, ucieczka, sprint)."
	_refresh()


func _cycle_duration() -> void:
	_duration_index = (_duration_index + 1) % DURATIONS.size()
	_refresh()


func _on_ftp_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left"):
		_change_ftp(-5.0)
		accept_event()
	elif event.is_action_pressed(&"ui_right"):
		_change_ftp(5.0)
		accept_event()


func _change_ftp(delta_w: float) -> void:
	App.set_ftp_w(App.ftp_w() + delta_w)
	_refresh()


func _on_go() -> void:
	App.selected_terrain = TerrainCatalog.ORDER[_terrain_index]
	App.start_run(DURATIONS[_duration_index])


static func _closest_duration(minutes: float) -> int:
	var best := 0
	for i in DURATIONS.size():
		if absf(DURATIONS[i] - minutes) < absf(DURATIONS[best] - minutes):
			best = i
	return best


func _make_preview_world() -> Node3D:
	var root := Node3D.new()
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("2a1d16")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("a08070")
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffe0b8")
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	root.add_child(sun)
	sun.look_at_from_position(Vector3(4, 6, 3), Vector3.ZERO, Vector3.UP)
	var rim := OmniLight3D.new()
	rim.light_color = Color("ff9a50")
	rim.light_energy = 2.0
	rim.omni_range = 9.0
	rim.position = Vector3(-3.0, 2.5, -2.5)
	root.add_child(rim)
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 4.2
	floor_mesh.bottom_radius = 4.4
	floor_mesh.height = 0.2
	floor_mesh.radial_segments = 24
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = floor_mesh
	floor_mi.material_override = Palette.mat(Color("5a4232"))
	floor_mi.position = Vector3(0, -0.1, 0)
	root.add_child(floor_mi)
	_turntable = Node3D.new()
	_turntable.rotation.y = 2.3
	root.add_child(_turntable)
	_buggy = (load("res://scenes/run/buggy.tscn") as PackedScene).instantiate()
	_turntable.add_child(_buggy)
	(func() -> void:
		if is_instance_valid(_buggy):
			_buggy.update_combat(null, 0.25, 0.016)
			_buggy.apply_loadout(App.run_loadout())).call_deferred()
	var cam := Camera3D.new()
	_preview_cam = cam
	cam.fov = 42.0
	root.add_child(cam)
	cam.look_at_from_position(Vector3(5.2, 3.3, 6.4), Vector3(0, 1.0, 0.6), Vector3.UP)
	return root
