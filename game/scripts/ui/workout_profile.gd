class_name WorkoutProfile
extends Control
## Profil planu treningowego (etap 4): bloki kroków (wysokość i kolor = intensywność
## względem FTP), przyciemniona część już przejechana i znacznik „teraz”.
## Dane są ogólne (słowniki), więc widżet nie zależy od formatu planu.

var blocks: Array[Dictionary] = []   # {"start": s, "duration": s, "from": frac, "to": frac}
var total_s := 1.0
var now_s := 0.0


func set_blocks(p_blocks: Array[Dictionary]) -> void:
	blocks = p_blocks
	total_s = 0.0
	for b in blocks:
		total_s = maxf(total_s, float(b["start"]) + float(b["duration"]))
	total_s = maxf(total_s, 1.0)
	queue_redraw()


func set_now(seconds: float) -> void:
	now_s = seconds
	queue_redraw()


static func zone_color(fraction: float) -> Color:
	if fraction < 0.56:
		return Color("8a8f96")
	if fraction < 0.76:
		return Color("4a9fd8")
	if fraction < 0.91:
		return Color("5cc46a")
	if fraction < 1.06:
		return Color("f2c94c")
	if fraction < 1.21:
		return Color("f2994a")
	return Color("eb5757")


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	var max_frac := 1.5
	for b in blocks:
		var x0 := float(b["start"]) / total_s * w
		var x1 := (float(b["start"]) + float(b["duration"])) / total_s * w
		var f0 := float(b["from"])
		var f1 := float(b["to"])
		var y0 := h - clampf(f0 / max_frac, 0.05, 1.0) * h
		var y1 := h - clampf(f1 / max_frac, 0.05, 1.0) * h
		var pts := PackedVector2Array([Vector2(x0, h), Vector2(x0, y0), Vector2(x1, y1), Vector2(x1, h)])
		draw_colored_polygon(pts, zone_color((f0 + f1) * 0.5))
	var nx := clampf(now_s / total_s, 0.0, 1.0) * w
	draw_rect(Rect2(Vector2.ZERO, Vector2(nx, h)), Color(0, 0, 0, 0.45))
	draw_line(Vector2(nx, -6), Vector2(nx, h + 6), Color.WHITE, 4.0)
