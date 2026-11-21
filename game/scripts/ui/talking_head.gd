class_name TalkingHead
extends PanelContainer
## Okienko „gadającej głowy”: popiersie postaci w 3D (osobny mały świat w SubViewport),
## imię, rola i kwestia wypisywana litera po literze. Kwestie czekają w krótkiej kolejce;
## ważniejsza przerywa mniej ważną, a nadmiar przepada – gadki nie mogą zalewać ekranu.

const PORTRAIT_PX := 230.0
const TEXT_WIDTH := 640.0
const MAX_QUEUE := 2
const CHARS_PER_S := 40.0
const JAW_DROP := 0.11

var _viewport: SubViewport
var _holder: Node3D
var _bust: Node3D
var _jaw: Node3D
var _jaw_y := 0.0
var _spin: Node3D
var _name: Label
var _role: Label
var _text: Label
var _style: StyleBoxFlat
var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _left_s := 0.0
var _shown := 0.0
var _time := 0.0
var _who := ""


## Budowane od razu (nie w _ready), żeby say() działało także przed wejściem do drzewa.
func _init() -> void:
	_build()
	visible = false


func is_busy() -> bool:
	return not _current.is_empty()


## Kto teraz mówi ("" = nikt) – do testów i logiki gadek.
func speaker() -> String:
	return str(_current.get("who", ""))


## Kwestia z Chatter.line(). priority: 0 = tło (fabuła), 1 = zwykła, 2 = ważna (przerywa).
func say(line: Dictionary, priority: int = 1) -> void:
	if line.is_empty():
		return
	var entry := line.duplicate()
	entry["priority"] = priority
	if _current.is_empty() or priority > int(_current["priority"]):
		_show(entry)
	elif priority > 0 and _queue.size() < MAX_QUEUE:
		_queue.append(entry)


func tick(delta: float) -> void:
	if _current.is_empty():
		return
	_time += delta
	_shown += delta * CHARS_PER_S
	var total := str(_current["text"]).length()
	_text.visible_characters = mini(total, int(_shown))
	var talking := _shown < total + 6.0
	if _jaw != null:
		_jaw.position.y = _jaw_y - (absf(sin(_time * 15.0)) * JAW_DROP if talking else 0.0)
	_holder.rotation.y = sin(_time * 1.3) * 0.14
	_holder.rotation.x = sin(_time * 2.3) * 0.04 + (sin(_time * 7.5) * 0.03 if talking else 0.0)
	if _spin != null:
		_spin.rotation.z += delta * 1.2
	_left_s -= delta
	if _left_s <= 0.0:
		_current = {}
		if _queue.is_empty():
			visible = false
		else:
			_show(_queue.pop_front())


func _show(entry: Dictionary) -> void:
	_current = entry
	var text := str(entry["text"])
	_left_s = Chatter.read_time_s(text)
	_shown = 0.0
	_name.text = str(entry["name"])
	_name.add_theme_color_override("font_color", entry["color"])
	_role.text = str(entry["role"])
	_text.text = text
	_text.visible_characters = 0
	_style.border_color = (entry["color"] as Color).darkened(0.2)
	if str(entry["who"]) != _who:
		_who = str(entry["who"])
		if _bust != null:
			_bust.queue_free()
		_bust = BustFactory.build(_who)
		_holder.add_child(_bust)
		_jaw = _bust.get_node_or_null("Jaw") as Node3D
		_jaw_y = _jaw.position.y if _jaw != null else 0.0
		_spin = _bust.get_node_or_null("Spin") as Node3D
	visible = true


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = UiStyle.panel_style(Palette.UI_PANEL_STRONG, 10)
	_style.set_border_width_all(4)
	_style.border_color = Palette.UI_ACCENT
	_style.content_margin_left = 12
	_style.content_margin_right = 22
	_style.content_margin_top = 12
	_style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", _style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	var frame := SubViewportContainer.new()
	frame.custom_minimum_size = Vector2(PORTRAIT_PX, PORTRAIT_PX)
	frame.stretch = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(frame)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	frame.add_child(_viewport)
	# Ciemne tło i ostre światło z boku: twarze mają być brudne i wyraziste, nie bajkowe.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.065, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Zimny cień, ciepłe światło kluczowe – jak przy ognisku w nocy.
	env.ambient_light_color = Color(0.3, 0.4, 0.52)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var cam := Camera3D.new()
	cam.environment = env
	cam.fov = 34.0
	cam.position = Vector3(0, -0.02, 3.25)
	_viewport.add_child(cam)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.86, 0.68)
	key.light_energy = 2.0
	key.rotation = Vector3(-0.6, 0.85, 0)
	key.shadow_enabled = true
	_viewport.add_child(key)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.3, 0.75, 0.85)
	rim.light_energy = 3.0
	rim.omni_range = 6.0
	rim.position = Vector3(-1.8, 0.8, -1.2)
	_viewport.add_child(rim)
	_holder = Node3D.new()
	_viewport.add_child(_holder)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_name = UiStyle.label("", 40, Palette.UI_ACCENT)
	col.add_child(_name)
	_role = UiStyle.label("", 24, Palette.UI_DIM)
	col.add_child(_role)
	_text = UiStyle.label("", 38, Palette.UI_TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(TEXT_WIDTH, 150)
	_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	col.add_child(_text)
