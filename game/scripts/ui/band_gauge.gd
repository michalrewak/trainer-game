class_name BandGauge
extends Control
## Wskaźnik widełek mocy: pozioma skala w watach, zielone pole = widełki celu, czerwone
## za nimi = przegrzanie, biała wskazówka = moc z nóg teraz. Od razu widać, czy trzeba
## docisnąć, czy odpuścić – bez czytania liczb.

var target_w := 130.0
var low_tol := 0.1
var high_tol := 0.4
var power_w := 0.0
var status_color := Palette.UI_GOOD

var _shown_w := 0.0


func set_values(p_power_w: float, p_target_w: float, p_low_tol: float, p_high_tol: float, color: Color) -> void:
	power_w = p_power_w
	target_w = p_target_w
	low_tol = p_low_tol
	high_tol = p_high_tol
	status_color = color
	# Wskazówka lekko wygładzona, żeby nie drgała.
	_shown_w = lerpf(_shown_w, power_w, 0.35)
	queue_redraw()


func _draw() -> void:
	var lo := TargetBand.low(target_w, low_tol)
	var hi := TargetBand.high(target_w, high_tol)
	var top_w := maxf(hi * 1.3, 120.0)
	var bar := Rect2(0.0, 10.0, size.x, size.y - 20.0)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	var x_lo := clampf(lo / top_w, 0.0, 1.0) * size.x
	var x_hi := clampf(hi / top_w, 0.0, 1.0) * size.x
	# Widełki i strefa przegrzania.
	draw_rect(Rect2(x_lo, bar.position.y, x_hi - x_lo, bar.size.y), Color(Palette.UI_GOOD, 0.5))
	draw_rect(Rect2(x_hi, bar.position.y, size.x - x_hi, bar.size.y), Color(Palette.UI_BAD, 0.3))
	for x: float in [x_lo, x_hi]:
		draw_line(Vector2(x, bar.position.y - 4.0), Vector2(x, bar.end.y + 4.0), Color(1, 1, 1, 0.55), 2.0)
	# Wypełnienie do bieżącej mocy i wskazówka.
	var x_now := clampf(_shown_w / top_w, 0.0, 1.0) * size.x
	draw_rect(Rect2(0.0, bar.position.y + bar.size.y * 0.3, x_now, bar.size.y * 0.4), Color(status_color, 0.9))
	draw_line(Vector2(x_now, 0.0), Vector2(x_now, size.y), Color.WHITE, 5.0)
	draw_colored_polygon(PackedVector2Array([Vector2(x_now - 9.0, 0.0), Vector2(x_now + 9.0, 0.0), Vector2(x_now, 11.0)]), Color.WHITE)
