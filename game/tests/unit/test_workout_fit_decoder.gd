extends TestCase
## Warstwa binarna FIT (FitDecoder): CRC, nagłówki, typy bazowe w obu kolejnościach bajtów,
## pola deweloperskie, skompresowane znaczniki czasu, uszkodzone pliki i fuzzing.

const D := preload("res://scripts/workout/fit_decoder.gd")


## Plik z file_id (typ workout) i jedną wiadomością workout z nazwą.
func _simple() -> FitWriter:
	var w := FitWriter.new()
	w.define(0, 0, [[0, 1, D.BASE_ENUM], [4, 4, D.BASE_UINT32]])
	w.write(0, [5, 1_100_000_000])
	w.define(1, 26, [[8, 6, D.BASE_STRING]])
	w.write(1, ["Test"])
	return w


func _decode(bytes: PackedByteArray) -> Dictionary:
	return FitDecoder.decode_all(bytes)


func _assert_error(bytes: PackedByteArray, fragment: String) -> void:
	var r := _decode(bytes)
	var message: String = r["error"]
	assert_true(message.contains(fragment), "błąd „%s” powinien zawierać „%s”" % [message, fragment])


func _assert_warning(r: Dictionary, fragment: String) -> void:
	var joined := " | ".join(PackedStringArray(r["warnings"]))
	assert_true(joined.contains(fragment), "ostrzeżenia „%s” powinny zawierać „%s”" % [joined, fragment])


func _with_records(raw: PackedByteArray, opts: Dictionary = {}) -> PackedByteArray:
	return FitWriter.new().write_raw(raw).to_bytes(opts)


