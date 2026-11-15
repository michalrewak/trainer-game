class_name Hud
extends CanvasLayer
## HUD czytelny z 3 m: duża moc w watach (środek dół), prędkość (lewy dół), dystans
## (prawy dół), czas do końca (lewa góra), złom (prawa góra). Kadencja dyskretnie pod mocą.
## Statyczne elementy powoli dryfują o kilka pikseli (ochrona OLED przed wypaleniem).

const DRIFT_PX := 8.0
const DRIFT_PERIOD_S := 45.0

var _root: Control
var _time_value: Label
var _scrap_value: Label
var _speed_value: Label
var _distance_value: Label
var _power_value: Label
var _cadence_value: Label
var _hint: Label
var _message: Label
var _popup: Label
var _scrap_panel: Control
var _fuel_value: Label
var _supply_label: Label
var _supply_fill: ColorRect
var _shield_fill: ColorRect
var _combat_row: Control
var _threat_left: Label
var _threat_right: Label
var _blink_t := 0.0

const BAR_WIDTH := 300.0

var _message_left := 0.0
var _persistent_message := ""
var _popup_left := 0.0
var _scrap_pulse := 0.0
var _drift_from := Vector2.ZERO
var _drift_to := Vector2.ZERO
var _drift_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 10
	_build()


func update_from(sim: RunSimulation, power: PowerSource, delta: float) -> void:
	var e := sim.expedition
	_power_value.text = str(roundi(power.get_power_watts()))
	var cadence := roundi(power.get_cadence())
	_cadence_value.text = "%d obr/min" % cadence if cadence > 0 else ""
	_hint.text = power.get_hint()
	_hint.visible = _hint.text != ""
	_speed_value.text = "%d" % roundi(sim.vehicle.speed_kmh())
	_distance_value.text = UiStyle.km(sim.vehicle.distance_m)
	_time_value.text = UiStyle.clock(e.time_left_s())
	_time_value.add_theme_color_override("font_color", Palette.UI_ACCENT if e.time_left_s() <= 60.0 else Palette.UI_TEXT)
	_scrap_value.text = str(e.scrap)
	_fuel_value.text = "PALIWO %d" % e.fuel
	_fuel_value.visible = e.fuel > 0
	_tick_effects(delta)


## Etap 2: zasilanie (moc względem celu), tarcza i ostrzeżenia o ataku z boku.
func update_combat(combat: CombatModel, power_w: float, player_x: float, delta: float) -> void:
	_blink_t += delta
	_combat_row.visible = combat.enabled
	var ratio := power_w / maxf(combat.target_power_w, 1.0)
	_supply_label.text = "CEL %d W · %d%%" % [roundi(combat.target_power_w), roundi(ratio * 100.0)]
	var fill_color := Palette.UI_GOOD if ratio >= 0.97 else (Palette.UI_ACCENT if ratio >= 0.7 else Palette.UI_BAD)
	_supply_fill.color = fill_color
	_supply_fill.size.x = BAR_WIDTH * clampf(ratio, 0.0, 1.0)
	_shield_fill.size.x = BAR_WIDTH * clampf(combat.shield, 0.0, 1.0)
	var left_warn := false
	var right_warn := false
	var left_near := false
	var right_near := false
	for r in combat.live_raiders():
		var on_left := r.x < player_x
		if r.is_threatening():
			if on_left:
				left_warn = true
			else:
				right_warn = true
		elif r.state == RaiderModel.State.APPROACH or r.state == RaiderModel.State.SHADOW:
			if on_left:
				left_near = true
			else:
				right_near = true
	var blink := fmod(_blink_t * 5.0, 1.0) < 0.6
	_set_threat(_threat_left, left_warn, left_near, blink, "◀ !!", "◀ GANG")
	_set_threat(_threat_right, right_warn, right_near, blink, "!! ▶", "GANG ▶")


