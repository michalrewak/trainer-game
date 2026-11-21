extends Control
## Garaż (baza między wyprawami): po lewej pojazd na obrotnicy z kartą pojazdu i treningu,
## po prawej zasoby, WARSZTAT (kafle modułów) i WYPRAWA (tryb, teren, czas, ustawienia).
## Całość obsługiwana padem (krzyżak/gałka + A) albo klawiaturą (strzałki + Enter).

const DURATIONS: Array[float] = [15.0, 30.0, 45.0, 60.0, 2.0]
const WEEKLY_GOALS: Array[int] = [100, 150, 200, 300, 400, 500]

var _detail: Label
var _tiles: Dictionary = {}
var _chips: Dictionary = {}
var _rank_name: Label
var _rank_line: Label
var _vehicle_line: Label
var _week_label: Label
var _week_fill: ColorRect
var _records_label: Label
var _slogan: Label
var _terrain_button: Button
var _duration_button: Button
var _ftp_button: Button
var _goal_button: Button
var _autofire_button: Button
var _source_button: Button
var _sound_button: Button
var _mode_button: Button
var _time_button: Button
var _plans: Array[String] = []
var _go_button: Button
var _buggy: BuggyView
var _turntable: Node3D
var _preview_cam: Camera3D
var _terrain_index := 0
var _duration_index := 0

