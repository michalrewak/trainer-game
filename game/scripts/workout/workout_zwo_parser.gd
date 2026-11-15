class_name WorkoutZwoParser
extends RefCounted
## Parser plików treningów Zwift (.zwo – XML) na XMLParser Godota. Używaj przez
## WorkoutLoader.parse_zwo(). Wielkość liter w nazwach elementów i atrybutów nie ma
## znaczenia (PowerLow = powerlow = POWERLOW).
##
## <workout_file> → <name>, <description>, <sportType>, <workout> z krokami:
##   Warmup / Cooldown / Ramp (Duration, PowerLow, PowerHigh) – rampa liniowa;
##     Warmup i Ramp: od PowerLow do PowerHigh, Cooldown zawsze w dół (od większej do mniejszej);
##   SteadyState (Duration, Power) – stały cel (SolidState jak SteadyState);
##   IntervalsT (Repeat, OnDuration, OffDuration, OnPower, OffPower, Cadence, CadenceResting)
##     – rozwijane na Repeat par WORK + RECOVERY;
##   FreeRide (Duration) – jazda swobodna; MaxEffort (Duration) – WORK na 150% FTP;
##   textevent (komunikaty tekstowe) – pomijane.
## Rodzaj kroków bez jawnego przeznaczenia (SteadyState, Ramp) wynika z mocy: >= 0.88 FTP praca,
## <= 0.55 FTP regeneracja, pomiędzy jazda równa.

const MAX_EFFORT_FRACTION := 1.5
const MAX_FRACTION := 3.0
const MAX_CADENCE := 250.0
const MAX_REPEAT := 100
const MAX_STEPS := 5000
const MAX_TOTAL_S := 12.0 * 3600.0

var _error := ""
var _warnings: Array[String] = []
var _plan := WorkoutPlan.new()
var _tag := ""
var _line := 0
var _total := 0.0


func parse(text: String) -> Dictionary:
	_error = ""
	_warnings.clear()
	_plan = WorkoutPlan.new()
	_tag = ""
	_line = 0
	_total = 0.0
	var body := text.trim_prefix(char(0xFEFF))
	if body.strip_edges() == "":
		return WorkoutLoader.failure("Plik ZWO jest pusty.")
	var xml := XMLParser.new()
	if xml.open_buffer(body.to_utf8_buffer()) != OK:
		return WorkoutLoader.failure("Nie można odczytać pliku ZWO jako XML.")
	_plan.source_format = "zwo"
	var stack: Array[String] = []
	var seen_root := false
	var seen_workout := false
	var capture := ""
	var captured := ""
	var sport := ""
	while true:
		var err := xml.read()
		if err == ERR_FILE_EOF:
			break
		if err != OK:
			return WorkoutLoader.failure("Błąd XML w linii %d." % (xml.get_current_line() + 1), _warnings)
		match xml.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag := xml.get_node_name().to_lower()
				_line = xml.get_current_line() + 1
				if not seen_root:
					if tag != "workout_file":
						return WorkoutLoader.failure("To nie jest plik treningu Zwift – brak elementu <workout_file>.", _warnings)
					seen_root = true
				elif stack.is_empty():
					return WorkoutLoader.failure("Nieprawidłowy XML: dane za zamknięciem </workout_file> (linia %d)." % _line, _warnings)
				var parent := stack[stack.size() - 1] if not stack.is_empty() else ""
				if parent == "workout_file":
					if tag == "workout":
						seen_workout = true
					elif tag == "name" or tag == "description" or tag == "sporttype":
						capture = tag
						captured = ""
				elif parent == "workout":
					_handle_step(tag, _attributes(xml))
					if _error != "":
						return WorkoutLoader.failure(_error, _warnings)
				if not xml.is_empty():
					stack.append(tag)
				elif capture == tag:
					capture = ""
			XMLParser.NODE_ELEMENT_END:
				var tag := xml.get_node_name().to_lower()
				if stack.is_empty() or stack[stack.size() - 1] != tag:
					return WorkoutLoader.failure("Nieprawidłowy XML: niepasujący znacznik </%s> w linii %d." % [xml.get_node_name(), xml.get_current_line() + 1], _warnings)
				stack.pop_back()
				if capture == tag and stack.size() == 1:
					match tag:
						"name":
							_plan.name = captured.strip_edges()
						"description":
							_plan.description = captured.strip_edges()
						_:
							sport = captured.strip_edges().to_lower()
					capture = ""
			XMLParser.NODE_TEXT:
				if capture != "":
					captured += xml.get_node_data()
			XMLParser.NODE_CDATA:
				if capture != "":
					captured += xml.get_node_name()
	if not seen_root:
		return WorkoutLoader.failure("To nie jest plik treningu Zwift – brak elementu <workout_file>.", _warnings)
	if not stack.is_empty():
		return WorkoutLoader.failure("Niekompletny plik XML – brak zamknięcia <%s>." % stack[stack.size() - 1], _warnings)
	if not seen_workout:
		return WorkoutLoader.failure("Brak sekcji <workout> z krokami treningu.", _warnings)
	if _plan.steps.is_empty():
		return WorkoutLoader.failure("Trening nie zawiera żadnych kroków.", _warnings)
	if sport != "" and sport != "bike":
		_warnings.append("To trening typu „%s” (nie rowerowy) – cele mocy odczytane jak dla roweru." % sport)
	return WorkoutLoader.success(_plan, _warnings)


