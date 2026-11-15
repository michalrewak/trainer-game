class_name WorkoutFitParser
extends RefCounted
## Plan treningowy z pliku FIT typu „workout” (np. eksport treningu z Garmin Connect).
## Używaj przez WorkoutLoader.parse_fit(). Warstwę binarną czyta FitDecoder, tu jest tylko
## profil: file_id (0), workout (26), workout_step (27). Szczegóły i decyzje: docs/plany-treningowe.md.
##
## Czas kroku: TIME – duration_value w ms; OPEN („do naciśnięcia Lap”) – 5 min;
##   dystans – przeliczony przy 30 km/h; kalorie – przy celu mocy (1 kcal ≈ 1 kJ pracy);
##   inne warunki (tętno, moc, TSS) – 5 min. Każde przybliżenie daje ostrzeżenie.
## Powtórzenia: REPEAT_UNTIL_STEPS_CMPLT – duration_value = message_index pierwszego kroku bloku,
##   target_value = ile razy wykonać blok (łącznie); zagnieżdżenia działają. REPEAT_UNTIL_TIME –
##   tyle powtórzeń, ile mieści się w zadanym czasie; inne warunki – blok raz.
## Cel mocy (POWER i warianty 3s/10s/30s/lap): target_value 1–7 = strefa mocy, 0 = własny zakres
##   custom_target_value_low/high: 0–1000 = % FTP, >1000 = waty + 1000 (przeliczane na ułamek
##   FTP podanym ftp, domyślnie 250 W). Zakres -> środek zakresu; dla rozgrzewki rampa od dołu
##   do góry zakresu, dla schłodzenia od góry do dołu (cały czas w zakresie).
## Cel OPEN albo brak celu -> jazda swobodna (FREERIDE). Inne cele (tętno, prędkość, kadencja...)
##   -> stała moc szacowana z intensywności/strefy, etykieta mówi, jaki był cel oryginalny.
## Rodzaj z intensity: active -> WORK/STEADY wg mocy, rest/recovery -> RECOVERY, warmup -> WARMUP,
##   cooldown -> COOLDOWN, interval -> WORK.

const MESG_FILE_ID := 0
const MESG_WORKOUT := 26
const MESG_WORKOUT_STEP := 27

const FILE_ID_TYPE := 0
const FILE_TYPE_WORKOUT := 5

const WKT_SPORT := 4
const WKT_NUM_VALID_STEPS := 6
const WKT_NAME := 8
const WKT_DESCRIPTION := 17

const STEP_MESSAGE_INDEX := 254
const STEP_NAME := 0
const STEP_DURATION_TYPE := 1
const STEP_DURATION_VALUE := 2
const STEP_TARGET_TYPE := 3
const STEP_TARGET_VALUE := 4
const STEP_CUSTOM_LOW := 5
const STEP_CUSTOM_HIGH := 6
const STEP_INTENSITY := 7
const STEP_NOTES := 8
const STEP_SECONDARY_TARGET_TYPE := 19
const STEP_SECONDARY_TARGET_VALUE := 20
const STEP_SECONDARY_CUSTOM_LOW := 21
const STEP_SECONDARY_CUSTOM_HIGH := 22

# wkt_step_duration
const DUR_TIME := 0
const DUR_DISTANCE := 1
const DUR_HR_LESS_THAN := 2
const DUR_HR_GREATER_THAN := 3
const DUR_CALORIES := 4
const DUR_OPEN := 5
const DUR_REPEAT_UNTIL_STEPS_CMPLT := 6
const DUR_REPEAT_UNTIL_TIME := 7
const DUR_REPEAT_UNTIL_DISTANCE := 8
const DUR_REPEAT_UNTIL_CALORIES := 9
const DUR_REPEAT_UNTIL_HR_LESS_THAN := 10
const DUR_REPEAT_UNTIL_HR_GREATER_THAN := 11
const DUR_REPEAT_UNTIL_POWER_LESS_THAN := 12
const DUR_REPEAT_UNTIL_POWER_GREATER_THAN := 13
const DUR_POWER_LESS_THAN := 14
const DUR_POWER_GREATER_THAN := 15
const DUR_TRAINING_PEAKS_TSS := 16
const DUR_REPETITION_TIME := 28
const DUR_REPS := 29
const DUR_TIME_ONLY := 31
const REPEAT_DURATIONS: Array[int] = [6, 7, 8, 9, 10, 11, 12, 13, 17, 18, 27]
const TIME_DURATIONS: Array[int] = [DUR_TIME, DUR_REPETITION_TIME, DUR_TIME_ONLY]

