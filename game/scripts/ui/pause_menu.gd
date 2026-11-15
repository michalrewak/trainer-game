class_name PauseMenu
extends CanvasLayer
## Pauza wyprawy (Start / Esc). Działa przy zatrzymanym drzewie sceny.
## „Zakończ wyprawę” zapisuje zebrany dotąd złom – każda sesja kończy się postępem.

signal resume_requested
signal end_requested

var _reason: Label
var _resume: Button
var _end: Button
var _opened_at := 0


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	_build()


func open(reason: String = "") -> void:
	_reason.text = reason
	_reason.visible = reason != ""
	visible = true
	_opened_at = Time.get_ticks_msec()
	_resume.grab_focus.call_deferred()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# Krótka blokada, żeby to samo wciśnięcie Start nie zamknęło od razu pauzy.
	if Time.get_ticks_msec() - _opened_at < 250:
		return
	if event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		resume_requested.emit()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiStyle.menu_theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 28)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	col.add_child(UiStyle.label("PAUZA", 120, Palette.UI_ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	_reason = UiStyle.label("", 44, Palette.UI_BAD, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_reason)
	_resume = UiStyle.button("JEDŹ DALEJ")
	_resume.pressed.connect(func() -> void: resume_requested.emit())
	col.add_child(_resume)
	_end = UiStyle.button("ZAKOŃCZ WYPRAWĘ (zapisz złom)")
	_end.pressed.connect(func() -> void: end_requested.emit())
	col.add_child(_end)
	col.add_child(UiStyle.label("Start / B / Esc – wróć do jazdy   ·   A – wybierz", 32, Palette.UI_DIM, HORIZONTAL_ALIGNMENT_CENTER))
