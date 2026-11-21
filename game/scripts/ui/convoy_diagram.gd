class_name ConvoyDiagram
extends Control
## Schemat konwoju widziany z góry: ogon, galera i ciągnik spięte sprzęgami oraz pozycja
## gracza względem kolumny. Tył z lewej, przód z prawej (kierunek jazdy →).
## To główna podpowiedź taktyczna: widać, ile brakuje do okna sprzęgu.

const BACK_M := -44.0
const FRONT_M := 24.0

## Położenie gracza względem środka galery [m]; dodatnie = z przodu.
var rel_m := -40.0
var beside := false
var has_guard := true
var has_tractor := true
var hitch_rear_alive := true
var hitch_front_alive := true
var guard_hp := 1.0
var tractor_hp := 1.0
var hitch_rear_hp := 1.0
var hitch_front_hp := 1.0
## 0 = żadne okno, 1 = tylny sprzęg, 2 = przedni sprzęg.
var window := 0
## Postęp przesiadki 0..1; ujemny = nie trwa.
var board := -1.0

var _t := 0.0


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


func _x(m: float) -> float:
	return (m - BACK_M) / (FRONT_M - BACK_M) * size.x


func _draw() -> void:
	var mid := size.y * 0.42
	var half_h := 19.0
	var font := UiStyle.font()
	# Droga i pas konwoju.
	draw_rect(Rect2(0, mid - 58, size.x, 116), Color(0, 0, 0, 0.42))
	draw_line(Vector2(0, mid - 30), Vector2(size.x, mid - 30), Color(1, 1, 1, 0.12), 2.0)
	draw_line(Vector2(0, mid + 30), Vector2(size.x, mid + 30), Color(1, 1, 1, 0.12), 2.0)
	var pulse := 0.55 + 0.45 * sin(_t * 9.0)
	# Okna sprzęgów: strefy na bocznym pasie, z których widać sworzeń.
	if has_guard and hitch_rear_alive:
		_window(ConvoyDirector.HITCH_REAR_OFFSET_M, mid, window == 1, pulse)
	if has_tractor and hitch_front_alive and board < 0.0:
		_window(ConvoyDirector.HITCH_FRONT_OFFSET_M, mid, window == 2, pulse)
	# Wagony.
	if has_guard:
		_wagon(ConvoyDirector.GUARD_OFFSET_M, ConvoyDirector.GUARD_HALF_M, mid, half_h, Color("8a4a30"), "OGON", guard_hp, font)
	_wagon(0.0, ConvoyDirector.GALLEY_HALF_M, mid, half_h, Color("c9a23a"), "GALERA", -1.0, font)
	# Pręty klatki.
	for i in 6:
		var bx := _x(-ConvoyDirector.GALLEY_HALF_M + 1.0 + i * 1.3)
		draw_line(Vector2(bx, mid - half_h + 3), Vector2(bx, mid + half_h - 3), Color(0, 0, 0, 0.6), 3.0)
	if has_tractor:
		_wagon(ConvoyDirector.TRACTOR_OFFSET_M, ConvoyDirector.TRACTOR_HALF_M, mid, half_h, Color("a8382a"), "CIĄGNIK", tractor_hp, font)
	# Sprzęgi.
	if has_guard and hitch_rear_alive:
		_hitch(ConvoyDirector.HITCH_REAR_OFFSET_M, mid, hitch_rear_hp, window == 1, pulse)
	if has_tractor and hitch_front_alive and board < 0.0:
		_hitch(ConvoyDirector.HITCH_FRONT_OFFSET_M, mid, hitch_front_hp, window == 2, pulse)
	# Gracz: strzałka na bocznym pasie albo na pasie konwoju (za/przed kolumną).
	var px := clampf(_x(rel_m), 14.0, size.x - 14.0)
	var py := mid + 44.0 if beside else mid
	var col := Palette.UI_SCRAP
	draw_colored_polygon(PackedVector2Array([Vector2(px + 16, py), Vector2(px - 12, py - 13), Vector2(px - 5, py), Vector2(px - 12, py + 13)]), col)
	if rel_m < BACK_M:
		draw_string(font, Vector2(34, py + 9), "konwój %d m przed tobą" % roundi(-rel_m - 13.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, col)
	draw_string(font, Vector2(size.x - 190, size.y - 6), "kierunek jazdy →", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.45))
	# Przesiadka.
	if board >= 0.0:
		var bar := Rect2(0, size.y - 34, size.x * 0.6, 16)
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(board, 0.0, 1.0), bar.size.y)), Palette.UI_GOOD)


func _wagon(center_m: float, half_m: float, mid: float, half_h: float, color: Color, caption: String, hp: float, font: Font) -> void:
	var x0 := _x(center_m - half_m)
	var x1 := _x(center_m + half_m)
	draw_rect(Rect2(x0, mid - half_h, x1 - x0, half_h * 2.0), color)
	draw_rect(Rect2(x0, mid - half_h, x1 - x0, half_h * 2.0), Color(0, 0, 0, 0.8), false, 3.0)
	draw_string(font, Vector2(x0 - 20, mid - half_h - 30), caption, HORIZONTAL_ALIGNMENT_CENTER, x1 - x0 + 40, 20, Palette.UI_TEXT)
	if hp >= 0.0:
		draw_rect(Rect2(x0, mid - half_h - 24, x1 - x0, 7), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(x0, mid - half_h - 24, (x1 - x0) * clampf(hp, 0.0, 1.0), 7), Palette.UI_BAD)


func _hitch(at_m: float, mid: float, hp: float, open: bool, pulse: float) -> void:
	var c := Vector2(_x(at_m), mid)
	var col := Color("ffd21a") if open else Color("9a8a4a")
	draw_circle(c, 9.0 + (4.0 * pulse if open else 0.0), col)
	draw_arc(c, 13.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(hp, 0.0, 1.0), 20, Color(1, 1, 1, 0.9), 3.0)


func _window(at_m: float, mid: float, open: bool, pulse: float) -> void:
	var x0 := _x(at_m - ConvoyDirector.WINDOW_BACK_M)
	var x1 := _x(at_m + ConvoyDirector.WINDOW_FRONT_M)
	var a := (0.35 + 0.35 * pulse) if open else 0.16
	var col := Color(1.0, 0.82, 0.1, a)
	draw_rect(Rect2(x0, mid + 30, x1 - x0, 28), col)
	draw_rect(Rect2(x0, mid - 58, x1 - x0, 28), col)