# wkt_step_target
const TGT_SPEED := 0
const TGT_HEART_RATE := 1
const TGT_OPEN := 2
const TGT_CADENCE := 3
const TGT_POWER := 4
const TGT_GRADE := 5
const TGT_RESISTANCE := 6
const TGT_POWER_3S := 7
const TGT_POWER_10S := 8
const TGT_POWER_30S := 9
const TGT_POWER_LAP := 10
const TGT_SWIM_STROKE := 11
const TGT_SPEED_LAP := 12
const TGT_HEART_RATE_LAP := 13
const POWER_TARGETS: Array[int] = [TGT_POWER, TGT_POWER_3S, TGT_POWER_10S, TGT_POWER_30S, TGT_POWER_LAP]

# intensity
const INT_ACTIVE := 0
const INT_REST := 1
const INT_WARMUP := 2
const INT_COOLDOWN := 3
const INT_RECOVERY := 4
const INT_INTERVAL := 5
const INT_OTHER := 6

const SPORT_GENERIC := 0
const SPORT_CYCLING := 2

## Krok „do naciśnięcia Lap” (i inne warunki, których gra nie sprawdza) trwa tyle sekund.
const OPEN_STEP_S := 300.0
## Prędkość do przeliczania kroków na dystans (30 km/h).
const ASSUMED_SPEED_MPS := 30.0 / 3.6
## Typowe ułamki FTP dla stref mocy 1–7 (Coggan: środek strefy; strefa 7 jak MaxEffort).
const POWER_ZONE_FRACTIONS := {1: 0.50, 2: 0.65, 3: 0.83, 4: 0.98, 5: 1.13, 6: 1.35, 7: 1.50}
## Szacunek mocy dla stref tętna 1–5.
const HR_ZONE_FRACTIONS := {1: 0.50, 2: 0.65, 3: 0.80, 4: 0.92, 5: 1.05}
## Szacunek mocy, gdy cel nie jest mocą (prędkość, kadencja...) – według intensywności kroku.
const INTENSITY_FRACTIONS := {INT_ACTIVE: 0.70, INT_REST: 0.50, INT_WARMUP: 0.55, INT_COOLDOWN: 0.50, INT_RECOVERY: 0.50, INT_INTERVAL: 0.90, INT_OTHER: 0.65}
const MAX_FRACTION := 3.0
const MAX_REPEAT := 100
const MAX_STEPS := 5000
const MAX_TOTAL_S := 12.0 * 3600.0

const FILE_TYPE_NAMES := {
	1: "plik urządzenia", 2: "ustawienia", 3: "profil sportu", 4: "zapis aktywności (jazdy)",
	6: "trasa (course)", 7: "harmonogram treningów", 9: "pomiary wagi", 10: "podsumowania",
	11: "cele", 14: "pomiary ciśnienia", 15: "dane monitoringu", 20: "podsumowanie aktywności",
	28: "dane monitoringu dziennego", 32: "dane monitoringu", 34: "segment", 35: "lista segmentów",
}
const DURATION_NAMES := {
	DUR_HR_LESS_THAN: "tętno poniżej", DUR_HR_GREATER_THAN: "tętno powyżej",
	DUR_POWER_LESS_THAN: "moc poniżej", DUR_POWER_GREATER_THAN: "moc powyżej",
	DUR_TRAINING_PEAKS_TSS: "TSS", DUR_REPS: "powtórzenia ćwiczenia",
	DUR_REPEAT_UNTIL_DISTANCE: "dystans", DUR_REPEAT_UNTIL_CALORIES: "kalorie",
	DUR_REPEAT_UNTIL_HR_LESS_THAN: "tętno poniżej", DUR_REPEAT_UNTIL_HR_GREATER_THAN: "tętno powyżej",
	DUR_REPEAT_UNTIL_POWER_LESS_THAN: "moc poniżej", DUR_REPEAT_UNTIL_POWER_GREATER_THAN: "moc powyżej",
}
const INTENSITY_LABELS := {INT_WARMUP: "Rozgrzewka", INT_COOLDOWN: "Schłodzenie", INT_REST: "Odpoczynek", INT_RECOVERY: "Regeneracja", INT_INTERVAL: "Interwał"}

