extends Control
## Podsumowanie wyprawy: zebrany złom (największy), po lewej TRENING (NP, IF, TSS, strefy,
## najlepsze odcinki mocy, nowe rekordy), po prawej WYPRAWA (zlecenia i statystyki),
## na dole stan magazynu i najbliższy cel. Jeden przycisk, żeby od razu jechać dalej.

const GOLD := Color("ffd21a")


func _ready() -> void:
	theme = UiStyle.menu_theme()
	var s: Dictionary = App.last_summary
	add_child(UiStyle.backdrop())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	center.add_child(col)

	var completed := bool(s.get("completed", false))
	col.add_child(UiStyle.label("DOTARŁEŚ DO OSADY" if completed else "POWRÓT PRZED CZASEM", 58, Palette.UI_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiStyle.label("+%d ZŁOMU" % int(s.get("scrap", 0)), 96, Palette.UI_SCRAP, HORIZONTAL_ALIGNMENT_CENTER))

	var panels := HBoxContainer.new()
	panels.alignment = BoxContainer.ALIGNMENT_CENTER
	panels.add_theme_constant_override("separation", 20)
	col.add_child(panels)
	panels.add_child(_training_panel(s))
	panels.add_child(_run_panel(s))

	var before := App.last_total_before
	var after := App.progress.total_scrap()
	col.add_child(UiStyle.label("Magazyn: złom %d → %d   ·   paliwo %d   ·   załoga %d" % [before, after, App.progress.fuel(), App.progress.crew()], 34, Palette.UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UiStyle.label("Praca łącznie: %d kJ   ·   %s" % [App.progress.total_energy_kj(), App.progress.next_goal()], 30, Palette.UI_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	if not bool(s.get("saved", true)):
		col.add_child(UiStyle.label("Uwaga: nie udało się zapisać postępu!", 40, Palette.UI_BAD, HORIZONTAL_ALIGNMENT_CENTER))

	var again := UiStyle.button("JESZCZE RAZ (%s)" % _minutes_label(App.selected_minutes), 560)
	again.custom_minimum_size.y = 84
	again.pressed.connect(func() -> void: App.start_run(App.selected_minutes))
	var menu := UiStyle.button("GARAŻ", 360)
	menu.custom_minimum_size.y = 84
	menu.pressed.connect(func() -> void: App.go_to_start())
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	buttons.add_child(again)
	buttons.add_child(menu)
	col.add_child(buttons)
	col.add_child(UiStyle.label("„%s”" % Lore.slogan(App.progress.runs().size()), 26, Palette.UI_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	again.grab_focus.call_deferred()
	if App.options.screenshot_dir != "" and not App.is_headless():
		await get_tree().create_timer(1.0).timeout
		await Screenshot.capture(self, App.options.screenshot_dir + "/summary.png")
		get_tree().quit()


## Trening: to, po co naprawdę wsiadasz na trenażer.
func _training_panel(s: Dictionary) -> Control:
	var plate := UiStyle.plate(UiStyle.STEEL_MENU, Palette.UI_GOOD)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size = Vector2(840, 0)
	plate.add_child(col)
	col.add_child(UiStyle.section("TRENING"))
	col.add_child(UiStyle.label("NP %d W   ·   IF %.2f   ·   TSS %d   ·   %d kJ" % [int(s.get("np_w", 0)), float(s.get("intensity_factor", 0.0)), roundi(float(s.get("tss", 0.0))), int(s.get("energy_kj", 0))], 40, Palette.UI_TEXT))
	col.add_child(_zone_bar(s.get("zones_s", [])))
	var best: Array[String] = []
	for i in TrainingMetrics.BEST_KEYS.size():
		var w := int(s.get(TrainingMetrics.BEST_KEYS[i], 0))
		best.append("%s %s" % [TrainingMetrics.BEST_NAMES[i], "%d W" % w if w > 0 else "—"])
	col.add_child(UiStyle.label("Najlepsze odcinki:  " + "   ·   ".join(best), 28, Palette.UI_TEXT))
	var broken: Array = s.get("new_records", [])
	if broken.is_empty():
		col.add_child(UiStyle.label("Bez nowych rekordów. Poprzeczka wisi – następnym razem.", 26, Palette.UI_DIM))
	for key: String in broken:
		col.add_child(UiStyle.label("★ NOWY REKORD  –  %s" % ProgressStore.record_text(key, float(s.get(key, 0.0))), 32, GOLD))
	return plate


## Wyprawa: zlecenia i statystyki jazdy.
func _run_panel(s: Dictionary) -> Control:
	var plate := UiStyle.plate(UiStyle.STEEL_MENU, Palette.UI_ACCENT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size = Vector2(840, 0)
	plate.add_child(col)
	col.add_child(UiStyle.section("ZLECENIA"))
	var contracts: Array = s.get("contracts", [])
	if contracts.is_empty():
		col.add_child(UiStyle.label("Brak zleceń w tej wyprawie.", 26, Palette.UI_DIM))
	for c: Variant in contracts:
		var done := bool((c as Dictionary).get("done", false))
		var text := "%s %s" % ["■" if done else "□", str((c as Dictionary).get("text", ""))]
		if done:
			text += "   +%d złomu" % int((c as Dictionary).get("reward_scrap", 0))
		col.add_child(UiStyle.label(text, 28, Palette.UI_GOOD if done else Palette.UI_DIM))
	col.add_child(UiStyle.section("WYPRAWA"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 0)
	col.add_child(grid)
	var stats := [
		["Dystans", "%s km" % UiStyle.km(float(s.get("distance_m", 0)))],
		["Czas", UiStyle.clock(float(s.get("duration_s", 0)))],
		["Śr. moc", "%d W" % int(s.get("avg_power_w", 0))],
		["Śr. prędkość", "%.1f km/h" % float(s.get("avg_speed_kmh", 0.0))],
		["Passa maks.", "×%.1f" % float(s.get("best_streak", 1.0))],
		["Uniki o włos", str(int(s.get("near_misses", 0)))],
		["Rozbite gangi", str(int(s.get("raiders_destroyed", 0)))],
		["Zderzenia", str(int(s.get("collisions", 0)))],
		["Paliwo", "+%d" % int(s.get("fuel", 0))],
		["Skrzynie", str(int(s.get("crates_opened", 0)))],
	]
	if int(s.get("raids_done", 0)) > 0:
		stats.append(["Napady", str(int(s.get("raids_done", 0)))])
	if int(s.get("challenges_completed", 0)) > 0:
		stats.append(["Wyzwania", str(int(s.get("challenges_completed", 0)))])
	if int(s.get("convoys_captured", 0)) + int(s.get("convoys_lost", 0)) > 0:
		stats.append(["Konwoje", "%d z %d" % [int(s.get("convoys_captured", 0)), int(s.get("convoys_captured", 0)) + int(s.get("convoys_lost", 0))]])
	if int(s.get("pedalers_freed", 0)) > 0:
		stats.append(["Uwolnieni", "+%d" % int(s.get("pedalers_freed", 0))])
	if s.has("workout"):
		stats.append(["Trening", str(s["workout"])])
		stats.append(["W widełkach", "%d%% czasu" % int(s.get("workout_in_band_pct", 0))])
	for pair: Array in stats:
		grid.add_child(UiStyle.label(pair[0], 26, Palette.UI_DIM, HORIZONTAL_ALIGNMENT_RIGHT))
		grid.add_child(UiStyle.label(pair[1], 30, Palette.UI_TEXT))
	return plate


## Pasek czasu w strefach mocy Z1–Z7 z legendą.
func _zone_bar(zones: Variant) -> Control:
	var box := VBoxContainer.new()
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
	bar.add_theme_constant_override("separation", 0)
	var legend: Array[String] = []
	for i in mini(secs.size(), TrainingMetrics.ZONE_COLORS.size()):
		if secs[i] <= 0.0:
			continue
		var seg := ColorRect.new()
		seg.color = TrainingMetrics.ZONE_COLORS[i]
		seg.custom_minimum_size = Vector2(maxf(4.0, 800.0 * secs[i] / total), 22)
		bar.add_child(seg)
		legend.append("Z%d %s" % [i + 1, UiStyle.clock(secs[i])])
	box.add_child(bar)
	box.add_child(UiStyle.label("Czas w strefach:  " + "   ".join(legend), 24, Palette.UI_DIM))
	return box


static func _minutes_label(minutes: float) -> String:
	return "%d min" % roundi(minutes) if minutes >= 1.0 else "%d s" % roundi(minutes * 60.0)
