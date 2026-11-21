class_name ZoneStrip
extends Control
## Pasek stref mocy Z1–Z7 (Coggan): siedem pól w kolorach stref, bieżąca strefa świeci,
## reszta jest przygaszona. Wskazówka pokazuje miejsce wewnątrz strefy.

var zone := -1
## Położenie w obrębie strefy 0..1 (od dolnej do górnej granicy).
var within := 0.0


func set_power(power_w: float, ftp_w: float) -> void:
	if power_w < 5.0 or ftp_w <= 0.0:
		zone = -1
	else:
		zone = TrainingMetrics.zone_index(power_w, ftp_w)
		var frac := power_w / ftp_w
		var limits := TrainingMetrics.ZONE_LIMITS
		var lo: float = 0.0 if zone == 0 else float(limits[zone - 1])
		var hi: float = float(limits[zone]) if zone < limits.size() else lo + 0.5
		within = clampf((frac - lo) / maxf(hi - lo, 0.01), 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var n := TrainingMetrics.ZONE_COLORS.size()
	var gap := 4.0
	var w := (size.x - gap * (n - 1)) / n
	var font := UiStyle.font()
	for i in n:
		var r := Rect2(i * (w + gap), 0.0, w, size.y)
		var c: Color = TrainingMetrics.ZONE_COLORS[i]
		var on := i == zone
		draw_rect(r, c if on else Color(c, 0.22))
		draw_string(font, Vector2(r.position.x, r.position.y + size.y * 0.5 + 8.0), "Z%d" % (i + 1), HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color(0, 0, 0, 0.85) if on else Color(1, 1, 1, 0.5))
		if on:
			var x := r.position.x + within * w
			draw_line(Vector2(x, -4.0), Vector2(x, size.y + 4.0), Color.WHITE, 4.0)