var _ftp := WorkoutLoader.DEFAULT_FTP
var _used_watts := false
var _error := ""
var _warnings: Array[String] = []


func parse(bytes: PackedByteArray, ftp: float = WorkoutLoader.DEFAULT_FTP) -> Dictionary:
	_ftp = ftp if ftp > 0.0 else WorkoutLoader.DEFAULT_FTP
	_used_watts = false
	_error = ""
	_warnings.clear()
	var dec := FitDecoder.new()
	if not dec.open(bytes):
		return WorkoutLoader.failure(dec.error, dec.warnings)
	var seen_file_id := false
	var file_type: Variant = null
	var workout := {}
	var workouts := 0
	var step_fields: Array[Dictionary] = []
	while true:
		var msg := dec.next_message()
		if msg.is_empty():
			break
		var fields: Dictionary = msg["fields"]
		match int(msg["global"]):
			MESG_FILE_ID:
				if not seen_file_id:
					seen_file_id = true
					file_type = fields.get(FILE_ID_TYPE)
					if file_type is int and file_type != FILE_TYPE_WORKOUT:
						return WorkoutLoader.failure(_not_workout_message(file_type), dec.warnings)
			MESG_WORKOUT:
				workouts += 1
				if workouts == 1:
					workout = fields
			MESG_WORKOUT_STEP:
				step_fields.append(fields)
	if dec.error != "":
		return WorkoutLoader.failure(dec.error, dec.warnings)
	dec.verify_file_crc()
	_warnings.append_array(dec.warnings)
	if not seen_file_id:
		_warnings.append("Brak wiadomości file_id – zakładam, że to plik treningu.")
	elif not file_type is int:
		_warnings.append("Wiadomość file_id bez typu pliku – zakładam, że to plik treningu.")
	if workouts > 1:
		_warnings.append("Plik zawiera %d treningi – wczytuję pierwszy." % workouts)
	if step_fields.is_empty():
		return WorkoutLoader.failure("Plik FIT nie zawiera kroków treningu (workout_step).", _warnings)
	var plan := WorkoutPlan.new()
	plan.source_format = "fit"
	plan.name = _text(workout, WKT_NAME)
	plan.description = _text(workout, WKT_DESCRIPTION)
	var sport: Variant = workout.get(WKT_SPORT)
	if sport is int and sport != SPORT_CYCLING and sport != SPORT_GENERIC:
		_warnings.append("To trening dla innego sportu niż kolarstwo (sport %d) – cele odczytane jak dla roweru." % sport)
	var declared: Variant = workout.get(WKT_NUM_VALID_STEPS)
	if declared is int and declared != step_fields.size():
		_warnings.append("Plik deklaruje %d kroków, a zawiera %d." % [declared, step_fields.size()])
	var steps := _build_steps(step_fields)
	if _error != "":
		return WorkoutLoader.failure(_error, _warnings)
	if steps.is_empty():
		return WorkoutLoader.failure("Trening w pliku FIT nie ma żadnego kroku z czasem trwania.", _warnings)
	plan.steps = steps
	if plan.total_duration_s() > MAX_TOTAL_S:
		return WorkoutLoader.failure("Trening trwa dłużej niż 12 h – plik jest prawdopodobnie uszkodzony.", _warnings)
	plan.reference_ftp = _ftp if _used_watts else 0.0
	return WorkoutLoader.success(plan, _warnings)


static func _not_workout_message(file_type: int) -> String:
	var what: String = FILE_TYPE_NAMES.get(file_type, "plik FIT typu %d" % file_type)
	return "To nie jest plan treningowy, tylko %s. Wyeksportuj z Garmin Connect trening (plik FIT typu workout)." % what


# --- Kroki i powtórzenia ------------------------------------------------------

func _build_steps(step_fields: Array[Dictionary]) -> Array[WorkoutStep]:
	var out: Array[WorkoutStep] = []
	var ordered := _ordered(step_fields)
	var first_pos := {}
	for entry: Array in ordered:
		var index: int = entry[0]
		var f: Dictionary = entry[1]
		first_pos[index] = out.size()
		var duration_type: Variant = f.get(STEP_DURATION_TYPE)
		if duration_type is int and REPEAT_DURATIONS.has(duration_type):
			_expand_repeat(f, duration_type, index, first_pos, out)
		else:
			var step := _convert_step(f, index)
			if step != null:
				out.append(step)
		if _error != "":
			return out
		if out.size() > MAX_STEPS:
			_error = "Trening ma więcej niż %d kroków po rozwinięciu powtórzeń." % MAX_STEPS
			return out
	return out


