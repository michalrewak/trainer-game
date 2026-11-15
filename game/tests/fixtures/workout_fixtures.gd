class_name WorkoutFixtures
extends RefCounted
## Definicje plików FIT używanych w testach (game/tests/fixtures/workouts/*.fit).
## Pliki w repozytorium generuje (po zmianie tego skryptu):
##   godot --headless --path game --script res://tests/fixtures/make_workout_fixtures.gd
## Test test_workout_fit sprawdza, że pliki w repo są identyczne z tym, co powstaje tutaj.

const DIR := "res://tests/fixtures/workouts"
## Stały czas utworzenia (s od 1989-12-31 UTC) – pliki są deterministyczne.
const TIME_CREATED := 1_100_000_000
## Producent 255 = „development” w profilu FIT (pliki nie udają plików Garmina).
const MANUFACTURER_DEVELOPMENT := 255

## Skrót do stałych profilu FIT (numery wiadomości, pól, typy czasu/celu, intensywność).
const P := preload("res://scripts/workout/workout_fit_parser.gd")


## Plik FIT typu workout z kroków opisanych słownikami:
##   name, notes, duration_type, duration_value, target_type, target_value, low, high,
##   intensity, secondary_type, secondary_low, secondary_high (brak klucza = wartość nieprawidłowa).
## Opcje: file_type (5), sport (2), num_valid_steps, big_endian_steps, plus opcje FitWriter.to_bytes.
static func workout_file(wkt_name: String, steps: Array, opts: Dictionary = {}) -> PackedByteArray:
	var w := FitWriter.new()
	w.define(0, P.MESG_FILE_ID, [
		[0, 1, FitDecoder.BASE_ENUM], [1, 2, FitDecoder.BASE_UINT16], [2, 2, FitDecoder.BASE_UINT16],
		[3, 4, FitDecoder.BASE_UINT32Z], [4, 4, FitDecoder.BASE_UINT32],
	])
	w.write(0, [opts.get("file_type", P.FILE_TYPE_WORKOUT), MANUFACTURER_DEVELOPMENT, 1, 4242, TIME_CREATED])
	w.define(1, P.MESG_WORKOUT, [
		[P.WKT_SPORT, 1, FitDecoder.BASE_ENUM], [P.WKT_NUM_VALID_STEPS, 2, FitDecoder.BASE_UINT16],
		[P.WKT_NAME, FitWriter.string_size([wkt_name]), FitDecoder.BASE_STRING],
	])
	w.write(1, [opts.get("sport", P.SPORT_CYCLING), opts.get("num_valid_steps", steps.size()), wkt_name])
	var names: Array = []
	var notes: Array = []
	for s: Dictionary in steps:
		names.append(s.get("name"))
		notes.append(s.get("notes"))
	w.define(2, P.MESG_WORKOUT_STEP, [
		[P.STEP_MESSAGE_INDEX, 2, FitDecoder.BASE_UINT16],
		[P.STEP_NAME, FitWriter.string_size(names), FitDecoder.BASE_STRING],
		[P.STEP_DURATION_TYPE, 1, FitDecoder.BASE_ENUM],
		[P.STEP_DURATION_VALUE, 4, FitDecoder.BASE_UINT32],
		[P.STEP_TARGET_TYPE, 1, FitDecoder.BASE_ENUM],
		[P.STEP_TARGET_VALUE, 4, FitDecoder.BASE_UINT32],
		[P.STEP_CUSTOM_LOW, 4, FitDecoder.BASE_UINT32],
		[P.STEP_CUSTOM_HIGH, 4, FitDecoder.BASE_UINT32],
		[P.STEP_INTENSITY, 1, FitDecoder.BASE_ENUM],
		[P.STEP_NOTES, FitWriter.string_size(notes), FitDecoder.BASE_STRING],
		[P.STEP_SECONDARY_TARGET_TYPE, 1, FitDecoder.BASE_ENUM],
		[P.STEP_SECONDARY_CUSTOM_LOW, 4, FitDecoder.BASE_UINT32],
		[P.STEP_SECONDARY_CUSTOM_HIGH, 4, FitDecoder.BASE_UINT32],
	], bool(opts.get("big_endian_steps", false)))
	for i in steps.size():
		var s: Dictionary = steps[i]
		w.write(2, [
			s.get("message_index", i), s.get("name"), s.get("duration_type"), s.get("duration_value"),
			s.get("target_type"), s.get("target_value"), s.get("low"), s.get("high"), s.get("intensity"),
			s.get("notes"), s.get("secondary_type"), s.get("secondary_low"), s.get("secondary_high"),
		])
	return w.to_bytes(opts)