func _fail(message: String) -> void:
	if _error == "":
		_error = "<%s> w linii %d: %s" % [_tag, _line, message]


func _warn(message: String) -> void:
	_warnings.append("<%s> w linii %d: %s" % [_tag, _line, message])


static func _attributes(xml: XMLParser) -> Dictionary:
	var out := {}
	for i in xml.get_attribute_count():
		out[xml.get_attribute_name(i).to_lower()] = xml.get_attribute_value(i).strip_edges()
	return out


func _handle_step(tag: String, a: Dictionary) -> void:
	_tag = tag
	match tag:
		"warmup", "cooldown", "ramp":
			_ramp_step(tag, a)
		"steadystate", "solidstate":
			_steady_step(a)
		"intervalst":
			_intervals(a)
		"freeride":
			_free_ride(a)
		"maxeffort":
			_max_effort(a)
		"textevent", "text_event":
			pass
		_:
			_warn("nieznany element – pominięty.")


func _ramp_step(tag: String, a: Dictionary) -> void:
	var duration := _duration(a, "duration")
	if duration <= 0.0:
		return
	var low := _power(a, "powerlow")
	var high := _power(a, "powerhigh")
	if low < 0.0 or high < 0.0:
		var p := _power(a, "power")
		if p < 0.0:
			_fail("brak atrybutów PowerLow i PowerHigh.")
			return
		low = p
		high = p
	var start := low
	var end := high
	var kind := WorkoutStep.Kind.STEADY
	match tag:
		"warmup":
			kind = WorkoutStep.Kind.WARMUP
		"cooldown":
			# Schłodzenie zawsze w dół – pliki bywają zapisane w obu konwencjach.
			kind = WorkoutStep.Kind.COOLDOWN
			start = maxf(low, high)
			end = minf(low, high)
		_:
			kind = WorkoutStep.kind_for_power((low + high) * 0.5, true)
	_add(WorkoutStep.new(kind, duration, start, end, _cadence(a, "cadence")))


func _steady_step(a: Dictionary) -> void:
	var duration := _duration(a, "duration")
	if duration <= 0.0:
		return
	var p := _power(a, "power")
	if p < 0.0:
		var low := _power(a, "powerlow")
		var high := _power(a, "powerhigh")
		if low < 0.0 or high < 0.0:
			_fail("brak atrybutu Power.")
			return
		p = (low + high) * 0.5
	_add(WorkoutStep.new(WorkoutStep.kind_for_power(p, true), duration, p, p, _cadence(a, "cadence")))


func _intervals(a: Dictionary) -> void:
	var repeat := 1
	if a.has("repeat"):
		var text: String = a["repeat"]
		if not text.is_valid_float() or text.to_float() != floorf(text.to_float()) or text.to_float() < 1.0 or text.to_float() > MAX_REPEAT:
			_fail("Repeat musi być liczbą całkowitą od 1 do %d (jest „%s”)." % [MAX_REPEAT, text])
			return
		repeat = int(text.to_float())
	var on_s := _duration(a, "onduration")
	if on_s <= 0.0:
		return
	var off_s := _duration(a, "offduration", true)
	if _error != "":
		return
	var on_power := _interval_power(a, "onpower", "poweronlow", "poweronhigh")
	if _error != "":
		return
	var off_power := PackedFloat64Array([0.0, 0.0])
	if off_s > 0.0:
		off_power = _interval_power(a, "offpower", "powerofflow", "poweroffhigh")
		if _error != "":
			return
	var on_cadence := _cadence(a, "cadence")
	var off_cadence := _cadence(a, "cadenceresting")
	for r in repeat:
		_add(WorkoutStep.new(WorkoutStep.Kind.WORK, on_s, on_power[0], on_power[1], on_cadence))
		if off_s > 0.0:
			_add(WorkoutStep.new(WorkoutStep.Kind.RECOVERY, off_s, off_power[0], off_power[1], off_cadence))
		if _error != "":
			return


