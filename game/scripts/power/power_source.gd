@abstract
class_name PowerSource
extends RefCounted
## Źródło mocy dla gry. Reszta gry zna wyłącznie ten interfejs i nie wie,
## czy moc pochodzi z pada, ze skryptu testowego, czy (od etapu 5) z trenażera.

enum Status { ACTIVE, CONNECTING, LOST }

var _notices: Array[String] = []


## Wywoływane raz na klatkę przez kontroler wyprawy, zanim gra odczyta moc.
func update(_delta: float) -> void:
	pass


## Aktualna moc w watach (>= 0).
@abstract func get_power_watts() -> float


## Aktualna kadencja w obr./min (>= 0). Tylko do wyświetlania – nie jest mechaniką.
@abstract func get_cadence() -> float


## Stan źródła. Gdy LOST albo CONNECTING, gra pauzuje wyprawę (nigdy jej nie przerywa).
func get_status() -> Status:
	return Status.ACTIVE


## Krótka nazwa źródła do HUD i menu, np. "PAD".
func get_label() -> String:
	return ""


## Krótki stały komunikat do HUD (np. "TEMPOMAT 210 W"); pusty, gdy nie ma nic do pokazania.
func get_hint() -> String:
	return ""


## Jednorazowe komunikaty dla gracza (np. „trigger pada jest cyfrowy”). Zwraca i czyści.
func take_notices() -> Array[String]:
	var out := _notices.duplicate()
	_notices.clear()
	return out


func push_notice(text: String) -> void:
	_notices.append(text)


# --- Sterowanie oporem (etapy 4–6). Źródła bez trenażera ignorują te wywołania. ---

## Czy źródło potrafi ustawiać opór trenażera (ERG / symulacja nachylenia).
func supports_resistance_control() -> bool:
	return false


## Tryb ERG: trenażer trzyma zadaną moc. 0 albo mniej = wyłącz ERG.
func set_erg_target(_watts: float) -> void:
	pass


## Tryb symulacji: nachylenie w procentach (np. 4.5 = 4,5%).
func set_grade(_grade_percent: float) -> void:
	pass
