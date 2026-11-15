extends TestCase
## Testy widoków w drzewie sceny (headless) – regresje znalezione w review etapu 1.


func test_buggy_visible_again_after_hit_flash() -> void:
	# Budujemy węzeł jawnie (w trakcie _initialize drzewo nie wywołuje jeszcze _ready).
	var view := BuggyView.new()
	view._ready()
	var sim := RunSimulation.new(60.0, 1)
	view.on_hit()
	var t := 0.0
	while t < 2.0:
		view.sync(sim, 85.0, 200.0, 1.0 / 60.0)
		t += 1.0 / 60.0
	var body := view.get_node("Body") as Node3D
	assert_true(body.visible, "pojazd widoczny po zakończeniu migania")
	view.free()


func test_menu_actions_have_pad_buttons() -> void:
	var has_a := false
	for e in InputMap.action_get_events(&"ui_accept"):
		if e is InputEventJoypadButton and e.button_index == JOY_BUTTON_A:
			has_a = true
	var has_b := false
	for e in InputMap.action_get_events(&"ui_cancel"):
		if e is InputEventJoypadButton and e.button_index == JOY_BUTTON_B:
			has_b = true
	assert_true(has_a, "A zatwierdza w menu")
	assert_true(has_b, "B cofa w menu")
