extends Control
## Podsumowanie wyprawy: zebrany złom (największy), statystyki, stan magazynu.
## Jeden przycisk, żeby od razu jechać dalej.


func _ready() -> void:
	theme = UiStyle.menu_theme()
	var s: Dictionary = App.last_summary
	var bg := ColorRect.new()
	bg.color = Color("1c1410")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 22)
	center.add_child(col)

	var completed := bool(s.get("completed", false))
	col.add_child(UiStyle.label("WYPRAWA ZAKOŃCZONA" if completed else "WYPRAWA PRZERWANA", 84, Palette.UI_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiStyle.label("+%d ZŁOMU" % int(s.get("scrap", 0)), 110, Palette.UI_SCRAP, HORIZONTAL_ALIGNMENT_CENTER))
	# Trening: to, po co naprawdę wsiadasz na trenażer.
	col.add_child(UiStyle.label("TRENING:  NP %d W  ·  IF %.2f  ·  TSS %d  ·  %d kJ  ·  maks. %d W" % [int(s.get("np_w", 0)), float(s.get("intensity_factor", 0.0)), roundi(float(s.get("tss", 0.0))), int(s.get("energy_kj", 0)), int(s.get("max_power_w", 0))], 40, Palette.UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(_zone_bar(s.get("zones_s", [])))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 60)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	var stats := [
		["Dystans", "%s km" % UiStyle.km(float(s.get("distance_m", 0)))],
		["Czas", UiStyle.clock(float(s.get("duration_s", 0)))],
		["Śr. moc", "%d W" % int(s.get("avg_power_w", 0))],
		["Śr. prędkość", "%.1f km/h" % float(s.get("avg_speed_kmh", 0.0))],
		["Zderzenia", str(int(s.get("collisions", 0)))],
		["Paliwo", "+%d" % int(s.get("fuel", 0))],
		["Rozbite gangi", str(int(s.get("raiders_destroyed", 0)))],
		["Wyzwania", str(int(s.get("challenges_completed", 0)))],
		["Napady", str(int(s.get("raids_done", 0)))],
	]
	if s.has("workout"):
		stats.append(["Trening", str(s["workout"])])
		stats.append(["W widełkach", "%d%% czasu" % int(s.get("workout_in_band_pct", 0))])
	for pair in stats:
		grid.add_child(UiStyle.label(pair[0], 36, Palette.UI_DIM, HORIZONTAL_ALIGNMENT_RIGHT))
		grid.add_child(UiStyle.label(pair[1], 44, Palette.UI_TEXT))

	var before := App.last_total_before
	var after := App.progress.total_scrap()
	col.add_child(UiStyle.label("Złom w magazynie: %d → %d   ·   Paliwo: %d" % [before, after, App.progress.fuel()], 44, Palette.UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiStyle.label("Praca łącznie: %d kJ   ·   %s" % [App.progress.total_energy_kj(), App.progress.next_goal()], 36, Palette.UI_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	if not bool(s.get("saved", true)):
		col.add_child(UiStyle.label("Uwaga: nie udało się zapisać postępu!", 40, Palette.UI_BAD, HORIZONTAL_ALIGNMENT_CENTER))

	var again := UiStyle.button("JESZCZE RAZ (%s)" % _minutes_label(App.selected_minutes))
	again.pressed.connect(func() -> void: App.start_run(App.selected_minutes))
	var menu := UiStyle.button("GARAŻ")
	menu.pressed.connect(func() -> void: App.go_to_start())
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 30)
	buttons.add_child(again)
	buttons.add_child(menu)
	col.add_child(buttons)
	col.add_child(UiStyle.label("„%s”" % Lore.slogan(App.progress.runs().size()), 30, Palette.UI_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	again.grab_focus.call_deferred()
	if App.options.screenshot_dir != "" and not App.is_headless():
		await get_tree().create_timer(1.0).timeout
		await Screenshot.capture(self, App.options.screenshot_dir + "/summary.png")
		get_tree().quit()


## Pasek czasu w strefach mocy Z1–Z7 z legendą.
func _zone_bar(zones: Variant) -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	var total := 0.0
	var secs: Array[float] = []
	if zones is Array:
		for z: Variant in zones:
			secs.append(float(z))
			total += float(z)
	if total <= 0.0:
		return box
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 0)
	var legend: Array[String] = []
	for i in mini(secs.size(), TrainingMetrics.ZONE_COLORS.size()):
		if secs[i] <= 0.0:
			continue
		var seg := ColorRect.new()
		seg.color = TrainingMetrics.ZONE_COLORS[i]
		seg.custom_minimum_size = Vector2(maxf(4.0, 1100.0 * secs[i] / total), 22)
		bar.add_child(seg)
		legend.append("Z%d %s" % [i + 1, UiStyle.clock(secs[i])])
	box.add_child(bar)
	box.add_child(UiStyle.label("Czas w strefach:  " + "   ".join(legend), 28, Palette.UI_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	return box


static func _minutes_label(minutes: float) -> String:
	return "%d min" % roundi(minutes) if minutes >= 1.0 else "%d s" % roundi(minutes * 60.0)
