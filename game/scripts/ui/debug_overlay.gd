class_name DebugOverlay
extends CanvasLayer
## Podgląd wejść (F3 albo Back/Select na padzie): nazwa pada, surowe osie (RT, LT, lewa
## gałka), ostatnio wciśnięty przycisk, siła akcji z Input Map, FPS. Pomaga sprawdzić,
## czy GameSir w danym trybie Bluetooth daje analogowy trigger.

var _label: Label
var _last_button := "-"


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var panel := UiStyle.panel(Palette.UI_PANEL_STRONG)
	panel.position = Vector2(40, 200)
	add_child(panel)
	_label = UiStyle.label("", 28, Palette.UI_TEXT)
	panel.add_child(_label)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		_last_button = "%d (%s)" % [event.button_index, _button_name(event.button_index)]
	if event.is_action_pressed(&"debug_overlay"):
		visible = not visible


func _process(_delta: float) -> void:
	if not visible:
		return
	var lines: Array[String] = []
	lines.append("FPS: %d" % Engine.get_frames_per_second())
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		lines.append("Pad: brak (sterowanie klawiaturą)")
	for id in pads:
		lines.append("Pad %d: %s" % [id, Input.get_joy_name(id)])
		lines.append("  RT (oś 5): %.2f   LT (oś 4): %.2f" % [Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT), Input.get_joy_axis(id, JOY_AXIS_TRIGGER_LEFT)])
		lines.append("  Lewa gałka X/Y: %.2f / %.2f" % [Input.get_joy_axis(id, JOY_AXIS_LEFT_X), Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)])
		lines.append("  Prawa gałka X/Y: %.2f / %.2f (etap 2)" % [Input.get_joy_axis(id, JOY_AXIS_RIGHT_X), Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y)])
	lines.append("Ostatni przycisk: %s" % _last_button)
	lines.append("Akcje: moc %.2f  pas L %.2f  pas P %.2f" % [
		Input.get_action_strength(&"power_trigger"),
		Input.get_action_raw_strength(&"lane_left"),
		Input.get_action_raw_strength(&"lane_right")])
	lines.append("F3 / Back – zamknij")
	_label.text = "\n".join(lines)


static func _button_name(index: int) -> String:
	match index:
		JOY_BUTTON_A: return "A / dolny"
		JOY_BUTTON_B: return "B / prawy"
		JOY_BUTTON_X: return "X / lewy"
		JOY_BUTTON_Y: return "Y / górny"
		JOY_BUTTON_BACK: return "Back/Select"
		JOY_BUTTON_GUIDE: return "Guide/Home"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_LEFT_STICK: return "L3"
		JOY_BUTTON_RIGHT_STICK: return "R3"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_DPAD_UP: return "krzyżak góra"
		JOY_BUTTON_DPAD_DOWN: return "krzyżak dół"
		JOY_BUTTON_DPAD_LEFT: return "krzyżak lewo"
		JOY_BUTTON_DPAD_RIGHT: return "krzyżak prawo"
	return "?"
