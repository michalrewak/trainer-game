class_name UpgradeTile
extends Button
## Kafel modułu w warsztacie: nazwa, poziomy jako klocki (kupione, dostępne, zablokowane
## przez podwozie) i koszt następnego poziomu w kolorze mówiącym, czy cię stać.

enum State { BUY, POOR, CAPPED, MAXED }

var title := ""
var level := 0
var max_level := 1
var cap := 1
var cost_text := ""
var state: State = State.POOR


func _init() -> void:
	text = ""
	custom_minimum_size = Vector2(290, 88)
	focus_mode = Control.FOCUS_ALL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func set_data(p_title: String, p_level: int, p_max_level: int, p_cap: int, p_cost_text: String, p_state: State) -> void:
	title = p_title
	level = p_level
	max_level = p_max_level
	cap = p_cap
	cost_text = p_cost_text
	state = p_state
	queue_redraw()


func _draw() -> void:
	var font := UiStyle.font()
	var x := 24.0
	var dim := state == State.POOR or state == State.CAPPED
	var name_color := Color.WHITE if has_focus() else (Palette.UI_TEXT.darkened(0.25) if dim else Palette.UI_TEXT)
	draw_string(font, Vector2(x, 32.0), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 8.0, 28, name_color)
	# Poziomy: pełny klocek = kupiony, ramka = do kupienia, przekreślony = wymaga podwozia.
	for i in max_level:
		var r := Rect2(x + i * 26.0, 41.0, 20.0, 13.0)
		if i < level:
			draw_rect(r, Palette.UI_ACCENT)
		elif i < cap:
			draw_rect(r, Color(1, 1, 1, 0.75), false, 2.0)
		else:
			draw_rect(r, Color(1, 1, 1, 0.22), false, 2.0)
			draw_line(r.position, r.end, Color(1, 1, 1, 0.22), 2.0)
	var cost_color := Palette.UI_GOOD
	match state:
		State.POOR:
			cost_color = Color("d08a6a")
		State.CAPPED:
			cost_color = Color("c9a23a")
		State.MAXED:
			cost_color = Palette.UI_SCRAP
	draw_string(font, Vector2(x, 80.0), cost_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 8.0, 24, cost_color)
