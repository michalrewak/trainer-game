class_name RaiderModel
extends RefCounted
## Wrogi pojazd gangu. Cykl: dojazd z tyłu (APPROACH) -> jazda obok gracza (SHADOW)
## -> sygnał ataku (TELEGRAPH) -> taranowanie bokiem (RAM) -> ponowna próba albo ucieczka
## (RETREAT). Może zostać zestrzelony albo rozbić się o wrak (DESTROYED).
##
## Ten sam model opisuje części konwoju (ciągnik, galera, ogon, sprzęgi): mają stan CONVOY,
## nie atakują, a ich ruchem i odsłonięciem na ostrzał steruje ConvoyDirector.

enum State { APPROACH, SHADOW, TELEGRAPH, RAM, RETREAT, DESTROYED, CONVOY }
## Część konwoju; NONE = zwykły wóz gangu.
enum Part { NONE, TRACTOR, GALLEY, GUARD, HITCH_FRONT, HITCH_REAR }

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

# --- Części konwoju ---
var part: Part = Part.NONE
## Czy wieżyczka może teraz wziąć tę część na cel (sprzęg widać tylko z boku, z bliska).
var exposed := true
## Im większy, tym chętniej automat celuje właśnie tu (odsłonięty sprzęg ma pierwszeństwo).
var aim_priority := 0.0
## Połowa długości bryły do trafień [m]; 0 = cel punktowy.
var half_length := 0.0
var hit_radius := 1.5
## Klatka z pedalarzami: trafienia nie niszczą wagonu, tylko ranią ludzi (liczy je konwój).
var invulnerable := false
var hits_taken := 0
## Światła stopu: konwój hamuje.
var braking := false
## Część odczepiona od ciągnika (toczy się bez napędu).
var detached := false


func _init(p_id: int = 0, p_side: int = -1, p_variant: int = 0) -> void:
	id = p_id
	side = p_side
	variant = p_variant


func is_alive() -> bool:
	return state != State.DESTROYED


func is_convoy_part() -> bool:
	return part != Part.NONE


func is_hitch() -> bool:
	return part == Part.HITCH_FRONT or part == Part.HITCH_REAR


func is_threatening() -> bool:
	return state == State.TELEGRAPH or state == State.RAM


func set_state(new_state: State) -> void:
	state = new_state
	timer = 0.0
