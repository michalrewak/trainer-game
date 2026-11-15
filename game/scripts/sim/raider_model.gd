class_name RaiderModel
extends RefCounted
## Wrogi pojazd gangu. Cykl: dojazd z tyłu (APPROACH) -> jazda obok gracza (SHADOW)
## -> sygnał ataku (TELEGRAPH) -> taranowanie bokiem (RAM) -> ponowna próba albo ucieczka
## (RETREAT). Może zostać zestrzelony albo rozbić się o wrak (DESTROYED).

enum State { APPROACH, SHADOW, TELEGRAPH, RAM, RETREAT, DESTROYED }

var id := 0
var state: State = State.APPROACH
var x := 0.0
var d := 0.0
var speed := 0.0
var lateral_velocity := 0.0
var hp := 3
var max_hp := 3
## Strona ataku: -1 = z lewej, +1 = z prawej.
var side := -1
var timer := 0.0
var attempts_left := 2
var offset_d := 0.0
var ram_from_x := 0.0
var ram_to_x := 0.0
## Pozycja „na flance” zablokowana w chwili sygnału ataku – zmiana pasa w tym czasie = unik.
var locked_flank_x := 0.0
var ram_hit_resolved := false
var variant := 0
var hit_flash := 0.0


func _init(p_id: int = 0, p_side: int = -1, p_variant: int = 0) -> void:
	id = p_id
	side = p_side
	variant = p_variant


func is_alive() -> bool:
	return state != State.DESTROYED


func is_threatening() -> bool:
	return state == State.TELEGRAPH or state == State.RAM


func set_state(new_state: State) -> void:
	state = new_state
	timer = 0.0
