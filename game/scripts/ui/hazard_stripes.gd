class_name HazardStripes
extends Control
## Ukośne pasy ostrzegawcze (pomarańcz na czerni) – ozdobna listwa ekranów menu.

var stripe_px := 26.0
var color := Color(0.85, 0.5, 0.12, 0.55)


func _ready() -> void:
	clip_contents = true
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.9))
	var x := -size.y
	while x < size.x:
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, size.y), Vector2(x + size.y, 0.0),
			Vector2(x + size.y + stripe_px * 0.5, 0.0), Vector2(x + stripe_px * 0.5, size.y),
		]), color)
		x += stripe_px
