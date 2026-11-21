class_name Hud
extends CanvasLayer
## HUD czytelny z 3 m. Układ:
## - dół, środek: deska rozdzielcza – prędkość, MOC (największa), pasek stref Z1–Z7,
##   wskaźnik widełek celu, zasilanie, kondensatory, moc na kołach i dopalacz;
## - lewa góra: czas i dystans, pod spodem panel konwoju albo treningu;
## - prawa góra: złom z mnożnikiem passy, zlecenia, gadająca głowa;
## - środek góry: tylko wąski pasek stanu – horyzont i droga przed pojazdem są odsłonięte.
## Statyczne elementy powoli dryfują o kilka pikseli (ochrona OLED przed wypaleniem).

## FTP gracza – do pokazania procentu FTP i strefy mocy.
var ftp_w := 200.0

const DRIFT_PX := 8.0
const DRIFT_PERIOD_S := 45.0
const BAR_WIDTH := 178.0
## Kolor ładunku kondensatorów: zimny, elektryczny błękit (złom jest turkusowy).
const CAPACITOR_COLOR := Color("9fd8ff")

var _root: Control
var _time_value: Label
var _scrap_value: Label
var _speed_value: Label
var _distance_value: Label
var _power_value: Label
var _cadence_value: Label
var _zone_label: Label
var _zone_strip: ZoneStrip
var _wheel_label: Label
var _band_gauge: BandGauge
var _hint: Label
var _status_box: Control
var _message: Label
var _popup: Label
var _scrap_panel: Control
var _streak_label: Label
var _streak_fill: ColorRect
var _streak_time: ColorRect
var _fuel_value: Label
var _speed_caption: Label
var _challenge_label: Label
var _contract_box: Control
var _contract_labels: Array[Label] = []
var _scout_card: PanelContainer
var _scout_title: Label
var _scout_lines: Label
var _scout_side := 0
var _convoy_box: PanelContainer
var _convoy_title: Label
var _convoy_status: Label
var _convoy_diagram: ConvoyDiagram
var _head: TalkingHead
var _workout_box: Control
var _profile: WorkoutProfile
var _workout_title: Label
var _step_label: Label
var _next_label: Label
var _safe_label: Label
var _supply_label: Label
var _supply_fill: ColorRect
var _capacitor_fill: ColorRect
var _capacitor_caption: Label
var _combat_row: Control
var _target_col: Control
var _threat_left: Label
var _threat_right: Label
var _blink_t := 0.0

var _message_left := 0.0
var _persistent_message := ""
var _popup_left := 0.0
var _scrap_pulse := 0.0
var _streak_pulse := 0.0
var _drift_from := Vector2.ZERO
var _drift_to := Vector2.ZERO
var _drift_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	layer = 10
	_build()