## Krok czasowy z celem mocy jako własny zakres (low/high: 0–1000 = % FTP, >1000 = W + 1000).
static func power_step(name: String, seconds: float, low: int, high: int, intensity: int) -> Dictionary:
	return {
		"name": name, "duration_type": P.DUR_TIME, "duration_value": roundi(seconds * 1000.0),
		"target_type": P.TGT_POWER, "target_value": 0, "low": low, "high": high, "intensity": intensity,
	}


## Krok powtórzenia: wróć do kroku from_index i wykonaj blok łącznie times razy.
static func repeat_step(from_index: int, times: int) -> Dictionary:
	return {"duration_type": P.DUR_REPEAT_UNTIL_STEPS_CMPLT, "duration_value": from_index, "target_value": times}


## Odpowiednik game/plans/kanion_4x4.json: rozgrzewka 50–75% (rampa), 4 x (4 min 105% / 3 min 55%),
## schłodzenie 65–45% (rampa w dół). Kadencja 95 jako drugi cel interwałów.
static func kanion_4x4(opts: Dictionary = {}) -> PackedByteArray:
	var work := power_step("Interwał 4 min", 240, 105, 105, P.INT_INTERVAL)
	work["secondary_type"] = P.TGT_CADENCE
	work["secondary_low"] = 95
	work["secondary_high"] = 95
	return workout_file("Kanion 4x4", [
		power_step("Rozgrzewka", 600, 50, 75, P.INT_WARMUP),
		work,
		power_step("Regeneracja", 180, 55, 55, P.INT_RECOVERY),
		repeat_step(1, 4),
		power_step("Schłodzenie", 600, 45, 65, P.INT_COOLDOWN),
	], opts)


## Trening w stylu Garmin Connect: krok „do Lap”, cele w watach (W + 1000), strefy mocy,
## krok bez celu, drugi cel kadencji, cel tętna i zagnieżdżone powtórzenia.
static func garmin_repeats_watts() -> PackedByteArray:
	var hard := power_step("Mocno", 120, 1300, 1320, P.INT_INTERVAL)
	hard["secondary_type"] = P.TGT_CADENCE
	hard["secondary_low"] = 90
	hard["secondary_high"] = 100
	return workout_file("Garmin: waty i powtórzenia", [
		{"name": "Rozgrzewka", "duration_type": P.DUR_OPEN, "target_type": P.TGT_OPEN, "intensity": P.INT_WARMUP},
		power_step("Tempo", 300, 1150, 1200, P.INT_ACTIVE),
		hard,
		{"notes": "Luz", "duration_type": P.DUR_TIME, "duration_value": 60000, "target_type": P.TGT_POWER, "target_value": 1, "intensity": P.INT_REST},
		repeat_step(2, 3),
		{"name": "Sprint", "duration_type": P.DUR_TIME, "duration_value": 30000, "target_type": P.TGT_POWER, "target_value": 6, "intensity": P.INT_INTERVAL},
		{"duration_type": P.DUR_TIME, "duration_value": 90000, "target_type": P.TGT_OPEN, "intensity": P.INT_RECOVERY},
		repeat_step(5, 2),
		repeat_step(1, 2),
		{"name": "Schłodzenie", "duration_type": P.DUR_TIME, "duration_value": 300000, "target_type": P.TGT_HEART_RATE, "target_value": 2, "intensity": P.INT_COOLDOWN},
	])


## Zapis aktywności (file_id typ 4) z kilkoma rekordami – gra ma go odrzucić z czytelnym błędem.
static func activity_file() -> PackedByteArray:
	var w := FitWriter.new()
	w.define(0, P.MESG_FILE_ID, [[0, 1, FitDecoder.BASE_ENUM], [1, 2, FitDecoder.BASE_UINT16], [4, 4, FitDecoder.BASE_UINT32]])
	w.write(0, [4, MANUFACTURER_DEVELOPMENT, TIME_CREATED])
	# record (20): timestamp, power, cadence
	w.define(1, 20, [[253, 4, FitDecoder.BASE_UINT32], [7, 2, FitDecoder.BASE_UINT16], [4, 1, FitDecoder.BASE_UINT8]])
	w.write(1, [TIME_CREATED, 210, 88])
	w.define(2, 20, [[7, 2, FitDecoder.BASE_UINT16], [4, 1, FitDecoder.BASE_UINT8]])
	for i in 5:
		w.write_compressed(2, (TIME_CREATED + 1 + i) & 0x1F, [215 + i, 89])
	return w.to_bytes()


## Wszystkie pliki fixture'ów FIT: nazwa pliku -> zawartość.
static func fit_files() -> Dictionary:
	var kanion := kanion_4x4()
	return {
		"kanion_4x4.fit": kanion,
		"garmin_powtorzenia_waty.fit": garmin_repeats_watts(),
		"aktywnosc.fit": activity_file(),
		"zla_suma_kontrolna.fit": kanion_4x4({"file_crc": "bad"}),
		"uciety.fit": kanion.slice(0, floori(kanion.size() / 2.0)),
	}