## Pary [message_index, pola] w kolejności kroków. Bez poprawnych (unikalnych) message_index –
## kolejność z pliku.
func _ordered(step_fields: Array[Dictionary]) -> Array:
	var pairs: Array = []
	var seen := {}
	var indexed := true
	for f in step_fields:
		var mi: Variant = f.get(STEP_MESSAGE_INDEX)
		if not mi is int or seen.has(int(mi) & 0x0FFF):
			indexed = false
			break
		seen[int(mi) & 0x0FFF] = true
	for i in step_fields.size():
		var index: int = (int(step_fields[i][STEP_MESSAGE_INDEX]) & 0x0FFF) if indexed else i
		pairs.append([index, step_fields[i]])
	if indexed:
		pairs.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	elif step_fields.size() > 1:
		_warnings.append("Kroki bez poprawnych numerów (message_index) – używam kolejności z pliku.")
	return pairs


func _expand_repeat(f: Dictionary, duration_type: int, index: int, first_pos: Dictionary, out: Array[WorkoutStep]) -> void:
	var from_v: Variant = f.get(STEP_DURATION_VALUE)
	var from := int(from_v) if from_v is int else -1
	if from < 0 or from >= index or not first_pos.has(from):
		_warnings.append("Krok %d: powtórzenie odwołuje się do nieistniejącego kroku – pominięte." % (index + 1))
		return
	var start: int = first_pos[from]
	var block: Array[WorkoutStep] = out.slice(start)
	if block.is_empty():
		_warnings.append("Krok %d: powtórzenie pustego bloku – pominięte." % (index + 1))
		return
	var value: Variant = f.get(STEP_TARGET_VALUE)
	var count := 1
	match duration_type:
		DUR_REPEAT_UNTIL_STEPS_CMPLT:
			if value is int and value >= 1:
				count = value
			else:
				_warnings.append("Krok %d: brak liczby powtórzeń – blok wykonany raz." % (index + 1))
		DUR_REPEAT_UNTIL_TIME:
			var block_s := 0.0
			for s in block:
				block_s += s.duration_s
			if value is int and value > 0 and block_s > 0.0:
				count = maxi(1, ceili(value / 1000.0 / block_s))
				_warnings.append("Krok %d: „powtarzaj do czasu %s” – przyjęto %d powtórzeń bloku." % [index + 1, WorkoutStep.format_duration(value / 1000.0), count])
			else:
				_warnings.append("Krok %d: powtarzanie do czasu bez czasu – blok wykonany raz." % (index + 1))
		_:
			_warnings.append("Krok %d: powtarzanie do warunku (%s) nie jest obsługiwane – blok wykonany raz." % [index + 1, DURATION_NAMES.get(duration_type, "typ %d" % duration_type)])
	if count > MAX_REPEAT:
		_error = "Krok %d: %d powtórzeń to za dużo (najwyżej %d) – plik jest prawdopodobnie uszkodzony." % [index + 1, count, MAX_REPEAT]
		return
	if out.size() + block.size() * (count - 1) > MAX_STEPS:
		_error = "Trening ma więcej niż %d kroków po rozwinięciu powtórzeń." % MAX_STEPS
		return
	for r in count - 1:
		for s in block:
			out.append(s.copy())