func update_from(sim: RunSimulation, power: PowerSource, delta: float) -> void:
	var e := sim.expedition
	var pw := power.get_power_watts()
	_power_value.text = str(roundi(pw))
	var cadence := roundi(power.get_cadence())
	_cadence_value.text = "%d obr/min" % cadence if cadence > 0 else ""
	# To, co ważne treningowo: procent FTP i strefa mocy, w kolorze strefy.
	_zone_strip.set_power(pw, ftp_w)
	if pw >= 5.0:
		var zone := TrainingMetrics.zone_index(pw, ftp_w)
		_zone_label.text = "%d%% FTP\n%s" % [roundi(pw / ftp_w * 100.0), TrainingMetrics.ZONE_NAMES[zone]]
		_zone_label.add_theme_color_override("font_color", TrainingMetrics.ZONE_COLORS[zone].lerp(Palette.UI_TEXT, 0.35))
	else:
		_zone_label.text = ""
	# Układ napędowy: co z mocy z nóg trafia na koła i ile ładunków ma dopalacz.
	var train := sim.power_train
	var pips := "■".repeat(train.charges) + "□".repeat(maxi(0, train.max_charges - train.charges))
	if train.is_boosting():
		_wheel_label.text = "DOPALACZ +%d%%  ·  %d s  ·  NA KOŁACH %d W" % [roundi(train.boost_gain * 100.0), ceili(train.boost_left_s), roundi(sim.last_wheel_power_w)]
		_wheel_label.add_theme_color_override("font_color", Color("ff9a4a"))
	else:
		_wheel_label.text = "NA KOŁACH %d W (×%.2f)  ·  DOPALACZ %s" % [roundi(sim.last_wheel_power_w), sim.power_multiplier(), pips]
		_wheel_label.add_theme_color_override("font_color", Palette.UI_DIM)
	_hint.text = power.get_hint()
	_hint.visible = _hint.text != ""
	_status_box.visible = _hint.visible or _challenge_label.visible
	_speed_value.text = "%d" % roundi(sim.vehicle.speed_kmh())
	var grade_pct := roundi(sim.vehicle.grade * 100.0)
	if grade_pct > 0:
		_speed_caption.text = "KM/H  ↑ %d%%" % grade_pct
	elif grade_pct < 0:
		_speed_caption.text = "KM/H  ↓ %d%%" % absi(grade_pct)
	else:
		_speed_caption.text = "KM/H"
	_distance_value.text = "%s km" % UiStyle.km(sim.vehicle.distance_m)
	_time_value.text = UiStyle.clock(e.time_left_s())
	_time_value.add_theme_color_override("font_color", Palette.UI_ACCENT if e.time_left_s() <= 60.0 else Palette.UI_TEXT)
	_scrap_value.text = str(e.scrap)
	var extras: Array[String] = []
	if e.fuel > 0:
		extras.append("PALIWO %d" % e.fuel)
	if sim.ram_cooldown_s > 0.0:
		extras.append("TARAN gotowy" if sim.ram_ready() else "TARAN %d s" % ceili(sim.ram_left_s))
	_fuel_value.text = "   ·   ".join(extras)
	_fuel_value.visible = not extras.is_empty()
	_update_streak(sim.streak)
	_update_contracts(sim.contracts)
	_tick_effects(delta)


## Passa: mnożnik złomu, postęp do następnego progu i zegar do jej utraty.
func _update_streak(streak: Streak) -> void:
	var active := streak.points > 0
	_streak_label.text = "×%.1f" % streak.multiplier()
	_streak_label.add_theme_color_override("font_color", Palette.UI_ACCENT if streak.tier() > 0 else Palette.UI_DIM)
	_streak_fill.size.x = 120.0 * streak.progress_to_next()
	_streak_time.size.x = 120.0 * streak.time_ratio()
	# Zegar czerwienieje, gdy passa zaraz przepadnie.
	_streak_time.color = Palette.UI_BAD if active and streak.time_ratio() < 0.3 else Color(1, 1, 1, 0.7)


## Impuls przy wejściu passy na wyższy próg.
func pulse_streak() -> void:
	_streak_pulse = 0.35


func _update_contracts(board: ContractBoard) -> void:
	_contract_box.visible = not board.contracts.is_empty()
	for i in _contract_labels.size():
		var l := _contract_labels[i]
		l.visible = i < board.contracts.size()
		if not l.visible:
			continue
		var c := board.contracts[i]
		if bool(c["done"]):
			l.text = "■ %s" % str(c["text"])
			l.add_theme_color_override("font_color", Palette.UI_GOOD.darkened(0.15))
		else:
			l.text = "□ %s  %s" % [str(c["text"]), ContractBoard.progress_text(c)]
			l.add_theme_color_override("font_color", Palette.UI_TEXT)


## Etap 4: tryb treningowy – profil planu pod licznikiem czasu i bieżący krok.
func set_workout(blocks: Array[Dictionary], plan_name: String) -> void:
	_workout_box.visible = true
	_profile.set_blocks(blocks)
	_workout_title.text = plan_name
	_supply_label.add_theme_font_size_override("font_size", 34)