const WEEK_BAR_PX := 420.0


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
	add_child(UiStyle.backdrop())

	# Lewa strona: podgląd 3D pojazdu.
	var view_box := SubViewportContainer.new()
	view_box.stretch = true
	view_box.anchor_right = 0.46
	view_box.anchor_bottom = 1.0
	view_box.offset_top = 10.0
	view_box.offset_bottom = -10.0
	view_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view_box)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	view_box.add_child(vp)
	vp.add_child(_make_preview_world())
	_build_vehicle_card()

	# Prawa strona: zasoby, warsztat, wyprawa.
	var right := MarginContainer.new()
	right.anchor_left = 0.46
	right.anchor_right = 1.0
	right.anchor_bottom = 1.0
	for m in ["margin_left", "margin_right"]:
		right.add_theme_constant_override(m, 36)
	right.add_theme_constant_override("margin_top", 26)
	add_child(right)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	right.add_child(col)

	# Nagłówek: nazwa ekranu i ranga wynikająca z FTP.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 24)
	head.add_child(UiStyle.label("GARAŻ", 60, Palette.UI_ACCENT))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var rank := UiStyle.plate(UiStyle.STEEL_MENU, Palette.UI_ACCENT)
	var rank_col := VBoxContainer.new()
	rank_col.add_theme_constant_override("separation", -2)
	rank.add_child(rank_col)
	_rank_name = UiStyle.label("", 34, Palette.UI_ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	rank_col.add_child(_rank_name)
	_rank_line = UiStyle.label("", 22, Palette.UI_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	rank_col.add_child(_rank_line)
	head.add_child(rank)
	col.add_child(head)

	# Zasoby.
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	for entry: Array in [["scrap", "ZŁOM", Palette.UI_SCRAP], ["fuel", "PALIWO", Color("ff9a5a")], ["work", "PRACA", Palette.UI_TEXT], ["crew", "ZAŁOGA", Color("ffd98a")]]:
		var chip := UiStyle.chip(str(entry[1]), entry[2], 36)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chips.add_child(chip)
		_chips[entry[0]] = chip.get_meta("value")
	col.add_child(chips)

	# Warsztat: kafle modułów.
	col.add_child(UiStyle.section("WARSZTAT"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	for id in UpgradeCatalog.ORDER:
		var tile := UpgradeTile.new()
		tile.pressed.connect(_on_buy.bind(id))
		tile.focus_entered.connect(_show_detail.bind(id))
		grid.add_child(tile)
		_tiles[id] = tile
	var detail_plate := UiStyle.plate(Color(0, 0, 0, 0.35))
	_detail = UiStyle.label("", 24, Palette.UI_TEXT)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(880, 92)
	_detail.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	detail_plate.add_child(_detail)
	col.add_child(detail_plate)

	# Wyprawa: tryb, teren, czas, pora i ustawienia.
	col.add_child(UiStyle.section("WYPRAWA"))
	_mode_button = _option("Jazda swobodna: gra proponuje wyzwania, napady i konwoje. Trening: plan (JSON/ZWO/FIT) prowadzi jazdę – interwały to burze piaskowe z polem bezpiecznym, cel ±5%.")
	_mode_button.pressed.connect(_cycle_mode)
	_terrain_button = _option("")
	_terrain_button.pressed.connect(_cycle_terrain)
	_terrain_button.focus_entered.connect(func() -> void: _detail.text = TerrainCatalog.description(TerrainCatalog.ORDER[_terrain_index]))
	col.add_child(_row([_mode_button, _terrain_button]))
	_duration_button = _option("Długość wyprawy. Test 2 min – do szybkiego sprawdzenia sterowania.")
	_duration_button.pressed.connect(_cycle_duration)
	_time_button = _option("Pora wyprawy. Zmienna: start za dnia, w połowie zachód słońca, końcówka nocą w reflektorach.")
	_time_button.pressed.connect(func() -> void:
		var modes: Array[String] = ["cycle", "day", "night"]
		App.set_time_mode(modes[(modes.find(App.time_mode()) + 1) % modes.size()])
		_refresh())
	col.add_child(_row([_duration_button, _time_button]))
	_ftp_button = _option("Twoje FTP: ←/→ zmienia o 5 W. Od niego liczą się strefy, cele mocy, tempo konwojów i ranga; niektóre tereny wymagają wyższego FTP.")
	_ftp_button.gui_input.connect(_on_ftp_input)
	_ftp_button.pressed.connect(func() -> void: _change_ftp(5.0))
	_goal_button = _option("Cel tygodnia w TSS (obciążenie treningowe). Pasek postępu jest na karcie treningu po lewej.")
	_goal_button.pressed.connect(func() -> void:
		var i := WEEKLY_GOALS.find(App.weekly_tss_goal())
		App.set_weekly_tss_goal(WEEKLY_GOALS[(i + 1) % WEEKLY_GOALS.size()])
		_refresh())
	col.add_child(_row([_ftp_button, _goal_button]))
	_autofire_button = _option("Auto-ogień: wieżyczka strzela sama do najbliższego celu – wygodne na ciężkich odcinkach.")
	_autofire_button.pressed.connect(func() -> void:
		App.set_auto_fire(not App.auto_fire_enabled())
		_refresh())
	_source_button = _option("Źródło mocy: PAD (symulacja na triggerze) albo TRENAŻER (Elite Suito przez mostek bridge/ – uruchom go przed wyprawą). Rekordy mocy są liczone osobno dla każdego źródła.")
	_source_button.pressed.connect(func() -> void:
		var next := PowerSourceFactory.KIND_GAMEPAD if App.power_source_kind() == PowerSourceFactory.KIND_TRAINER else PowerSourceFactory.KIND_TRAINER
		App.set_power_source_kind(next)
		_refresh())
	_sound_button = _option("Efekty dźwiękowe: zbieranie, strzały, wybuchy, ostrzeżenia. Generowane w grze, bez muzyki.")
	_sound_button.pressed.connect(func() -> void:
		App.set_sound(not bool(App.settings.get("sound", true)))
		_refresh())
	col.add_child(_row([_autofire_button, _source_button, _sound_button]))

	var go_row := HBoxContainer.new()
	go_row.add_theme_constant_override("separation", 10)
	_go_button = UiStyle.button("WYRUSZ!", 680)
	_go_button.custom_minimum_size.y = 84
	_go_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_go_button.pressed.connect(_on_go)
	_go_button.focus_entered.connect(func() -> void: _detail.text = "Każda wyprawa kończy się postępem: złom, paliwo, kilodżule i rekordy zapisują się także po przerwaniu jazdy.")
	go_row.add_child(_go_button)
	var quit := UiStyle.button("WYJŚCIE", 210)
	quit.custom_minimum_size.y = 84
	quit.add_theme_font_size_override("font_size", 30)
	quit.pressed.connect(func() -> void: App.quit_game())
	go_row.add_child(quit)
	col.add_child(go_row)
	col.add_child(UiStyle.caption("Pad: krzyżak – wybór, A – zatwierdź   ·   Klawiatura: strzałki, Enter   ·   F11 pełny ekran", 20))
	(func() -> void:
		if _go_button.is_inside_tree():
			_go_button.grab_focus()).call_deferred()


## Karta pojazdu i treningu na tle podglądu (lewy dół).
func _build_vehicle_card() -> void:
	var card := UiStyle.plate(UiStyle.STEEL, Palette.UI_ACCENT)
	card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.position += Vector2(30, -34)
	add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)
	col.add_child(UiStyle.caption("POJAZD", 20, Palette.UI_ACCENT))
	_vehicle_line = UiStyle.label("", 26, Palette.UI_TEXT)
	col.add_child(_vehicle_line)
	col.add_child(UiStyle.caption("TRENING", 20, Palette.UI_ACCENT))
	_week_label = UiStyle.label("", 26, Palette.UI_TEXT)
	col.add_child(_week_label)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(WEEK_BAR_PX, 14)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.size = Vector2(WEEK_BAR_PX, 14)
	bar.add_child(bg)
	_week_fill = ColorRect.new()
	_week_fill.color = Palette.UI_GOOD
	_week_fill.size = Vector2(0, 14)
	bar.add_child(_week_fill)
	col.add_child(bar)
	_records_label = UiStyle.label("", 24, Palette.UI_DIM)
	col.add_child(_records_label)
	_slogan = UiStyle.label("", 22, Palette.UI_DIM)
	_slogan.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_slogan.custom_minimum_size = Vector2(640, 0)
	col.add_child(_slogan)


## Przycisk opcji wyprawy; opis pokazuje się w polu szczegółów po najechaniu.
func _option(help: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(200, 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 27)
	b.focus_mode = Control.FOCUS_ALL
	b.clip_text = true
	if help != "":
		b.focus_entered.connect(func() -> void: _detail.text = help)
	return b


func _row(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	for b: Button in buttons:
		row.add_child(b)
	return row


func _refresh() -> void:
	var p := App.progress
	var rank := Lore.rank(App.ftp_w())
	_rank_name.text = str(rank["name"]).to_upper()
	_rank_line.text = "FTP %d W" % roundi(App.ftp_w()) + ("  ·  %s od %d W" % [str(rank["next_name"]), int(rank["next_at"])] if int(rank["next_at"]) > 0 else "  ·  najwyższa ranga")
	var load := p.loadout()
	(_chips["scrap"] as Label).text = str(p.total_scrap())
	(_chips["fuel"] as Label).text = str(p.fuel())
	(_chips["work"] as Label).text = "%d kJ" % p.total_energy_kj()
	(_chips["crew"] as Label).text = "%d/%d" % [load.active_crew(), load.crew_seats()]
	for id in UpgradeCatalog.ORDER:
		var lvl := p.upgrade_level(id)
		var maxl := UpgradeCatalog.max_level(id)
		var cap := UpgradeCatalog.level_cap(id, p.chassis_level())
		var cost := UpgradeCatalog.next_cost(id, lvl)
		var state := UpgradeTile.State.BUY
		var text := ""
		if cost.is_empty():
			state = UpgradeTile.State.MAXED
			text = "MAKSIMUM"
		elif lvl >= cap:
			state = UpgradeTile.State.CAPPED
			text = "wymaga większego podwozia"
		else:
			text = "%d złomu%s" % [int(cost["scrap"]), (" + %d paliwa" % int(cost["fuel"])) if int(cost["fuel"]) > 0 else ""]
			if not p.can_buy(id):
				state = UpgradeTile.State.POOR
				var kj := UpgradeCatalog.required_kj(id, lvl)
				if kj > p.total_energy_kj():
					text = "%d zł, %d pal., %d kJ pracy" % [int(cost["scrap"]), int(cost["fuel"]), kj]
		(_tiles[id] as UpgradeTile).set_data(UpgradeCatalog.display_name(id), lvl, maxl, cap, text, state)
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
	_goal_button.text = "Cel tygodnia: %d TSS" % App.weekly_tss_goal()
	_autofire_button.text = "Auto-ogień: %s" % ("TAK" if App.auto_fire_enabled() else "nie")
	_source_button.text = "Moc: %s" % ("TRENAŻER" if App.power_source_kind() == PowerSourceFactory.KIND_TRAINER else "PAD")
	_sound_button.text = "Dźwięk: %s" % ("TAK" if bool(App.settings.get("sound", true)) else "nie")
	_go_button.disabled = not missing.is_empty()
	_go_button.text = "WYRUSZ!  →  %s" % TerrainCatalog.display_name(tid) if missing.is_empty() else "TEREN ZABLOKOWANY"
	if _buggy != null:
		_buggy.apply_loadout(App.run_loadout())
	_refresh_card(load)


## Karta po lewej: napęd pojazdu, cel tygodnia, dni z rzędu, rekordy i hasło.
func _refresh_card(load: Loadout) -> void:
	var p := App.progress
	_vehicle_line.text = "Moc na kołach ×%.2f  ·  dopalacz %d× +%d%% na %d s" % [load.accelerator_multiplier(), load.boost_charges(), roundi(load.boost_gain() * 100.0), roundi(load.boost_duration_s())]
	var week := p.recent_stats(7)
	var goal := App.weekly_tss_goal()
	var tss := roundi(float(week["tss"]))
	var days := p.day_streak()
	_week_label.text = "Tydzień: TSS %d / %d  ·  %d min  ·  %d kJ%s" % [tss, goal, int(week["minutes"]), int(week["kj"]), "  ·  dni z rzędu: %d" % days if days > 0 else ""]
	_week_fill.size.x = WEEK_BAR_PX * clampf(float(tss) / goal, 0.0, 1.0)
	_week_fill.color = Palette.UI_SCRAP if tss >= goal else Palette.UI_GOOD
	var source := App.power_source_tag()
	var parts: Array[String] = []
	for i in TrainingMetrics.BEST_KEYS.size():
		var w := p.record(source, TrainingMetrics.BEST_KEYS[i])
		if w > 0.0:
			parts.append("%s %d W" % [TrainingMetrics.BEST_NAMES[i], roundi(w)])
	_records_label.text = "Rekordy mocy (%s): %s" % ["trenażer" if source == "trainer" else "pad", "  ·  ".join(parts) if not parts.is_empty() else "jeszcze brak – pierwsza jazda ustawi poprzeczkę"]
	_slogan.text = "„%s”" % Lore.slogan(p.runs().size())


## Kamera podglądu odsuwa się, gdy pojazd rośnie (kolejne osie).
func _frame_vehicle(loadout: Loadout) -> void:
	if _preview_cam == null or not _preview_cam.is_inside_tree():
		return
	var tail := BuggyView.tail_length(loadout)
	_preview_cam.look_at_from_position(Vector3(5.2, 3.6, 6.4) * (1.0 + tail * 0.11), Vector3(0, 0.6, 0.6), Vector3.UP)
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
	_detail.text = plan.describe() if plan != null else "Jazda swobodna – gra sama proponuje wyzwania, napady i konwoje."
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
	e.background_color = UiStyle.BACKDROP
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
	cam.look_at_from_position(Vector3(5.2, 3.6, 6.4), Vector3(0, 0.6, 0.6), Vector3.UP)
	return root