func _convert_step(f: Dictionary, index: int) -> WorkoutStep:
	var number := index + 1
	var label := _text(f, STEP_NAME)
	if label == "":
		label = _text(f, STEP_NOTES)
	var intensity_v: Variant = f.get(STEP_INTENSITY)
	var intensity: int = intensity_v if intensity_v is int else INT_ACTIVE
	var target := _target(f.get(STEP_TARGET_TYPE), f.get(STEP_TARGET_VALUE), f.get(STEP_CUSTOM_LOW), f.get(STEP_CUSTOM_HIGH), intensity, number)
	var secondary := _target(f.get(STEP_SECONDARY_TARGET_TYPE), f.get(STEP_SECONDARY_TARGET_VALUE), f.get(STEP_SECONDARY_CUSTOM_LOW), f.get(STEP_SECONDARY_CUSTOM_HIGH), intensity, number)
	if not target["power"] and secondary["power"]:
		# Cel główny nie jest mocą (np. tętno), ale drugi cel jest – bierzemy moc.
		var swap := target
		target = secondary
		secondary = swap
	var cadence: float = target["cadence"] if target["cadence"] > 0.0 else secondary["cadence"]
	var note: String = target["note"]
	if note != "":
		label = "%s (cel: %s)" % [label, note] if label != "" else "Cel: %s" % note
	var has_power: bool = target["power"] or target["estimated"]
	var low: float = target["low"]
	var high: float = target["high"]
	var duration := _duration(f, number, (low + high) * 0.5 if has_power else 0.0)
	if duration <= 0.0:
		return null
	if not has_power:
		if label == "" and INTENSITY_LABELS.has(intensity):
			label = "%s – bez celu mocy" % INTENSITY_LABELS[intensity]
		return WorkoutStep.new(WorkoutStep.Kind.FREERIDE, duration, 0.0, 0.0, cadence, label)
	var mid := (low + high) * 0.5
	match intensity:
		INT_WARMUP:
			return WorkoutStep.new(WorkoutStep.Kind.WARMUP, duration, low, high, cadence, label)
		INT_COOLDOWN:
			return WorkoutStep.new(WorkoutStep.Kind.COOLDOWN, duration, high, low, cadence, label)
		INT_REST, INT_RECOVERY:
			return WorkoutStep.new(WorkoutStep.Kind.RECOVERY, duration, mid, mid, cadence, label)
		INT_INTERVAL:
			return WorkoutStep.new(WorkoutStep.Kind.WORK, duration, mid, mid, cadence, label)
		_:
			return WorkoutStep.new(WorkoutStep.kind_for_power(mid), duration, mid, mid, cadence, label)


## Czas kroku w sekundach (0 = pominąć). fraction = cel mocy do przeliczenia kalorii.
func _duration(f: Dictionary, number: int, fraction: float) -> float:
	var type_v: Variant = f.get(STEP_DURATION_TYPE)
	var duration_type: int = type_v if type_v is int else DUR_OPEN
	var value: Variant = f.get(STEP_DURATION_VALUE)
	var seconds := 0.0
	if TIME_DURATIONS.has(duration_type):
		if not value is int or value <= 0:
			_warnings.append("Krok %d: brak czasu trwania – pominięty." % number)
			return 0.0
		seconds = value / 1000.0
	elif duration_type == DUR_OPEN:
		seconds = OPEN_STEP_S
		_warnings.append("Krok %d: „do naciśnięcia Lap” – przyjęto %s." % [number, WorkoutStep.format_duration(OPEN_STEP_S)])
	elif duration_type == DUR_DISTANCE and value is int and value > 0:
		var meters: float = value / 100.0
		seconds = meters / ASSUMED_SPEED_MPS
		_warnings.append("Krok %d: dystans %.1f km – przyjęto %s (30 km/h)." % [number, meters / 1000.0, WorkoutStep.format_duration(seconds)])
	elif duration_type == DUR_CALORIES and value is int and value > 0:
		# 1 kcal spalona ≈ 1 kJ pracy na pedałach (sprawność ok. 24%).
		var watts := maxf(fraction * _ftp, 100.0)
		seconds = value * 1000.0 / watts
		_warnings.append("Krok %d: %d kcal – przyjęto %s przy %d W." % [number, value, WorkoutStep.format_duration(seconds), roundi(watts)])
	else:
		seconds = OPEN_STEP_S
		_warnings.append("Krok %d: warunek końca (%s) nie jest obsługiwany – przyjęto %s." % [number, DURATION_NAMES.get(duration_type, "typ %d" % duration_type), WorkoutStep.format_duration(OPEN_STEP_S)])
	if seconds > MAX_TOTAL_S:
		_error = "Krok %d: czas trwania ponad 12 h – plik jest prawdopodobnie uszkodzony." % number
		return 0.0
	return seconds