## info: now_s, step_label, step_left_s, next_label, target_w, safe (bool)
func update_workout(info: Dictionary) -> void:
	_profile.set_now(float(info.get("now_s", 0.0)))
	_step_label.text = "%s  ·  %s" % [str(info.get("step_label", "")), UiStyle.clock(float(info.get("step_left_s", 0.0)))]
	_next_label.text = str(info.get("next_label", ""))
	_safe_label.visible = bool(info.get("safe", false))


## Karta zwiadu: co czeka w osadzie przed zjazdem (łup, obrona, koszt wysiłku).
## Pojawia się po tej stronie ekranu, po której jest zjazd.
func update_scout(visible_now: bool, side: int = 1, title: String = "", lines: String = "") -> void:
	_scout_card.visible = visible_now
	if not visible_now:
		return
	_scout_title.text = title
	_scout_lines.text = lines
	if side != _scout_side:
		_scout_side = side
		_scout_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT if side < 0 else Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE)
		_scout_card.grow_horizontal = Control.GROW_DIRECTION_END if side < 0 else Control.GROW_DIRECTION_BEGIN
		_scout_card.grow_vertical = Control.GROW_DIRECTION_END
		_scout_card.position += Vector2(48.0 if side < 0 else -48.0, 110.0)


## Gadająca głowa: kwestia z Chatter.line(); priorytet 0 = tło, 1 = zwykła, 2 = ważna.
func say(line: Dictionary, priority: int = 1) -> void:
	_head.say(line, priority)


func head_busy() -> bool:
	return _head.is_busy()


## Panel konwoju: schemat kolumny z pozycją gracza i podpowiedź, co robić. {} = ukryj.
## d: title, status, color, rel, beside, has_guard, has_tractor, hitch_rear, hitch_front,
## guard_hp, tractor_hp, hitch_rear_hp, hitch_front_hp, window, board.
func update_convoy(d: Dictionary) -> void:
	_convoy_box.visible = not d.is_empty()
	if d.is_empty():
		return
	_convoy_title.text = str(d.get("title", ""))
	_convoy_status.text = str(d.get("status", ""))
	_convoy_status.add_theme_color_override("font_color", d.get("color", Palette.UI_TEXT))
	var g := _convoy_diagram
	g.rel_m = float(d.get("rel", 0.0))
	g.beside = bool(d.get("beside", false))
	g.has_guard = bool(d.get("has_guard", true))
	g.has_tractor = bool(d.get("has_tractor", true))
	g.hitch_rear_alive = bool(d.get("hitch_rear", true))
	g.hitch_front_alive = bool(d.get("hitch_front", true))
	g.guard_hp = float(d.get("guard_hp", 1.0))
	g.tractor_hp = float(d.get("tractor_hp", 1.0))
	g.hitch_rear_hp = float(d.get("hitch_rear_hp", 1.0))
	g.hitch_front_hp = float(d.get("hitch_front_hp", 1.0))
	g.window = int(d.get("window", 0))
	g.board = float(d.get("board", -1.0))


## Pasek stanu u góry: wyzwanie, napad albo konwój (pusty = ukryty).
func update_challenge(text: String, color: Color) -> void:
	_challenge_label.text = text
	_challenge_label.visible = text != ""
	_challenge_label.add_theme_color_override("font_color", color)
	_status_box.visible = _hint.visible or _challenge_label.visible


