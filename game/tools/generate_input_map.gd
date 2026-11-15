extends SceneTree
## Generuje sekcję [input] w project.godot (standardowy Input Map Godota – widoczny
## i edytowalny w edytorze: Projekt > Ustawienia projektu > Mapa wejścia).
## Uruchom po zmianie mapowania:
##   godot --headless --path game --script res://tools/generate_input_map.gd
##
## Pad w standardowym układzie Godota (SDL): A = dolny przycisk, B = prawy, X = lewy, Y = górny.
## Zarezerwowane na etap 2 (celowo NIE mapowane teraz): prawa gałka (celowanie), strzał.


func _initialize() -> void:
	var actions := {
		# Menu: w Godot 4.7 domyślne ui_accept/ui_cancel nie mają przycisków pada – dodajemy A/B.
		"ui_accept": _action(0.5, [_key(KEY_ENTER), _key(KEY_KP_ENTER), _key(KEY_SPACE), _button(JOY_BUTTON_A)]),
		"ui_cancel": _action(0.5, [_key(KEY_ESCAPE), _button(JOY_BUTTON_B)]),
		# Moc (symulacja na padzie): prawy trigger analogowy 0..1 -> 0..350 W.
		"power_trigger": _action(0.05, [_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)]),
		# Tempomat na LB: lewy palec wskazujący jest wolny, prawy trzyma RT, kciuki zostają
		# na gałkach (etap 2: celowanie). Ramiona nie zamieniają się między trybami pada.
		"cruise_toggle": _action(0.5, [_key(KEY_C), _key(KEY_SPACE), _button(JOY_BUTTON_LEFT_SHOULDER)]),
		# +/-10 W (klawiatura i krzyżak góra/dół – działa też, gdy trigger pada jest cyfrowy).
		"power_up": _action(0.5, [_key(KEY_W), _key(KEY_UP), _button(JOY_BUTTON_DPAD_UP)]),
		"power_down": _action(0.5, [_key(KEY_S), _key(KEY_DOWN), _button(JOY_BUTTON_DPAD_DOWN)]),
		# Zmiana pasa: krzyżak lewo/prawo, lewa gałka, A/D, strzałki.
		"lane_left": _action(0.2, [_key(KEY_A), _key(KEY_LEFT), _button(JOY_BUTTON_DPAD_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)]),
		"lane_right": _action(0.2, [_key(KEY_D), _key(KEY_RIGHT), _button(JOY_BUTTON_DPAD_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)]),
		# Etap 2 – wieżyczka: prawa gałka celuje (bez wychylenia = auto-cel), LT strzela.
		# RT strzela dodatkowo dopiero, gdy moc daje trenażer (RT jest wtedy wolny) –
		# dokłada to kod przy wyborze źródła mocy, nie ta mapa.
		"aim_left": _action(0.25, [_axis(JOY_AXIS_RIGHT_X, -1.0)]),
		"aim_right": _action(0.25, [_axis(JOY_AXIS_RIGHT_X, 1.0)]),
		"aim_up": _action(0.25, [_axis(JOY_AXIS_RIGHT_Y, -1.0)]),
		"aim_down": _action(0.25, [_axis(JOY_AXIS_RIGHT_Y, 1.0)]),
		"fire": _action(0.3, [_key(KEY_F), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)]),
		# Pauza / menu wyprawy.
		"pause": _action(0.5, [_key(KEY_ESCAPE), _key(KEY_P), _button(JOY_BUTTON_START)]),
		# Okno: pełny ekran i przeniesienie na kolejny ekran (laptop/PC + telewizor).
		"toggle_fullscreen": _action(0.5, [_key(KEY_F11), _key(KEY_ENTER, true)]),
		"next_screen": _action(0.5, [_key(KEY_F10)]),
		# Podgląd wejść pada (diagnostyka).
		"debug_overlay": _action(0.5, [_key(KEY_F3), _button(JOY_BUTTON_BACK)]),
	}
	for action_name in actions:
		ProjectSettings.set_setting("input/" + action_name, actions[action_name])
	var err := ProjectSettings.save()
	print("Zapisano mapę wejść (%d akcji): %s" % [actions.size(), error_string(err)])
	quit(0 if err == OK else 1)


func _action(deadzone: float, events: Array) -> Dictionary:
	return {"deadzone": deadzone, "events": events}


func _key(keycode: Key, alt: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.device = -1
	e.physical_keycode = keycode
	e.alt_pressed = alt
	return e


func _button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = -1
	e.button_index = button
	return e


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = -1
	e.axis = axis
	e.axis_value = value
	return e