## Cel kroku: {"power": bool (cel mocy), "estimated": bool (moc oszacowana z innego celu),
## "low", "high" (ułamki FTP), "cadence" (obr./min), "note" (opis celu innego niż moc)}.
func _target(type_v: Variant, value_v: Variant, low_v: Variant, high_v: Variant, intensity: int, number: int) -> Dictionary:
	var t := {"power": false, "estimated": false, "low": 0.0, "high": 0.0, "cadence": 0.0, "note": ""}
	if not type_v is int or type_v == TGT_OPEN:
		return t
	var target_type: int = type_v
	var value: int = value_v if value_v is int else 0
	var low: int = low_v if low_v is int else -1
	var high: int = high_v if high_v is int else -1
	if POWER_TARGETS.has(target_type):
		if value >= 1 and value <= 7:
			t["power"] = true
			t["low"] = POWER_ZONE_FRACTIONS[value]
			t["high"] = t["low"]
			return t
		if value != 0:
			_warnings.append("Krok %d: nieznana strefa mocy %d – próbuję własnego zakresu." % [number, value])
		var lo := _power_fraction(low, number)
		var hi := _power_fraction(high, number)
		if lo < 0.0:
			lo = hi
		if hi < 0.0:
			hi = lo
		if hi <= 0.0:
			_warnings.append("Krok %d: cel mocy bez wartości – jazda swobodna." % number)
			return t
		t["power"] = true
		t["low"] = minf(lo, hi)
		t["high"] = maxf(lo, hi)
		return t
	var estimate: float = INTENSITY_FRACTIONS.get(intensity, 0.65)
	var has_range := low > 0 or high > 0
	var note := ""
	match target_type:
		TGT_HEART_RATE, TGT_HEART_RATE_LAP:
			if value >= 1 and value <= 5:
				estimate = HR_ZONE_FRACTIONS[value]
				note = "tętno strefa %d" % value
			elif maxi(low, high) > 100:
				# Tętno w ud./min zapisuje się jako bpm + 100.
				note = "tętno %s ud./min" % _range_text(low - 100 if low > 100 else -1, high - 100 if high > 100 else -1)
			elif has_range:
				note = "tętno %s%% HRmax" % _range_text(low, high)
			else:
				note = "tętno"
		TGT_SPEED, TGT_SPEED_LAP:
			if value >= 1:
				note = "prędkość strefa %d" % value
			elif has_range:
				# Prędkość w mm/s (m/s * 1000) -> km/h.
				note = "prędkość %s km/h" % _range_text(low * 0.0036 if low > 0 else -1.0, high * 0.0036 if high > 0 else -1.0, 1)
			else:
				note = "prędkość"
		TGT_CADENCE:
			if value >= 1:
				note = "kadencja strefa %d" % value
			elif has_range:
				note = "kadencja %s obr./min" % _range_text(low, high)
				var c := _midpoint(low, high)
				if c > 0.0 and c <= 250.0:
					t["cadence"] = c
			else:
				note = "kadencja"
		TGT_GRADE:
			note = "nachylenie"
		TGT_RESISTANCE:
			note = "opór"
		TGT_SWIM_STROKE:
			note = "styl pływacki"
		_:
			note = "typ %d" % target_type
	t["estimated"] = true
	t["low"] = estimate
	t["high"] = estimate
	t["note"] = note
	return t


## Wartość mocy FIT -> ułamek FTP: 0–1000 = % FTP, >1000 = waty + 1000. -1 = brak.
func _power_fraction(raw: int, number: int) -> float:
	if raw < 0:
		return -1.0
	if raw > 1000:
		_used_watts = true
	var fraction := raw / 100.0 if raw <= 1000 else (raw - 1000) / _ftp
	if fraction > MAX_FRACTION:
		_warnings.append("Krok %d: cel mocy ponad 300%% FTP – ograniczony do 300%%." % number)
		fraction = MAX_FRACTION
	return fraction


static func _midpoint(low: int, high: int) -> float:
	if low > 0 and high > 0:
		return (low + high) * 0.5
	return float(maxi(low, high)) if maxi(low, high) > 0 else 0.0


## "140–150" albo jedna wartość, gdy druga brakuje (<= 0) lub obie są równe.
static func _range_text(low: float, high: float, decimals: int = 0) -> String:
	var fmt := "%." + str(decimals) + "f"
	var a := minf(low, high)
	var b := maxf(low, high)
	if a > 0.0 and b > a:
		return (fmt + "–" + fmt) % [a, b]
	return fmt % b


static func _text(fields: Dictionary, num: int) -> String:
	var v: Variant = fields.get(num)
	return (v as String).strip_edges() if v is String else ""