## Zasilanie (moc względem celu), kondensatory i ostrzeżenia o ataku z boku.
func update_combat(combat: CombatModel, power_w: float, player_x: float, delta: float) -> void:
	_blink_t += delta
	_combat_row.visible = combat.enabled
	# Widełki celu: w zakresie – zielono, za słabo – pomarańczowo, za mocno – czerwono (przegrzanie).
	var range_text := TargetBand.range_text(combat.target_power_w, combat.target_low_tol, combat.target_high_tol)
	var fill_color := Palette.UI_GOOD
	match combat.band_status(power_w):
		TargetBand.Status.BELOW:
			_supply_label.text = "CEL %s · za słabo" % range_text
			fill_color = Palette.UI_ACCENT
		TargetBand.Status.ABOVE:
			_supply_label.text = "CEL %s · ZA MOCNO" % range_text
			fill_color = Palette.UI_BAD
		_:
			_supply_label.text = "CEL %s · OK" % range_text
	_supply_label.add_theme_color_override("font_color", fill_color.lerp(Palette.UI_TEXT, 0.25))
	_band_gauge.set_values(power_w, combat.target_power_w, combat.target_low_tol, combat.target_high_tol, fill_color)
	_supply_fill.color = fill_color
	_supply_fill.size.x = BAR_WIDTH * clampf(combat.supply_ratio(), 0.0, 1.0)
	_capacitor_fill.size.x = BAR_WIDTH * clampf(combat.capacitor, 0.0, 1.0)
	var ready := floori(combat.capacitor / CombatModel.CAPACITOR_RAM_COST + 0.001)
	_capacitor_caption.text = "KONDENSATORY  ×%d" % ready
	_capacitor_caption.add_theme_color_override("font_color", CAPACITOR_COLOR if ready > 0 else Palette.UI_DIM)
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
	_head.tick(delta)
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
	_scrap_pulse = maxf(0.0, _scrap_pulse - delta)
	var s := 1.0 + _scrap_pulse * 0.5
	_scrap_value.pivot_offset = _scrap_value.size * 0.5
	_scrap_value.scale = Vector2(s, s)
	_streak_pulse = maxf(0.0, _streak_pulse - delta)
	var k := 1.0 + _streak_pulse * 1.6
	_streak_label.pivot_offset = _streak_label.size * 0.5
	_streak_label.scale = Vector2(k, k)
	# Dryf HUD (OLED).
	_drift_t += delta / DRIFT_PERIOD_S
	if _drift_t >= 1.0:
		_drift_t = 0.0
		_drift_from = _drift_to
		_drift_to = Vector2(_rng.randf_range(-DRIFT_PX, DRIFT_PX), _rng.randf_range(-DRIFT_PX, DRIFT_PX))
	_root.position = _drift_from.lerp(_drift_to, smoothstep(0.0, 1.0, _drift_t))


# --- Budowa ----------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_top_left()
	_build_top_right()
	_build_status()
	_build_dashboard()
	_build_overlays()


## Lewa góra: czas do końca i dystans; niżej panel konwoju albo treningu.
func _build_top_left() -> void:
	var col := _column(Control.PRESET_TOP_LEFT, Vector2(40, 32), false)
	var plate := UiStyle.plate(UiStyle.STEEL, Palette.UI_ACCENT)
	plate.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)
	var time := _stat("DO OSADY", 76)
	_time_value = time.get_meta("value")
	row.add_child(time)
	var dist := _stat("DYSTANS", 40, Palette.UI_DIM)
	_distance_value = dist.get_meta("value")
	dist.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(dist)
	col.add_child(plate)

	# Panel konwoju (w treningu konwojów nie ma, więc dzieli miejsce z panelem treningu).
	_convoy_box = UiStyle.plate(UiStyle.STEEL_STRONG, Palette.UI_ACCENT)
	_convoy_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var convoy_col := VBoxContainer.new()
	convoy_col.add_theme_constant_override("separation", 2)
	convoy_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_convoy_box.add_child(convoy_col)
	_convoy_title = UiStyle.label("", 28, Palette.UI_ACCENT)
	convoy_col.add_child(_convoy_title)
	_convoy_diagram = ConvoyDiagram.new()
	_convoy_diagram.custom_minimum_size = Vector2(640, 180)
	_convoy_diagram.mouse_filter = Control.MOUSE_FILTER_IGNORE
	convoy_col.add_child(_convoy_diagram)
	_convoy_status = UiStyle.label("", 30, Palette.UI_TEXT)
	convoy_col.add_child(_convoy_status)
	_convoy_box.visible = false
	col.add_child(_convoy_box)

	# Panel treningu: plan, bieżący krok, profil.
	var wpanel := UiStyle.plate(UiStyle.STEEL_STRONG, Palette.UI_GOOD)
	wpanel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var wcol := VBoxContainer.new()
	wcol.add_theme_constant_override("separation", 4)
	wcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wpanel.add_child(wcol)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 24)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_workout_title = UiStyle.caption("", 24)
	title_row.add_child(_workout_title)
	_safe_label = UiStyle.caption("POLE BEZPIECZNE", 24, Palette.UI_GOOD)
	_safe_label.visible = false
	title_row.add_child(_safe_label)
	wcol.add_child(title_row)
	_step_label = UiStyle.label("", 36, Palette.UI_TEXT)
	wcol.add_child(_step_label)
	_profile = WorkoutProfile.new()
	_profile.custom_minimum_size = Vector2(560, 64)
	_profile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wcol.add_child(_profile)
	_next_label = UiStyle.label("", 24, Palette.UI_DIM)
	wcol.add_child(_next_label)
	_workout_box = wpanel
	wpanel.visible = false
	col.add_child(wpanel)