## Cel części interwału: stały (OnPower) albo rampa (PowerOnLow -> PowerOnHigh): [start, koniec].
func _interval_power(a: Dictionary, key: String, low_key: String, high_key: String) -> PackedFloat64Array:
	var p := _power(a, key)
	if p >= 0.0:
		return PackedFloat64Array([p, p])
	var low := _power(a, low_key)
	var high := _power(a, high_key)
	if low >= 0.0 and high >= 0.0:
		return PackedFloat64Array([low, high])
	if _error == "":
		_fail("brak atrybutu %s." % _attr_name(key))
	return PackedFloat64Array([0.0, 0.0])


func _free_ride(a: Dictionary) -> void:
	var duration := _duration(a, "duration")
	if duration > 0.0:
		_add(WorkoutStep.new(WorkoutStep.Kind.FREERIDE, duration, 0.0, 0.0, _cadence(a, "cadence")))


func _max_effort(a: Dictionary) -> void:
	var duration := _duration(a, "duration")
	if duration > 0.0:
		_add(WorkoutStep.new(WorkoutStep.Kind.WORK, duration, MAX_EFFORT_FRACTION, MAX_EFFORT_FRACTION, 0.0, "Maksymalny wysiłek"))


## Czas w sekundach; 0 = krok pominięty (zerowy czas – ostrzeżenie albo błąd ustawiony w _error).
## optional: brak atrybutu daje 0 bez ostrzeżenia (np. OffDuration).
func _duration(a: Dictionary, key: String, optional: bool = false) -> float:
	if not a.has(key):
		if not optional:
			_fail("brak atrybutu %s." % _attr_name(key))
		return 0.0
	var text: String = a[key]
	if not text.is_valid_float() or not is_finite(text.to_float()):
		_fail("nieprawidłowy czas %s=„%s”." % [_attr_name(key), text])
		return 0.0
	var value := text.to_float()
	if value < 0.0:
		_fail("czas %s nie może być ujemny." % _attr_name(key))
		return 0.0
	if value > MAX_TOTAL_S:
		_fail("czas %s dłuższy niż 12 h." % _attr_name(key))
		return 0.0
	if value == 0.0 and not optional:
		_warn("zerowy czas – krok pominięty.")
	return value


## Moc (ułamek FTP) z atrybutu; -1, gdy atrybutu nie ma (błąd ustawiany tylko dla złej wartości).
func _power(a: Dictionary, key: String) -> float:
	if not a.has(key):
		return -1.0
	var text: String = a[key]
	if not text.is_valid_float() or not is_finite(text.to_float()):
		_fail("nieprawidłowa moc %s=„%s”." % [_attr_name(key), text])
		return -1.0
	var value := text.to_float()
	if value < 0.0 or value > MAX_FRACTION:
		_fail("moc %s=„%s” poza zakresem 0–3 (ZWO zapisuje moc jako ułamek FTP, np. 0.75)." % [_attr_name(key), text])
		return -1.0
	return value


## Kadencja (obr./min): atrybut key albo średnia z CadenceLow/CadenceHigh; zła wartość = ostrzeżenie i 0.
func _cadence(a: Dictionary, key: String) -> float:
	var values: Array[float] = []
	var keys: Array[String] = []
	if a.has(key) or key != "cadence":
		keys.append(key)
	else:
		keys.append("cadencelow")
		keys.append("cadencehigh")
	for k in keys:
		if not a.has(k):
			continue
		var text: String = a[k]
		if text.is_valid_float() and text.to_float() >= 0.0 and text.to_float() <= MAX_CADENCE:
			values.append(text.to_float())
		else:
			_warn("nieprawidłowa kadencja %s=„%s” – pominięta." % [_attr_name(k), text])
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for v in values:
		sum += v
	return sum / values.size()


func _add(step: WorkoutStep) -> void:
	if _error != "":
		return
	if _plan.steps.size() >= MAX_STEPS:
		_fail("trening ma więcej niż %d kroków." % MAX_STEPS)
		return
	_total += step.duration_s
	if _total > MAX_TOTAL_S:
		_fail("trening trwa dłużej niż 12 h.")
		return
	_plan.add_step(step)


## Nazwa atrybutu tak, jak w dokumentacji Zwift (do komunikatów).
static func _attr_name(key: String) -> String:
	const NAMES := {
		"duration": "Duration", "power": "Power", "powerlow": "PowerLow", "powerhigh": "PowerHigh",
		"onduration": "OnDuration", "offduration": "OffDuration", "onpower": "OnPower", "offpower": "OffPower",
		"poweronlow": "PowerOnLow", "poweronhigh": "PowerOnHigh", "powerofflow": "PowerOffLow",
		"poweroffhigh": "PowerOffHigh", "cadence": "Cadence", "cadenceresting": "CadenceResting",
		"cadencelow": "CadenceLow", "cadencehigh": "CadenceHigh", "repeat": "Repeat",
	}
	return NAMES.get(key, key)
