class_name WorkoutStep
extends RefCounted
## Jeden krok planu treningowego: rodzaj, czas trwania i cel mocy jako ułamek FTP
## (0.75 = 75% FTP). Krok stały ma power_start == power_end, rampa zmienia cel liniowo
## od power_start do power_end w czasie trwania kroku.
## FREERIDE = jazda swobodna bez celu mocy: cel 0 (ERG wyłączony, gracz jedzie po swojemu).

enum Kind { WARMUP, COOLDOWN, WORK, RECOVERY, STEADY, FREERIDE }

## Od tej intensywności (ułamek FTP) krok liczy się jako ciężki (WorkoutPlan.is_hard_step).
const HARD_THRESHOLD := 0.88
## Do tej intensywności krok bez jawnego rodzaju (np. SteadyState w ZWO) to regeneracja.
const RECOVERY_THRESHOLD := 0.55

## Nazwy rodzajów w naszym formacie JSON (indeks = wartość Kind).
const KIND_NAMES: Array[String] = ["warmup", "cooldown", "work", "recovery", "steady", "freeride"]
## Nazwy rodzajów dla gracza (HUD, lista planów).
const KIND_LABELS: Array[String] = ["Rozgrzewka", "Schłodzenie", "Interwał", "Regeneracja", "Jazda równa", "Jazda swobodna"]

var kind: Kind = Kind.STEADY
var duration_s: float = 0.0
## Cel na początku kroku (ułamek FTP).
var power_start: float = 0.0
## Cel na końcu kroku (ułamek FTP); równy power_start dla kroku stałego.
var power_end: float = 0.0
## Sugerowana kadencja (obr./min); 0 = brak.
var cadence_rpm: float = 0.0
## Opis kroku z pliku planu (może być pusty – wtedy display_label() daje nazwę rodzaju).
var label: String = ""


## p_power_end < 0 oznacza krok stały (power_end = power_start).
func _init(p_kind: Kind = Kind.STEADY, p_duration_s: float = 0.0, p_power_start: float = 0.0,
		p_power_end: float = -1.0, p_cadence_rpm: float = 0.0, p_label: String = "") -> void:
	kind = p_kind
	duration_s = maxf(0.0, p_duration_s)
	power_start = maxf(0.0, p_power_start)
	power_end = power_start if p_power_end < 0.0 else p_power_end
	cadence_rpm = maxf(0.0, p_cadence_rpm)
	label = p_label


## Cel (ułamek FTP) po t_in_step sekundach od początku kroku; czas przycinany do [0, duration_s].
func target_fraction_at(t_in_step: float) -> float:
	if duration_s <= 0.0:
		return power_start
	return lerpf(power_start, power_end, clampf(t_in_step / duration_s, 0.0, 1.0))


func is_ramp() -> bool:
	return absf(power_end - power_start) > 1e-6


## Czy krok ma cel mocy (FREERIDE i krok z celem 0 – nie, wtedy ERG ma być wyłączony).
func has_target() -> bool:
	return kind != Kind.FREERIDE and maxf(power_start, power_end) > 0.0


## Średni cel kroku (dla rampy liniowej to średnia z początku i końca).
func average_fraction() -> float:
	return (power_start + power_end) * 0.5


func max_fraction() -> float:
	return maxf(power_start, power_end)


func kind_name() -> String:
	return KIND_NAMES[kind]


func kind_label() -> String:
	return KIND_LABELS[kind]


## Tekst dla gracza: etykieta z planu albo nazwa rodzaju kroku.
func display_label() -> String:
	return label if label != "" else kind_label()


func copy() -> WorkoutStep:
	return WorkoutStep.new(kind, duration_s, power_start, power_end, cadence_rpm, label)


## Krótki opis do logów i testów, np. "work 4:00 105%" albo "warmup 10:00 50→75%".
func describe() -> String:
	var power := "bez celu"
	if kind != Kind.FREERIDE:
		power = "%d%%" % roundi(power_start * 100.0)
		if is_ramp():
			power = "%d→%d%%" % [roundi(power_start * 100.0), roundi(power_end * 100.0)]
	var text := "%s %s %s" % [kind_name(), format_duration(duration_s), power]
	if cadence_rpm > 0.0:
		text += " @%d rpm" % roundi(cadence_rpm)
	if label != "":
		text += " \"%s\"" % label
	return text


## Krok w naszym formacie JSON (patrz docs/plany-treningowe.md).
func to_dict() -> Dictionary:
	var d := {"type": kind_name(), "duration": _json_number(duration_s)}
	if kind != Kind.FREERIDE:
		if is_ramp():
			d["from"] = _json_number(power_start)
			d["to"] = _json_number(power_end)
		else:
			d["power"] = _json_number(power_start)
	if cadence_rpm > 0.0:
		d["cadence"] = _json_number(cadence_rpm)
	if label != "":
		d["label"] = label
	return d


## Rodzaj z nazwy JSON (bez rozróżniania wielkości liter); -1, gdy nieznany.
static func kind_from_name(kind_text: String) -> int:
	return KIND_NAMES.find(kind_text.strip_edges().to_lower())


## Rodzaj kroku bez jawnego przeznaczenia, wyznaczony z intensywności:
## od HARD_THRESHOLD praca, do RECOVERY_THRESHOLD (gdy allow_recovery) regeneracja, inaczej jazda równa.
static func kind_for_power(fraction: float, allow_recovery: bool = false) -> Kind:
	if fraction >= HARD_THRESHOLD - 1e-9:
		return Kind.WORK
	if allow_recovery and fraction <= RECOVERY_THRESHOLD + 1e-9:
		return Kind.RECOVERY
	return Kind.STEADY


## "m:ss" albo "h:mm:ss" (sekundy zaokrąglone).
static func format_duration(seconds: float) -> String:
	var s := maxi(0, roundi(seconds))
	var minutes := floori(s / 60.0)
	if s >= 3600:
		return "%d:%02d:%02d" % [floori(s / 3600.0), minutes % 60, s % 60]
	return "%d:%02d" % [minutes, s % 60]


## Liczby całkowite zapisujemy bez ".0", resztę z dokładnością do 0.0001.
static func _json_number(value: float) -> Variant:
	if absf(value - roundf(value)) < 1e-9:
		return roundi(value)
	return snappedf(value, 0.0001)