## Prawa góra: złom z mnożnikiem passy, paliwo i taran, zlecenia, gadająca głowa.
func _build_top_right() -> void:
	var col := _column(Control.PRESET_TOP_RIGHT, Vector2(-40, 32), true)
	var plate := UiStyle.plate(UiStyle.STEEL, Palette.UI_SCRAP)
	plate.size_flags_horizontal = Control.SIZE_SHRINK_END
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)
	# Passa: mnożnik, postęp do następnego progu, zegar.
	var streak_col := VBoxContainer.new()
	streak_col.add_theme_constant_override("separation", 3)
	streak_col.alignment = BoxContainer.ALIGNMENT_CENTER
	streak_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_streak_label = UiStyle.label("×1.0", 46, Palette.UI_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	streak_col.add_child(_streak_label)
	var progress := _bar(Palette.UI_ACCENT, 120.0, 8.0)
	_streak_fill = progress.get_meta("fill")
	streak_col.add_child(progress)
	var timer := _bar(Color(1, 1, 1, 0.7), 120.0, 5.0)
	_streak_time = timer.get_meta("fill")
	streak_col.add_child(timer)
	streak_col.add_child(UiStyle.caption("PASSA", 20, Palette.UI_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	row.add_child(streak_col)
	var scrap := _stat("ZŁOM", 76, Palette.UI_SCRAP)
	_scrap_value = scrap.get_meta("value")
	row.add_child(scrap)
	_scrap_panel = plate
	col.add_child(plate)
	_fuel_value = UiStyle.label("", 28, Color("ff9a5a"), HORIZONTAL_ALIGNMENT_RIGHT)
	_fuel_value.visible = false
	col.add_child(_fuel_value)

	# Zlecenia: trzy cele wyprawy z postępem.
	var contracts := UiStyle.plate(UiStyle.STEEL)
	contracts.size_flags_horizontal = Control.SIZE_SHRINK_END
	var ccol := VBoxContainer.new()
	ccol.add_theme_constant_override("separation", 0)
	ccol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contracts.add_child(ccol)
	ccol.add_child(UiStyle.caption("ZLECENIA", 20, Palette.UI_ACCENT))
	for i in 3:
		var l := UiStyle.label("", 26, Palette.UI_TEXT)
		ccol.add_child(l)
		_contract_labels.append(l)
	_contract_box = contracts
	contracts.visible = false
	col.add_child(contracts)

	_head = TalkingHead.new()
	_head.size_flags_horizontal = Control.SIZE_SHRINK_END
	col.add_child(_head)


## Środek góry: wąski pasek stanu (podpowiedź źródła mocy i bieżące zadanie).
func _build_status() -> void:
	var plate := UiStyle.plate(UiStyle.STEEL)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(col)
	_hint = UiStyle.caption("", 24, Palette.UI_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_hint)
	_challenge_label = UiStyle.label("", 34, Palette.UI_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	_challenge_label.visible = false
	col.add_child(_challenge_label)
	_status_box = plate
	plate.visible = false
	_place(plate, Control.PRESET_CENTER_TOP, Vector2(0, 24))


## Deska rozdzielcza na dole: prędkość | moc i strefy | cel, zasilanie, kondensatory, napęd.
func _build_dashboard() -> void:
	var plate := UiStyle.plate(UiStyle.STEEL, Palette.UI_ACCENT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)

	# Prędkość i kadencja.
	var speed_col := VBoxContainer.new()
	speed_col.add_theme_constant_override("separation", -2)
	speed_col.alignment = BoxContainer.ALIGNMENT_CENTER
	speed_col.custom_minimum_size = Vector2(190, 0)
	speed_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_value = UiStyle.label("0", 76, Palette.UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_speed_value.add_theme_constant_override("line_spacing", -12)
	speed_col.add_child(_speed_value)
	_speed_caption = UiStyle.caption("KM/H", 22, Palette.UI_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	speed_col.add_child(_speed_caption)
	_cadence_value = UiStyle.label("", 26, Palette.UI_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	speed_col.add_child(_cadence_value)
	row.add_child(speed_col)
	row.add_child(_divider())

	# Moc – największy element – z paskiem stref.
	var power_col := VBoxContainer.new()
	power_col.add_theme_constant_override("separation", -4)
	power_col.alignment = BoxContainer.ALIGNMENT_CENTER
	power_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var power_row := HBoxContainer.new()
	power_row.add_theme_constant_override("separation", 10)
	power_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_power_value = UiStyle.label("0", 116, Palette.UI_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_power_value.custom_minimum_size = Vector2(230, 0)
	power_row.add_child(_power_value)
	var unit := UiStyle.label("W", 60, Palette.UI_ACCENT)
	unit.size_flags_vertical = Control.SIZE_SHRINK_END
	power_row.add_child(unit)
	_zone_label = UiStyle.label("", 26, Palette.UI_DIM)
	_zone_label.custom_minimum_size = Vector2(220, 0)
	_zone_label.add_theme_constant_override("line_spacing", -4)
	power_row.add_child(_zone_label)
	power_col.add_child(power_row)
	_zone_strip = ZoneStrip.new()
	_zone_strip.custom_minimum_size = Vector2(500, 26)
	_zone_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	power_col.add_child(_zone_strip)
	row.add_child(power_col)
	row.add_child(_divider())

	# Cel mocy z widełkami, zasilanie, kondensatory i układ napędowy.
	var target_col := VBoxContainer.new()
	target_col.add_theme_constant_override("separation", 3)
	target_col.alignment = BoxContainer.ALIGNMENT_CENTER
	target_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_supply_label = UiStyle.label("", 28, Palette.UI_DIM)
	target_col.add_child(_supply_label)
	_band_gauge = BandGauge.new()
	_band_gauge.custom_minimum_size = Vector2(BAR_WIDTH * 2.0 + 24.0, 40)
	_band_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_col.add_child(_band_gauge)
	var bars := HBoxContainer.new()
	bars.add_theme_constant_override("separation", 24)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var supply := _captioned_bar("ZASILANIE", Palette.UI_GOOD)
	_supply_fill = supply.get_meta("fill")
	bars.add_child(supply)
	# Kondensatory: pięć ogniw; podpis mówi, na ile wyładowań (odparć ataku) starczy ładunku.
	var capacitor := _captioned_bar("KONDENSATORY", CAPACITOR_COLOR)
	_capacitor_fill = capacitor.get_meta("fill")
	_capacitor_caption = capacitor.get_child(0) as Label
	var cells := capacitor.get_child(1) as Control
	for i in range(1, 5):
		var gap := ColorRect.new()
		gap.color = Color(0, 0, 0, 0.9)
		gap.size = Vector2(3, 12)
		gap.position = Vector2(BAR_WIDTH * i / 5.0 - 1.5, 0)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cells.add_child(gap)
	bars.add_child(capacitor)
	_combat_row = bars
	target_col.add_child(bars)
	_wheel_label = UiStyle.label("", 22, Palette.UI_DIM)
	target_col.add_child(_wheel_label)
	_target_col = target_col
	row.add_child(target_col)
	_place(plate, Control.PRESET_CENTER_BOTTOM, Vector2(0, -16))


## Karta zwiadu, ostrzeżenia o gangu, komunikaty i wyskakujące napisy.
func _build_overlays() -> void:
	_scout_card = UiStyle.plate(UiStyle.STEEL_STRONG, Palette.UI_ACCENT)
	var scout_col := VBoxContainer.new()
	scout_col.add_theme_constant_override("separation", 2)
	scout_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scout_card.add_child(scout_col)
	_scout_title = UiStyle.label("", 38, Palette.UI_ACCENT)
	scout_col.add_child(_scout_title)
	_scout_lines = UiStyle.label("", 30, Palette.UI_TEXT)
	scout_col.add_child(_scout_lines)
	_scout_card.visible = false
	_root.add_child(_scout_card)

	_threat_left = UiStyle.label("", 96, Palette.UI_BAD)
	_threat_left.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_threat_left.grow_vertical = Control.GROW_DIRECTION_BOTH
	_threat_left.position += Vector2(40, 60)
	_threat_left.visible = false
	_root.add_child(_threat_left)
	_threat_right = UiStyle.label("", 96, Palette.UI_BAD, HORIZONTAL_ALIGNMENT_RIGHT)
	_threat_right.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_threat_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_threat_right.grow_vertical = Control.GROW_DIRECTION_BOTH
	_threat_right.position += Vector2(-40, 60)
	_threat_right.visible = false
	_root.add_child(_threat_right)

	_message = UiStyle.label("", 58, Palette.UI_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	# Długie komunikaty (np. o cyfrowym triggerze) zawijamy, zamiast ucinać na 16:9.
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(1500, 0)
	_message.set_anchors_preset(Control.PRESET_CENTER)
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message.grow_vertical = Control.GROW_DIRECTION_BOTH
	_message.position.y -= 150
	_message.visible = false
	_root.add_child(_message)
	_popup = UiStyle.label("", 76, Palette.UI_BAD, HORIZONTAL_ALIGNMENT_CENTER)
	_popup.set_anchors_preset(Control.PRESET_CENTER)
	_popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_popup.grow_vertical = Control.GROW_DIRECTION_BOTH
	_popup.position.y -= 40
	_popup.visible = false
	_root.add_child(_popup)


# --- Klocki ----------------------------------------------------------------------

## Kolumna przypięta do rogu ekranu; elementy układają się jeden pod drugim.
func _column(preset: Control.LayoutPreset, offset: Vector2, to_right: bool) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)
	col.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN if to_right else Control.GROW_DIRECTION_END
	col.grow_vertical = Control.GROW_DIRECTION_END
	col.position += offset
	return col


## Wartość z podpisem pod spodem. Wartość: meta "value".
func _stat(title: String, size: int, color: Color = Palette.UI_TEXT) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -10 if size >= 60 else -2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var value := UiStyle.label("0", size, color, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(value)
	col.add_child(UiStyle.caption(title, 20, Palette.UI_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	col.set_meta("value", value)
	return col


func _divider() -> Control:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.12)
	line.custom_minimum_size = Vector2(2, 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _captioned_bar(title: String, color: Color) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(UiStyle.caption(title, 18, color.lerp(Palette.UI_DIM, 0.4)))
	var bar := _bar(color, BAR_WIDTH, 12.0)
	col.add_child(bar)
	col.set_meta("fill", bar.get_meta("fill"))
	return col


func _bar(color: Color, width: float = BAR_WIDTH, height: float = 16.0) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(width, height)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.size = Vector2(width, height)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bg)
	var fill := ColorRect.new()
	fill.color = color
	fill.size = Vector2(0, height)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(fill)
	holder.set_meta("fill", fill)
	return holder


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
