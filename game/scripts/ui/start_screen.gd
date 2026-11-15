extends Control
## Ekran startowy: wybór długości wyprawy (15 min / test 2 min) i stan magazynu złomu.
## Pad: krzyżak/gałka – wybór, A – start. Klawiatura: strzałki, Enter.


func _ready() -> void:
	theme = UiStyle.menu_theme()
	_build()
	if App.options.screenshot_dir != "" and not App.options.autostart and not App.is_headless():
		await get_tree().create_timer(1.0).timeout
		await Screenshot.capture(self, App.options.screenshot_dir + "/start.png")
		get_tree().quit()


func _build() -> void:
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.texture = _sky_gradient()
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(bg)
	var mesas := _mesa_silhouette()
	add_child(mesas)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 26)
	center.add_child(col)
	col.add_child(UiStyle.label("WASTELAND RIDER", 132, Palette.UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiStyle.label("Kanion Rdzy · wyprawa po złom", 44, Palette.UI_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	var stash := UiStyle.panel(Palette.UI_PANEL_STRONG)
	stash.add_child(UiStyle.label("Złom w magazynie: %d" % App.progress.total_scrap(), 48, Palette.UI_SCRAP, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(stash)

	var long_run := UiStyle.button("WYPRAWA %d MIN" % roundi(LaunchOptions.DEFAULT_MINUTES))
	long_run.pressed.connect(func() -> void: App.start_run(LaunchOptions.DEFAULT_MINUTES))
	var test_run := UiStyle.button("TEST %d MIN" % roundi(LaunchOptions.TEST_MINUTES))
	test_run.pressed.connect(func() -> void: App.start_run(LaunchOptions.TEST_MINUTES))
	var quit := UiStyle.button("WYJŚCIE")
	quit.pressed.connect(func() -> void: App.quit_game())
	for b in [long_run, test_run, quit]:
		var holder := CenterContainer.new()
		holder.add_child(b)
		col.add_child(holder)
	var hint := UiStyle.label("Pad: krzyżak – wybór, A – start   ·   Klawiatura: strzałki, Enter   ·   F11 pełny ekran, F10 następny ekran", 28, Palette.UI_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(hint)
	var focus_target: Button = test_run if absf(App.selected_minutes - LaunchOptions.TEST_MINUTES) < 0.01 else long_run
	(func() -> void:
		if focus_target.is_inside_tree():
			focus_target.grab_focus()).call_deferred()


func _sky_gradient() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Palette.SKY_TOP)
	g.set_color(1, Palette.SKY_HORIZON)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 8
	tex.height = 256
	return tex


func _mesa_silhouette() -> Control:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var far := Polygon2D.new()
	far.color = Color("a35a38")
	far.polygon = PackedVector2Array([Vector2(0, 760), Vector2(180, 700), Vector2(260, 610), Vector2(520, 600), Vector2(600, 700), Vector2(900, 720), Vector2(1000, 640), Vector2(1260, 630), Vector2(1330, 720), Vector2(1700, 700), Vector2(1780, 600), Vector2(1920, 590), Vector2(1920, 1080), Vector2(0, 1080)])
	holder.add_child(far)
	var near := Polygon2D.new()
	near.color = Color("6b3424")
	near.polygon = PackedVector2Array([Vector2(0, 880), Vector2(300, 860), Vector2(420, 780), Vector2(640, 790), Vector2(760, 880), Vector2(1200, 900), Vector2(1350, 800), Vector2(1600, 810), Vector2(1700, 890), Vector2(1920, 870), Vector2(1920, 1080), Vector2(0, 1080)])
	holder.add_child(near)
	return holder