func test_crc_matches_known_vector_and_both_implementations() -> void:
	var check := "123456789".to_ascii_buffer()
	assert_eq(FitDecoder.crc16(check), 0xBB3D, "CRC-16/ARC: wektor kontrolny")
	assert_eq(FitWriter.crc16(check), 0xBB3D, "wariant nibble z FIT SDK")
	assert_eq(FitDecoder.crc16(PackedByteArray()), 0)
	assert_eq(FitDecoder.crc16(check, 2, 5), FitDecoder.crc16(check.slice(2, 5)), "zakres [from, to)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 25:
		var bytes := PackedByteArray()
		for k in rng.randi_range(0, 300):
			bytes.append(rng.randi_range(0, 255))
		var crc := FitDecoder.crc16(bytes)
		assert_eq(FitWriter.crc16(bytes), crc, "obie implementacje zgodne (próba %d)" % i)
		FitWriter.append_uint(bytes, crc, 2, false)
		assert_eq(FitDecoder.crc16(bytes), 0, "dane + ich CRC dają 0")


func test_header_variants() -> void:
	var w := _simple()
	for opts: Dictionary in [{"header_size": 12}, {"header_size": 14}, {"header_size": 14, "header_crc": "zero"}, {"header_size": 16}]:
		var r := _decode(w.to_bytes(opts))
		assert_eq(r["error"], "", "nagłówek %s" % str(opts))
		assert_eq((r["messages"] as Array).size(), 2, "wiadomości przy nagłówku %s" % str(opts))
		assert_true((r["warnings"] as Array).is_empty(), "bez ostrzeżeń przy %s: %s" % [str(opts), str(r["warnings"])])
	var dec := FitDecoder.new()
	assert_true(dec.open(w.to_bytes()))
	assert_eq(dec.header_size, 14)
	assert_eq(dec.protocol_version, 0x20)
	assert_eq(dec.profile_version, 2132)
	assert_eq(dec.header_crc_status, "ok")
	assert_true(dec.open(w.to_bytes({"header_size": 12})))
	assert_eq(dec.header_crc_status, "brak", "nagłówek 12 B nie ma CRC")
	assert_true(dec.open(w.to_bytes({"header_crc": "zero"})))
	assert_eq(dec.header_crc_status, "brak", "CRC = 0 znaczy „nie liczono”")
	var bad := _decode(w.to_bytes({"header_crc": "bad"}))
	assert_eq(bad["error"], "", "złe CRC nagłówka to tylko ostrzeżenie")
	assert_eq((bad["messages"] as Array).size(), 2)
	_assert_warning(bad, "nagłówka")


func test_all_base_types_in_both_byte_orders() -> void:
	var fields := [
		[0, 1, D.BASE_ENUM], [1, 1, D.BASE_SINT8], [2, 1, D.BASE_UINT8], [3, 2, D.BASE_SINT16],
		[4, 2, D.BASE_UINT16], [5, 4, D.BASE_SINT32], [6, 4, D.BASE_UINT32], [7, 12, D.BASE_STRING],
		[8, 4, D.BASE_FLOAT32], [9, 8, D.BASE_FLOAT64], [10, 1, D.BASE_UINT8Z], [11, 2, D.BASE_UINT16Z],
		[12, 4, D.BASE_UINT32Z], [13, 3, D.BASE_BYTE], [14, 8, D.BASE_SINT64], [15, 8, D.BASE_UINT64],
		[16, 8, D.BASE_UINT64Z], [17, 6, D.BASE_UINT16], [18, 1, D.BASE_SINT8],
	]
	var values := [
		7, -5, 200, -1234, 54321, -123456789, 3_000_000_000, "Łódź", 1.5, -2.25, 9, 65000,
		4_000_000_000, PackedByteArray([1, 2, 3]), -9_000_000_000, 9_000_000_000, 12_345_678_901, [1, 2, 3], -1,
	]
	for big: bool in [false, true]:
		var w := FitWriter.new()
		w.define(3, 999, fields, big)
		w.write(3, values)
		w.write(3, [])
		var r := _decode(w.to_bytes())
		var label := "BE" if big else "LE"
		assert_eq(r["error"], "", label)
		var messages: Array = r["messages"]
		if messages.size() != 2:
			fail("%s: oczekiwano 2 wiadomości, jest %d" % [label, messages.size()])
			continue
		assert_eq(messages[0]["global"], 999, "%s: numer globalny" % label)
		assert_eq(messages[0]["local"], 3, "%s: typ lokalny" % label)
		var got: Dictionary = messages[0]["fields"]
		for i in values.size():
			var expected: Variant = values[i]
			if expected is float:
				assert_near(float(got[i]), expected, 1e-12, "%s: pole %d" % [label, i])
			else:
				assert_eq(got[i], expected, "%s: pole %d" % [label, i])
		var invalid: Dictionary = messages[1]["fields"]
		for i in values.size():
			assert_true(invalid[i] == null, "%s: pole %d z wartością nieprawidłową -> null (jest %s)" % [label, i, str(invalid[i])])


func test_invalid_markers_of_signed_and_z_types() -> void:
	var w := FitWriter.new()
	w.define(0, 1, [[0, 1, D.BASE_SINT8], [1, 2, D.BASE_SINT16], [2, 1, D.BASE_UINT8Z], [3, 4, D.BASE_UINT32], [4, 4, D.BASE_UINT16]])
	w.write(0, [127, 32767, 0, 0xFFFFFFFF, [5, null]])
	w.write(0, [-128, -32768, 255, 0, [null, null]])
	var r := _decode(w.to_bytes())
	var a: Dictionary = r["messages"][0]["fields"]
	var b: Dictionary = r["messages"][1]["fields"]
	assert_true(a[0] == null and a[1] == null, "0x7F / 0x7FFF to wartości nieprawidłowe typów ze znakiem")
	assert_true(a[2] == null, "0 to wartość nieprawidłowa typu z „z”")
	assert_true(a[3] == null, "0xFFFFFFFF w uint32")
	assert_eq(a[4], [5, null], "tablica z jednym elementem nieprawidłowym")
	assert_eq(b[0], -128)
	assert_eq(b[1], -32768)
	assert_eq(b[2], 255)
	assert_eq(b[3], 0, "0 w uint32 jest poprawne")
	assert_true(b[4] == null, "tablica samych nieprawidłowych -> null")


func test_developer_fields_are_skipped() -> void:
	var w := FitWriter.new()
	w.define(0, 0, [[0, 1, D.BASE_ENUM]])
	w.write(0, [5])
	w.define(1, 27, [[254, 2, D.BASE_UINT16], [2, 4, D.BASE_UINT32]], false, [[0, 4, 0], [1, 2, 0]])
	w.write(1, [3, 120000], PackedByteArray([1, 2, 3, 4, 5, 6]))
	w.write(1, [4, 60000], PackedByteArray([9, 9, 9, 9, 9, 9]))
	w.define(2, 27, [[254, 2, D.BASE_UINT16]], true, [[0, 3, 1]])
	w.write(2, [5], PackedByteArray([7, 7, 7]))
	var r := _decode(w.to_bytes())
	assert_eq(r["error"], "")
	var messages: Array = r["messages"]
	assert_eq(messages.size(), 4)
	if messages.size() == 4:
		assert_eq(messages[1]["fields"], {254: 3, 2: 120000}, "pola po pominięciu bajtów deweloperskich")
		assert_eq(messages[2]["fields"], {254: 4, 2: 60000})
		assert_eq(messages[3]["fields"], {254: 5}, "big endian z polem deweloperskim")


func test_compressed_timestamps() -> void:
	var w := FitWriter.new()
	w.define(0, 20, [[253, 4, D.BASE_UINT32], [7, 2, D.BASE_UINT16]])
	w.write(0, [1_000_000_030, 100])
	w.define(1, 20, [[7, 2, D.BASE_UINT16]])
	w.write_compressed(1, 31, [101])
	w.write_compressed(1, 2, [102])
	w.write_compressed(1, 2, [103])
	var r := _decode(w.to_bytes())
	assert_eq(r["error"], "")
	var messages: Array = r["messages"]
	assert_eq(messages.size(), 4)
	if messages.size() != 4:
		return
	var stamps: Array = []
	for m: Dictionary in messages:
		stamps.append(m["fields"][FitDecoder.FIELD_TIMESTAMP])
	assert_eq(stamps, [1_000_000_030, 1_000_000_031, 1_000_000_034, 1_000_000_034], "przesunięcia z przeniesieniem przez 32 s")
	assert_eq(messages[2]["fields"][7], 102)
	assert_true(messages[3].get("compressed_timestamp", false), "znacznik skompresowany oznaczony")
	assert_false(messages[0].has("compressed_timestamp"))
	var orphan := FitWriter.new()
	orphan.define(0, 20, [[7, 2, D.BASE_UINT16]])
	orphan.write_compressed(0, 5, [100])
	var o := _decode(orphan.to_bytes())
	assert_eq(o["error"], "", "skompresowany bez bazowego znacznika nie jest błędem")
	assert_eq((o["messages"] as Array).size(), 1)
	_assert_warning(o, "Skompresowany")


func test_local_type_redefinition() -> void:
	var w := FitWriter.new()
	w.define(0, 0, [[0, 1, D.BASE_ENUM]])
	w.write(0, [5])
	w.define(0, 26, [[8, 6, D.BASE_STRING]])
	w.write(0, ["Test"])
	var r := _decode(w.to_bytes())
	var messages: Array = r["messages"]
	assert_eq(messages.size(), 2)
	if messages.size() == 2:
		assert_eq(messages[0]["global"], 0)
		assert_eq(messages[1]["global"], 26)
		assert_eq(messages[1]["fields"][8], "Test")


func test_unknown_base_type_and_odd_size_read_as_bytes() -> void:
	var w := FitWriter.new()
	w.define(0, 50, [[1, 2, 0x55], [2, 3, D.BASE_UINT16]])
	w.write_raw(PackedByteArray([0x00, 1, 2, 3, 4, 5]))
	var r := _decode(w.to_bytes())
	assert_eq(r["error"], "")
	var f: Dictionary = r["messages"][0]["fields"]
	assert_eq(f[1], PackedByteArray([1, 2]), "nieznany typ bazowy jako bajty")
	assert_eq(f[2], PackedByteArray([3, 4, 5]), "rozmiar niepodzielny przez typ jako bajty")
	assert_eq((r["warnings"] as Array).size(), 2)


func test_invalid_utf8_string_does_not_break() -> void:
	var w := FitWriter.new()
	w.define(0, 26, [[8, 4, D.BASE_BYTE]])
	w.write(0, [PackedByteArray([0x41, 0xC3, 0x28, 0x42])])
	var bytes := w.to_bytes()
	# Zmieniamy typ pola z byte na string w definicji, żeby dekoder dostał złe UTF-8.
	var at := bytes.find(D.BASE_BYTE, 14)
	bytes[at] = D.BASE_STRING
	bytes.resize(bytes.size() - 2)
	FitWriter.append_uint(bytes, FitWriter.crc16(bytes), 2, false)
	var r := _decode(bytes)
	assert_eq(r["error"], "")
	assert_eq(str(r["messages"][0]["fields"][8]).length(), 4, "tekst odczytany znak po znaku")
	_assert_warning(r, "UTF-8")
	assert_true(FitDecoder.is_valid_utf8("Łódź – ok €".to_utf8_buffer()))
	assert_false(FitDecoder.is_valid_utf8(PackedByteArray([0xC0, 0x80])), "nadmiarowe kodowanie")
	assert_false(FitDecoder.is_valid_utf8(PackedByteArray([0xED, 0xA0, 0x80])), "surogat")
	assert_false(FitDecoder.is_valid_utf8(PackedByteArray([0xE2, 0x82])), "ucięty znak")


func test_structural_errors() -> void:
	_assert_error(PackedByteArray([14, 0x20]), "za krótki")
	var good := _simple().to_bytes()
	var no_sig := good.duplicate()
	no_sig[9] = 0x58
	_assert_error(no_sig, "sygnatury")
	var small_header := good.duplicate()
	small_header[0] = 10
	_assert_error(small_header, "rozmiar nagłówka")
	var huge_header := good.duplicate()
	huge_header[0] = 200
	_assert_error(huge_header, "ucięty")
	_assert_error(_with_records(PackedByteArray([0x00, 1, 2])), "niezdefiniowanego typu lokalnego 0")
	_assert_error(_with_records(PackedByteArray([0xA5, 1])), "niezdefiniowanego typu lokalnego 1")
	_assert_error(_with_records(PackedByteArray([0x40, 0, 0])), "niepełny rekord definicji")
	_assert_error(_with_records(PackedByteArray([0x40, 0, 0, 0, 0, 5, 1, 1, 0])), "niepełna lista pól")
	_assert_error(_with_records(PackedByteArray([0x40, 0, 7, 0, 0, 0])), "architektura 7")
	_assert_error(_with_records(PackedByteArray([0x60, 0, 0, 0, 0, 0])), "deweloperskich")
	_assert_error(_with_records(PackedByteArray([0x60, 0, 0, 0, 0, 0, 2, 0, 1])), "deweloperskich")
	_assert_error(_with_records(PackedByteArray([0x40, 0, 0, 0, 0, 1, 2, 4, 0x86, 0x00, 1, 2])), "niepełny rekord danych")
	_assert_error(_simple().to_bytes({"data_size": 9999}), "brakuje")
	var too_big := PackedByteArray()
	too_big.resize(FitDecoder.MAX_FILE_BYTES + 1)
	_assert_error(too_big, "za duży")


func test_size_quirks_are_warnings() -> void:
	var w := _simple()
	var extra := w.to_bytes()
	extra.append_array(PackedByteArray([1, 2, 3]))
	var r := _decode(extra)
	assert_eq(r["error"], "")
	assert_eq((r["messages"] as Array).size(), 2)
	_assert_warning(r, "dodatkowe bajty")
	r = _decode(w.to_bytes({"data_size": 0}))
	assert_eq(r["error"], "", "plik zapisany strumieniowo (rozmiar 0)")
	assert_eq((r["messages"] as Array).size(), 2)
	_assert_warning(r, "nie podaje rozmiaru")
	r = _decode(w.to_bytes({"file_crc": "none"}))
	assert_eq(r["error"], "")
	_assert_warning(r, "Brak sumy kontrolnej")
	r = _decode(w.to_bytes({"file_crc": "bad"}))
	assert_eq(r["error"], "", "złe CRC pliku to ostrzeżenie")
	assert_eq((r["messages"] as Array).size(), 2)
	_assert_warning(r, "Suma kontrolna pliku")
	r = _decode(w.to_bytes({"protocol": 0x30}))
	assert_eq(r["error"], "")
	_assert_warning(r, "Nowsza wersja")
	var dec := FitDecoder.new()
	dec.open(w.to_bytes())
	while not dec.next_message().is_empty():
		pass
	assert_true(dec.at_end())
	assert_true(dec.verify_file_crc(), "poprawne CRC")


func test_fuzzed_files_never_crash() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var seeds: Array[PackedByteArray] = [WorkoutFixtures.kanion_4x4(), WorkoutFixtures.garmin_repeats_watts(), WorkoutFixtures.activity_file()]
	var plans := 0
	var errors := 0
	for i in 400:
		var bytes: PackedByteArray = seeds[i % seeds.size()].duplicate()
		match rng.randi_range(0, 3):
			0:
				for k in rng.randi_range(1, 6):
					bytes[rng.randi_range(0, bytes.size() - 1)] = rng.randi_range(0, 255)
			1:
				bytes = bytes.slice(0, rng.randi_range(0, bytes.size()))
			2:
				for k in rng.randi_range(1, 4):
					bytes[rng.randi_range(14, bytes.size() - 3)] = rng.randi_range(0, 255)
			_:
				var at := rng.randi_range(14, bytes.size())
				var junk := PackedByteArray()
				for k in rng.randi_range(1, 12):
					junk.append(rng.randi_range(0, 255))
				bytes = bytes.slice(0, at) + junk + bytes.slice(at)
		var decoded: Variant = FitDecoder.decode_all(bytes)
		if not decoded is Dictionary:
			fail("decode_all nie zwrócił słownika (próba %d)" % i)
			return
		var r: Variant = WorkoutLoader.parse_fit(bytes)
		if not r is Dictionary:
			fail("parse_fit nie zwrócił słownika (próba %d)" % i)
			return
		var d: Dictionary = r
		if d["plan"] != null:
			plans += 1
		elif str(d["error"]) != "":
			errors += 1
		else:
			fail("brak planu i brak błędu (próba %d)" % i)
			return
	assert_true(plans > 0 and errors > 0, "fuzzing trafia w oba wyniki (plany %d, błędy %d)" % [plans, errors])


func test_random_records_behind_valid_header_never_crash() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 150:
		var junk := PackedByteArray()
		for k in rng.randi_range(0, 120):
			junk.append(rng.randi_range(0, 255))
		var bytes := _with_records(junk)
		var r: Variant = WorkoutLoader.parse_fit(bytes)
		if not r is Dictionary or ((r as Dictionary)["plan"] == null and str((r as Dictionary)["error"]) == ""):
			fail("losowe rekordy: zły wynik (próba %d)" % i)
			return
