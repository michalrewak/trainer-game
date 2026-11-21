class_name UiStyle
extends RefCounted
## Wspólny styl UI pod telewizor oglądany z ~3 m: duże, grube cyfry (Bahnschrift z Windows,
## zapasowo Segoe UI / domyślny font), obrys i ciemne płyty dla kontrastu na jasnej pustyni.
## Wygląd: stalowe płyty ze ściętymi rogami, pomarańczowy pasek akcentu, napisy jak
## z szablonu – warsztat z pustkowi, nie bajka. Bazowa rozdzielczość 1920x1080.

## Ciemna stal: półprzezroczysta na HUD (widać przez nią świat), pełna w menu.
const STEEL := Color(0.07, 0.06, 0.055, 0.8)
const STEEL_STRONG := Color(0.07, 0.06, 0.055, 0.92)
const STEEL_MENU := Color(0.13, 0.105, 0.09, 0.96)
const STEEL_FOCUS := Color(0.42, 0.23, 0.06, 0.98)
const RUST_EDGE := Color(0.45, 0.27, 0.14, 1.0)
const BACKDROP := Color("17110d")

static var _font: Font
static var _theme: Theme


static func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
		f.font_weight = 650
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_font = f
	return _font


static func label(text: String, size: int, color: Color = Palette.UI_TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", maxi(4, size / 10))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Mały napis-etykieta wersalikami (podpisy wskaźników, nagłówki).
static func caption(text: String, size: int = 22, color: Color = Palette.UI_DIM, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(text.to_upper(), size, color, align)
	l.add_theme_constant_override("outline_size", 3)
	return l


## Stalowa płyta: ścięty lewy górny i prawy dolny róg, opcjonalny pasek akcentu z lewej.
static func plate_style(color: Color = STEEL, accent: Color = Color(0, 0, 0, 0), cut: int = 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.corner_detail = 1
	s.corner_radius_top_left = cut
	s.corner_radius_bottom_right = cut
	s.border_color = accent if accent.a > 0.0 else Color(1, 1, 1, 0.07)
	s.set_border_width_all(1)
	if accent.a > 0.0:
		s.set_border_width_all(0)
		s.border_width_left = 6
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


static func plate(color: Color = STEEL, accent: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", plate_style(color, accent))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Zgodność ze starszym kodem: panel to teraz płyta.
static func panel_style(color: Color = STEEL, radius: int = 16) -> StyleBoxFlat:
	return plate_style(color, Color(0, 0, 0, 0), radius)


static func panel(color: Color = STEEL) -> PanelContainer:
	return plate(color)


## Nagłówek sekcji: pomarańczowy klocek, napis i linia do końca.
static func section(title: String, size: int = 26) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var block := ColorRect.new()
	block.color = Palette.UI_ACCENT
	block.custom_minimum_size = Vector2(10, size)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(block)
	row.add_child(caption(title, size, Palette.UI_ACCENT))
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.14)
	line.custom_minimum_size = Vector2(0, 2)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	return row


## Żeton zasobu: podpis nad wartością. Wartość: meta "value" (Label).
static func chip(title: String, color: Color = Palette.UI_TEXT, value_size: int = 40) -> PanelContainer:
	var p := plate(STEEL_MENU, color.darkened(0.25))
	(p.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_top = 4
	(p.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_bottom = 6
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(col)
	col.add_child(caption(title, 18))
	var value := label("0", value_size, color)
	col.add_child(value)
	p.set_meta("value", value)
	return p


## Motyw menu: przyciski-płyty z paskiem po lewej, wyraźny fokus (nawigacja padem bez myszy).
static func menu_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 40
	var normal := plate_style(STEEL_MENU, RUST_EDGE, 14)
	normal.content_margin_left = 26
	normal.content_margin_right = 22
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = STEEL_FOCUS
	focus.border_color = Palette.UI_ACCENT
	focus.set_border_width_all(4)
	focus.border_width_left = 12
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.09, 0.08, 0.075, 0.9)
	disabled.border_color = Color(0.25, 0.22, 0.2)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("hover", "Button", focus)
	t.set_stylebox("pressed", "Button", focus)
	t.set_stylebox("hover_pressed", "Button", focus)
	t.set_color("font_color", "Button", Palette.UI_TEXT)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.5, 0.46))
	t.set_font_size("font_size", "Button", 44)
	t.set_color("font_color", "Label", Palette.UI_TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "Label", 6)
	_theme = t
	return t


static func button(text: String, min_width: float = 640.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 96)
	b.focus_mode = Control.FOCUS_ALL
	return b


## Tło ekranów menu: ciemna stal z ukośnymi pasami ostrzegawczymi u góry i u dołu.
static func backdrop() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = BACKDROP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	for top in [true, false]:
		var stripes := HazardStripes.new()
		stripes.anchor_right = 1.0
		stripes.anchor_top = 0.0 if top else 1.0
		stripes.anchor_bottom = 0.0 if top else 1.0
		stripes.offset_top = 0.0 if top else -10.0
		stripes.offset_bottom = 10.0 if top else 0.0
		stripes.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(stripes)
	return root


## mm:ss
static func clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds - 0.001))
	return "%d:%02d" % [s / 60, s % 60]


static func km(meters: float) -> String:
	return "%.2f" % (meters / 1000.0)
