class_name TrackItem
extends RefCounted
## Obiekt na trasie: wrak do ominięcia albo złom do zebrania.
## Pozycja = pas + dystans wzdłuż trasy (metry od startu wyprawy).

## CRATE = skrzynia z losową nagrodą.
enum Kind { WRECK, SCRAP, SCRAP_BIG, FUEL, CRATE }

var id := 0
var kind: Kind = Kind.SCRAP
var lane := 1
var distance_m := 0.0
var value := 1
## Przesunięcie w bok od środka pasa [m] – złom leży też między pasami i przy krawędzi.
var offset_x := 0.0
var variant := 0
var consumed := false
## Wytrzymałość wraku na ostrzał z wieżyczki.
var hp := 2
## Wrak już minięty (do liczenia uników „o włos”).
var passed := false


func _init(p_id: int = 0, p_kind: Kind = Kind.SCRAP, p_lane: int = 1, p_distance_m: float = 0.0, p_value: int = 1, p_variant: int = 0) -> void:
	id = p_id
	kind = p_kind
	lane = p_lane
	distance_m = p_distance_m
	value = p_value
	variant = p_variant


func is_wreck() -> bool:
	return kind == Kind.WRECK


func is_scrap() -> bool:
	return kind == Kind.SCRAP or kind == Kind.SCRAP_BIG


func is_fuel() -> bool:
	return kind == Kind.FUEL


func is_crate() -> bool:
	return kind == Kind.CRATE


## Rzecz do zebrania (złom albo paliwo).
func is_pickup() -> bool:
	return kind != Kind.WRECK
