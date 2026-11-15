class_name UiStyle
extends RefCounted
## Wspólny styl UI pod telewizor oglądany z ~3 m: duże, grube cyfry (Bahnschrift z Windows,
## zapasowo Segoe UI / domyślny font), obrys i półprzezroczyste panele dla kontrastu
## na jasnej pustyni. Bazowa rozdzielczość 1920x1080 skalowana do 4K.

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


static func panel_style(color: Color = Palette.UI_PANEL, radius: int = 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


static func panel(color: Color = Palette.UI_PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(color))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Motyw menu: duże przyciski, wyraźny fokus (nawigacja padem bez myszy).
static func menu_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 40
	var normal := panel_style(Color(0.08, 0.06, 0.05, 0.78), 14)
	normal.content_margin_left = 40
	normal.content_margin_right = 40
	normal.content_margin_top = 18
	normal.content_margin_bottom = 18
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(0.35, 0.2, 0.06, 0.95)
	focus.border_color = Palette.UI_ACCENT
	focus.set_border_width_all(6)
	var hover := focus.duplicate() as StyleBoxFlat
	for style_name in ["normal", "disabled"]:
		t.set_stylebox(style_name, "Button", normal)
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", focus)
	t.set_stylebox("hover_pressed", "Button", focus)
	t.set_color("font_color", "Button", Palette.UI_TEXT)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
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


## mm:ss
static func clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds - 0.001))
	return "%d:%02d" % [s / 60, s % 60]


static func km(meters: float) -> String:
	return "%.2f" % (meters / 1000.0)