func _set_threat(l: Label, warn: bool, near: bool, blink: bool, warn_text: String, near_text: String) -> void:
	if warn:
		l.text = warn_text
		l.add_theme_color_override("font_color", Palette.UI_BAD)
		l.visible = blink
	elif near:
		l.text = near_text
		l.add_theme_color_override("font_color", Palette.UI_ACCENT)
		l.visible = true
	else:
		l.visible = false


func show_popup(text: String, color: Color, seconds: float = 1.6) -> void:
	_popup.text = text
	_popup.add_theme_color_override("font_color", color)
	_popup_left = seconds


func flash_hit(lost: int) -> void:
	_popup.text = "-%d ZŁOMU" % lost if lost > 0 else "ZDERZENIE!"
	_popup.add_theme_color_override("font_color", Palette.UI_BAD)
	_popup_left = 1.6


func pulse_scrap() -> void:
	_scrap_pulse = 0.25


func show_message(text: String, seconds: float = 2.5) -> void:
	_message.text = text
	_message_left = seconds


func set_persistent_message(text: String) -> void:
	_persistent_message = text


func _tick_effects(delta: float) -> void:
	if _message_left > 0.0:
		_message_left -= delta
		_message.visible = true
	elif _persistent_message != "":
		_message.text = _persistent_message
		_message.visible = true
	else:
		_message.visible = false
	if _popup_left > 0.0:
		_popup_left -= delta
		_popup.visible = true
		_popup.modulate.a = clampf(_popup_left / 0.5, 0.0, 1.0)
	else:
		_popup.visible = false
	if _scrap_pulse > 0.0:
		_scrap_pulse = maxf(0.0, _scrap_pulse - delta)
	var s := 1.0 + _scrap_pulse * 0.6
	_scrap_panel.pivot_offset = _scrap_panel.size * 0.5
	_scrap_panel.scale = Vector2(s, s)
	# Dryf HUD (OLED).
	_drift_t += delta / DRIFT_PERIOD_S
	if _drift_t >= 1.0:
		_drift_t = 0.0
		_drift_from = _drift_to
		_drift_to = Vector2(_rng.randf_range(-DRIFT_PX, DRIFT_PX), _rng.randf_range(-DRIFT_PX, DRIFT_PX))
	_root.position = _drift_from.lerp(_drift_to, smoothstep(0.0, 1.0, _drift_t))


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Lewa góra: czas do końca.
	var time_box := _stat_panel("DO KOŃCA")
	_time_value = time_box.get_meta("value")
	_place(time_box, Control.PRESET_TOP_LEFT, Vector2(48, 40))

	# Prawa góra: złom.
	var scrap_box := _stat_panel("ZŁOM", Palette.UI_SCRAP)
	_scrap_value = scrap_box.get_meta("value")
	_scrap_panel = scrap_box
	_place(scrap_box, Control.PRESET_TOP_RIGHT, Vector2(-48, 40))
	_fuel_value = UiStyle.label("", 34, Color("ff9a5a"), HORIZONTAL_ALIGNMENT_RIGHT)
	_fuel_value.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fuel_value.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fuel_value.position += Vector2(-60, 205)
	_fuel_value.visible = false
	_root.add_child(_fuel_value)

	# Lewy dół: prędkość.
	var speed_box := _stat_panel("KM/H")
	_speed_value = speed_box.get_meta("value")
	_place(speed_box, Control.PRESET_BOTTOM_LEFT, Vector2(48, -40))

	# Prawy dół: dystans.
	var dist_box := _stat_panel("KM")
	_distance_value = dist_box.get_meta("value")
	_place(dist_box, Control.PRESET_BOTTOM_RIGHT, Vector2(-48, -40))

	# Środek dół: moc – największy element.
	var power_panel := UiStyle.panel(Palette.UI_PANEL)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	power_panel.add_child(col)
	_hint = UiStyle.label("", 34, Palette.UI_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	_power_value = UiStyle.label("0", 168, Palette.UI_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_power_value.custom_minimum_size = Vector2(330, 0)
	row.add_child(_power_value)
	var unit := UiStyle.label("W", 72, Palette.UI_ACCENT)
	row.add_child(unit)
	_cadence_value = UiStyle.label("", 34, Palette.UI_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_cadence_value)
	# Etap 2: zasilanie względem celu i tarcza.
	var combat_col := VBoxContainer.new()
	combat_col.add_theme_constant_override("separation", 6)
	combat_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_supply_label = UiStyle.label("", 28, Palette.UI_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	combat_col.add_child(_supply_label)
	var supply_row := HBoxContainer.new()
	supply_row.alignment = BoxContainer.ALIGNMENT_CENTER
	supply_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var supply_bar := _bar(Palette.UI_GOOD)
	_supply_fill = supply_bar.get_meta("fill")
	supply_row.add_child(supply_bar)
	combat_col.add_child(supply_row)
	var shield_row := HBoxContainer.new()
	shield_row.alignment = BoxContainer.ALIGNMENT_CENTER
	shield_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shield_bar := _bar(Palette.UI_SCRAP)
	_shield_fill = shield_bar.get_meta("fill")
	shield_row.add_child(shield_bar)
	combat_col.add_child(shield_row)
	combat_col.add_child(UiStyle.label("TARCZA", 22, Palette.UI_SCRAP, HORIZONTAL_ALIGNMENT_CENTER))
	_combat_row = combat_col
	col.add_child(combat_col)
	# Moc na górze pośrodku: tam jest tylko niebo, a dół ekranu zajmuje pojazd.
	_place(power_panel, Control.PRESET_CENTER_TOP, Vector2(0, 24))

	# Ostrzeżenia o gangu po bokach ekranu.
	_threat_left = UiStyle.label("", 96, Palette.UI_BAD)
	_threat_left.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_threat_left.grow_vertical = Control.GROW_DIRECTION_BOTH
	_threat_left.position.x += 40
	_threat_left.visible = false
	_root.add_child(_threat_left)
	_threat_right = UiStyle.label("", 96, Palette.UI_BAD, HORIZONTAL_ALIGNMENT_RIGHT)
	_threat_right.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_threat_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_threat_right.grow_vertical = Control.GROW_DIRECTION_BOTH
	_threat_right.position.x -= 40
	_threat_right.visible = false
	_root.add_child(_threat_right)

	# Komunikaty na środku i wyskakujące „-N ZŁOMU”.
	_message = UiStyle.label("", 72, Palette.UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_message.set_anchors_preset(Control.PRESET_CENTER)
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message.grow_vertical = Control.GROW_DIRECTION_BOTH
	_message.position.y -= 40
	_message.visible = false
	_root.add_child(_message)
	_popup = UiStyle.label("", 80, Palette.UI_BAD, HORIZONTAL_ALIGNMENT_CENTER)
	_popup.set_anchors_preset(Control.PRESET_CENTER)
	_popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_popup.grow_vertical = Control.GROW_DIRECTION_BOTH
	_popup.position.y += 70
	_popup.visible = false
	_root.add_child(_popup)


func _bar(color: Color) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(BAR_WIDTH, 16)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.size = Vector2(BAR_WIDTH, 16)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bg)
	var fill := ColorRect.new()
	fill.color = color
	fill.size = Vector2(0, 16)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(fill)
	holder.set_meta("fill", fill)
	return holder


func _stat_panel(caption: String, value_color: Color = Palette.UI_TEXT) -> PanelContainer:
	var p := UiStyle.panel()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(col)
	var value := UiStyle.label("0", 84, value_color, HORIZONTAL_ALIGNMENT_CENTER)
	value.custom_minimum_size = Vector2(220, 0)
	col.add_child(value)
	col.add_child(UiStyle.label(caption, 28, Palette.UI_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	p.set_meta("value", value)
	return p


func _place(c: Control, preset: Control.LayoutPreset, offset: Vector2) -> void:
	_root.add_child(c)
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	match preset:
		Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT:
			c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER_TOP:
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_:
			c.grow_horizontal = Control.GROW_DIRECTION_END
	match preset:
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM:
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_:
			c.grow_vertical = Control.GROW_DIRECTION_END
	c.position += offset
