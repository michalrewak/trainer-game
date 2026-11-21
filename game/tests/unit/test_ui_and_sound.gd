extends TestCase
## Nowy HUD (deska rozdzielcza, passa, zlecenia), kafle warsztatu i dźwięk – testy headless.


func test_all_sounds_are_generated() -> void:
	var streams := Sfx.build_streams()
	for sound: String in ["pickup", "big", "shot", "hit", "boom", "warn", "boost", "tier", "lost", "fanfare", "crate", "radio"]:
		assert_true(streams.has(sound), "jest próbka %s" % sound)
		var wav := streams[sound] as AudioStreamWAV
		assert_true(wav.data.size() > 1000, "%s ma dane (%d bajtów)" % [sound, wav.data.size()])
		assert_true(wav.get_length() < 1.0, "%s jest krótkim efektem" % sound)
	# Próbka nie jest ciszą.
	var data := (streams["pickup"] as AudioStreamWAV).data
	var peak := 0
	for i in range(0, data.size() - 1, 2):
		peak = maxi(peak, absi(data.decode_s16(i)))
	assert_true(peak > 8000, "brzdęk zębatki jest słyszalny (szczyt %d)" % peak)


func test_sfx_stays_silent_when_disabled_or_unknown() -> void:
	var sfx := Sfx.new()
	sfx.enabled = false
	sfx.play("pickup")
	sfx.pickup(2)
	sfx.enabled = true
	sfx.play("nie_ma_takiego")
	sfx.free()
	assert_true(true, "bez odtwarzaczy i bez błędów")


func test_hud_builds_and_shows_streak_contracts_and_convoy() -> void:
	var hud := Hud.new()
	hud._ready()
	var sim := RunSimulation.new(600.0, 2)
	sim.contracts.setup(10.0, 200.0, 2, {"combat": true})
	var power := ScriptedPowerSource.new(200.0, 0.0)
	power.update(1.0)
	for i in 6:
		sim.streak.add(1)
	sim.step(0.1, 200.0)
	hud.ftp_w = 200.0
	hud.update_from(sim, power, 0.1)
	hud.update_combat(sim.combat, 200.0, 0.0, 0.1)
	assert_eq(hud._streak_label.text, "×1.1", "mnożnik passy przy złomie")
	assert_true(hud._contract_box.visible, "zlecenia widoczne")
	assert_true(hud._contract_labels[0].text.begins_with("□ "), "zlecenie w toku ma pustą kratkę")
	assert_eq(hud._power_value.text, "200")
	assert_true(hud._zone_label.text.contains("100% FTP"), "procent FTP przy mocy: %s" % hud._zone_label.text)
	assert_true(hud._supply_label.text.begins_with("CEL "))
	sim.contracts.contracts[0]["done"] = true
	hud.update_from(sim, power, 0.1)
	assert_true(hud._contract_labels[0].text.begins_with("■ "), "wykonane zlecenie ma pełną kratkę")
	hud.update_convoy({"title": "CYSTERNA", "status": "PRZYSPIESZ", "rel": -20.0, "window": 1})
	assert_true(hud._convoy_box.visible)
	hud.update_convoy({})
	assert_false(hud._convoy_box.visible)
	hud.update_challenge("KONWÓJ UCIEKA", Palette.UI_ACCENT)
	assert_true(hud._status_box.visible, "pasek stanu pokazuje bieżące zadanie")
	hud.update_challenge("", Palette.UI_ACCENT)
	hud.say(Chatter.make(Chatter.MECH, "Test radia."), 1)
	assert_true(hud.head_busy())
	hud.pulse_streak()
	hud.show_popup("O WŁOS!", Palette.UI_SCRAP, 0.5)
	hud.update_from(sim, power, 0.1)
	hud.free()


func test_gauges_accept_values() -> void:
	var gauge := BandGauge.new()
	gauge.size = Vector2(380, 40)
	gauge.set_values(210.0, 200.0, 0.05, 0.05, Palette.UI_GOOD)
	assert_near(gauge.target_w, 200.0, 1e-6)
	gauge.free()
	var strip := ZoneStrip.new()
	strip.set_power(200.0, 200.0)
	assert_eq(strip.zone, 3, "100% FTP = Z4")
	assert_between(strip.within, 0.5, 0.8, "bliżej górnej granicy strefy")
	strip.set_power(0.0, 200.0)
	assert_eq(strip.zone, -1, "bez mocy żadna strefa nie świeci")
	strip.free()


func test_upgrade_tile_holds_state() -> void:
	var tile := UpgradeTile.new()
	tile.set_data("Dopalacz", 1, 3, 2, "520 złomu + 5 paliwa", UpgradeTile.State.POOR)
	assert_eq(tile.text, "", "kafel rysuje treść sam")
	assert_eq(tile.level, 1)
	assert_eq(tile.cap, 2)
	assert_eq(tile.state, UpgradeTile.State.POOR)
	assert_true(tile.custom_minimum_size.y >= 80.0, "kafel ma wysokość do czytania z daleka")
	tile.free()


func test_menu_style_has_plates_and_focus() -> void:
	var theme := UiStyle.menu_theme()
	var normal := theme.get_stylebox("normal", "Button") as StyleBoxFlat
	var focus := theme.get_stylebox("focus", "Button") as StyleBoxFlat
	assert_eq(normal.corner_detail, 1, "ścięte rogi, nie zaokrąglone")
	assert_true(focus.border_width_left > normal.border_width_left, "fokus ma grubszy pasek akcentu")
	assert_true(focus.bg_color != normal.bg_color, "fokus zmienia kolor płyty")
	var section := UiStyle.section("WARSZTAT")
	assert_eq(section.get_child_count(), 3)
	section.free()
	var chip := UiStyle.chip("ZŁOM", Palette.UI_SCRAP)
	assert_true(chip.has_meta("value"))
	chip.free()
